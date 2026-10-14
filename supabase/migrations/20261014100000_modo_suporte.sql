-- =============================================================================
-- Tronvix Facil - modo suporte
--
-- A equipe da plataforma entra no painel de uma loja para ver o que o dono ve
-- e corrigir o que precisa: tirar um item do ar, cancelar um lancamento
-- errado, conferir o caixa. Sem virar dono de todas as lojas — o que poria o
-- suporte na equipe da loja, desligaria a trava do ultimo dono e mandaria o
-- aviso de cada pedido de cada loja para o celular de quem da suporte.
--
-- O banco ja deixa o administrador agir em qualquer loja (as politicas e as
-- funcoes aceitam `app.is_platform_admin()`). O que falta e o registro: quem
-- entrou em qual loja, quando, e quando saiu. A loja ve esse registro — saber
-- que o suporte esteve ali e o minimo de transparencia.
-- =============================================================================

create table support_sessions (
  id uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references restaurants (id) on delete cascade,
  admin_id uuid references auth.users (id) on delete set null,
  started_at timestamptz not null default now(),
  ended_at timestamptz
);

create index support_sessions_restaurant_idx on support_sessions (restaurant_id, started_at desc);

alter table support_sessions enable row level security;

-- Leitura para a plataforma e para a gestao da loja. Escrita so pelas funcoes.
create policy "sessao de suporte visivel a plataforma e a gestao da loja"
  on support_sessions for select
  to authenticated
  using (app.is_platform_admin() or app.can_manage(restaurant_id));

-- Explicito: o Supabase ja concede por padrao, mas o Postgres puro dos testes
-- nao, e a politica sem o grant nao vale nada.
grant select on support_sessions to authenticated;

comment on table support_sessions is
  'Cada vez que alguem da plataforma entrou no painel de uma loja em modo suporte.';

create or replace function public.entrar_como_suporte(p_restaurante uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if not app.is_platform_admin() then
    raise exception 'Somente a equipe da plataforma entra como suporte.'
      using errcode = 'insufficient_privilege';
  end if;
  if not exists (select 1 from restaurants where id = p_restaurante and deleted_at is null) then
    raise exception 'Estabelecimento nao encontrado.' using errcode = 'no_data_found';
  end if;

  -- Uma sessao aberta por vez: entrar em outra loja encerra a anterior.
  update support_sessions
     set ended_at = now()
   where admin_id = auth.uid() and ended_at is null;

  insert into support_sessions (restaurant_id, admin_id)
  values (p_restaurante, auth.uid())
  returning id into v_id;

  return v_id;
end;
$$;

create or replace function public.sair_do_suporte()
returns void
language sql
security definer
set search_path = public
as $$
  update support_sessions
     set ended_at = now()
   where admin_id = auth.uid() and ended_at is null;
$$;

revoke all on function public.entrar_como_suporte(uuid) from public;
revoke all on function public.sair_do_suporte() from public;
grant execute on function public.entrar_como_suporte(uuid) to authenticated;
grant execute on function public.sair_do_suporte() to authenticated;

-- -----------------------------------------------------------------------------
-- Chamar entregador era a unica acao da loja que barrava a plataforma
-- -----------------------------------------------------------------------------
create or replace function public.chamar_entregador(
  p_pedido uuid,
  p_minutos int
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pedido orders;
begin
  select * into v_pedido from orders where id = p_pedido;
  if v_pedido.id is null then
    raise exception 'Pedido nao encontrado.' using errcode = 'no_data_found';
  end if;

  if not (app.is_member(v_pedido.restaurant_id) or app.is_platform_admin()) then
    raise exception 'So quem trabalha no estabelecimento chama entregador.'
      using errcode = 'insufficient_privilege';
  end if;

  if v_pedido.fulfillment <> 'delivery' then
    raise exception 'Retirada e mesa nao tem entregador.'
      using errcode = 'check_violation';
  end if;

  -- De 'ready' tambem se chama: e a loja que so lembrou do entregador depois
  -- que a comida ficou pronta. E o que acontece hoje, e continua valendo.
  if v_pedido.status not in ('confirmed', 'preparing', 'ready') then
    raise exception 'Nao da para chamar entregador para um pedido em "%".', v_pedido.status
      using errcode = 'check_violation';
  end if;

  if p_minutos is null or p_minutos < 0 or p_minutos > 180 then
    raise exception 'A previsao tem de estar entre 0 e 180 minutos.'
      using errcode = 'check_violation';
  end if;

  update orders
     set ready_forecast_at = now() + make_interval(mins => p_minutos)
   where id = p_pedido;

  -- So a corrida que ainda nao saiu da fila. Chamar de novo serve para
  -- corrigir a previsao quando a cozinha atrasa, e nao deve devolver a fila
  -- uma corrida que alguem ja aceitou.
  update deliveries
     set status = 'searching_courier'
   where order_id = p_pedido
     and status = 'pending';
end;
$$;

comment on function public.chamar_entregador(uuid, int) is
  'Poe a corrida na fila e grava a previsao de quando a comida fica pronta. Chamavel de novo para corrigir a previsao, sem tirar a corrida de quem ja aceitou.';

revoke all on function public.chamar_entregador(uuid, int) from public;
grant execute on function public.chamar_entregador(uuid, int) to authenticated;
