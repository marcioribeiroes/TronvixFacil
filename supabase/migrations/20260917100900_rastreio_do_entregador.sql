-- =============================================================================
-- Tronvix Facil - o cliente vê o entregador chegando
--
-- couriers.current_latitude, current_longitude e location_updated_at existiam
-- desde a fundacao e ninguem escrevia nem lia. Esta migracao abre o caminho, e
-- a parte dificil dela nao e tecnica: e decidir QUEM pode ver onde uma pessoa
-- esta.
--
-- A escolha, e por que:
--
--   * NAO existe politica nova em `couriers`. Abrir a tabela ao cliente, ainda
--     que so durante a entrega, entregaria a linha inteira - documento,
--     reputacao, telefone do cadastro - para quem so precisa de dois numeros.
--     E, com politica, o Realtime passaria a transmitir essa linha inteira.
--
--   * Em vez disso, uma funcao que devolve exatamente tres campos: latitude,
--     longitude e quando foi medida.
--
--   * So enquanto a corrida esta em andamento. Entregue, cancelada ou ainda na
--     fila, a funcao nao devolve nada. O entregador para de ser visivel no
--     instante em que deixa de estar trabalhando para aquele cliente.
--
-- O preco dessa escolha e que o cliente CONSULTA em vez de receber por
-- Realtime. Para uma bolinha andando no mapa, consultar a cada poucos segundos
-- resolve - e nenhum dado a mais vaza no caminho.
-- =============================================================================

-- Os estados em que a corrida esta acontecendo de verdade.
create or replace function app.delivery_in_flight(p_status delivery_status)
returns boolean
language sql
immutable
as $$
  select p_status in ('assigned', 'heading_to_restaurant',
                      'picked_up', 'heading_to_customer');
$$;

-- -----------------------------------------------------------------------------
-- O entregador publica a propria posicao
--
-- Escreve so a propria linha - a politica de UPDATE em couriers ja exige
-- user_id = auth.uid(). Existe como funcao, e nao como UPDATE direto da tela,
-- para que o aplicativo nao precise conhecer o formato da tabela e para que a
-- medida chegue sempre com a hora do SERVIDOR: um celular com o relogio errado
-- faria a posicao parecer velha (ou do futuro) para quem esta olhando.
-- -----------------------------------------------------------------------------
create or replace function public.publicar_posicao(
  p_latitude numeric,
  p_longitude numeric
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_entregador uuid := app.my_courier_id();
begin
  if v_entregador is null then
    raise exception 'Só entregador publica posição.' using errcode = 'insufficient_privilege';
  end if;

  update couriers
     set current_latitude = p_latitude,
         current_longitude = p_longitude,
         location_updated_at = now()
   where id = v_entregador;
end;
$$;

grant execute on function public.publicar_posicao(numeric, numeric) to authenticated;

-- -----------------------------------------------------------------------------
-- O cliente pergunta onde esta o entregador do SEU pedido
-- -----------------------------------------------------------------------------
create or replace function public.onde_esta_o_entregador(p_order uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  d deliveries;
  c couriers;
begin
  select * into d from deliveries where order_id = p_order;

  if d.id is null or d.courier_id is null then
    return null;
  end if;

  -- Entregue, cancelada ou ainda na fila: ninguem esta a caminho de ninguem.
  if not app.delivery_in_flight(d.status) then
    return null;
  end if;

  -- Quem pode perguntar: o cliente do pedido, a equipe do estabelecimento, o
  -- proprio entregador e a plataforma. Mais ninguem - e a checagem e aqui
  -- dentro, porque a funcao roda como definer e nao passa por RLS.
  -- O `coalesce` e o `is not null` nao sao zelo excessivo: app.my_courier_id()
  -- devolve NULL para quem nao e entregador, `courier_id = NULL` da NULL, e
  -- `if not (... or NULL)` NUNCA dispara - a condicao inteira vira NULL, que
  -- em `if` vale como falso. Sem isto, qualquer pessoa autenticada recebia a
  -- posicao do entregador. Foi o que o teste de visibilidade pegou.
  if not coalesce(
    app.is_order_customer(p_order)
    or app.is_member(d.restaurant_id)
    or (app.my_courier_id() is not null and d.courier_id = app.my_courier_id())
    or app.is_platform_admin(),
    false
  ) then
    return null;
  end if;

  select * into c from couriers where id = d.courier_id;

  if c.current_latitude is null or c.current_longitude is null then
    return null;
  end if;

  -- Tres campos. Nem um a mais.
  return jsonb_build_object(
    'latitude', c.current_latitude,
    'longitude', c.current_longitude,
    'medido_em', c.location_updated_at
  );
end;
$$;

comment on function public.onde_esta_o_entregador(uuid) is
  'Onde esta o entregador deste pedido, enquanto a corrida acontece. Devolve latitude, longitude e a hora da medida - nunca a linha do entregador.';

grant execute on function public.onde_esta_o_entregador(uuid) to authenticated;
