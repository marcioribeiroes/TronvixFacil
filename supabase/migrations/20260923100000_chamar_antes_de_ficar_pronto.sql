-- =============================================================================
-- Chamar o entregador antes da comida ficar pronta.
--
-- Ate aqui, um clique so do balcao fazia duas coisas: marcava o pedido como
-- `out_for_delivery` e, so entao, punha a corrida na fila. Isso tinha dois
-- defeitos:
--
--   O pedido dizia "saiu para entrega" com a comida no balcao e ninguem para
--   leva-la. A tela do cliente mentia.
--
--   Ninguem procurava entregador enquanto a comida cozinhava. Quando ela
--   ficava pronta, comecava a espera - agora com a comida esfriando. O balcao
--   aprende rapido a clicar cedo para ter alguem a caminho, e ai a mentira da
--   tela vira rotina.
--
-- O desenho passa a separar os dois momentos:
--
--   `chamar_entregador`  pode ser chamado ainda no preparo, e grava QUANDO a
--                        comida deve ficar pronta. O entregador decide com esse
--                        numero na mao, em vez de correr e esperar.
--
--   `out_for_delivery`   passa a ser consequencia da retirada, nao um clique.
--                        Quando a entrega vira `picked_up`, o pedido sai.
--
-- O caminho antigo continua valendo: quem despacha na mao - o dono que leva o
-- proprio pedido, a loja sem entregador cadastrado - nao perde nada.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- A previsao
-- -----------------------------------------------------------------------------
-- Cuidado ao ler: `ready_at` e `ready_forecast_at` parecem irmaos e sao
-- opostos. O primeiro e escrito pelo gatilho NO MOMENTO em que o pedido fica
-- pronto - e registro do passado, e serve para medir. O segundo e promessa,
-- escrita antes, e serve para alguem decidir. Confundir os dois faz o relatorio
-- de tempo medio medir intencao em vez de realidade.
alter table orders
  add column if not exists ready_forecast_at timestamptz;

comment on column orders.ready_forecast_at is
  'Previsao de quando a comida fica pronta, escrita por public.chamar_entregador. E promessa, nao medicao: quem mede e ready_at.';

-- -----------------------------------------------------------------------------
-- Chamar o entregador
-- -----------------------------------------------------------------------------
-- Existe como funcao, e nao como duas escritas na Server Action, porque as duas
-- coisas tem de acontecer juntas. Separadas, daria para existir pedido com
-- previsao e sem corrida na fila - promessa feita a ninguem.
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

  if not app.is_member(v_pedido.restaurant_id) then
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

-- -----------------------------------------------------------------------------
-- "Peguei o pedido" exige que exista pedido para pegar
-- -----------------------------------------------------------------------------
-- Agora que a corrida e aceita durante o preparo, o entregador chega antes da
-- comida. Sem esta trava, ele apertaria "peguei" com a cozinha ainda no fogo e
-- o pedido iria para a rua sem ter saido da chapa.
--
-- Aceita 'out_for_delivery' alem de 'ready' de proposito: no caminho antigo o
-- balcao ja marcou o pedido como saido antes de existir entregador. Exigir so
-- 'ready' quebraria o fluxo que funciona hoje.
create or replace function app.guard_delivery_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status_do_pedido order_status;
begin
  if new.status = old.status then
    return new;
  end if;

  if not app.delivery_transition_allowed(old.status, new.status) then
    raise exception 'Transicao de entrega invalida: % -> %', old.status, new.status
      using errcode = 'check_violation';
  end if;

  if new.status = 'picked_up' then
    select status into v_status_do_pedido from orders where id = new.order_id;

    if v_status_do_pedido not in ('ready', 'out_for_delivery') then
      raise exception 'O pedido ainda nao esta pronto para ser retirado.'
        using errcode = 'check_violation';
    end if;
  end if;

  -- Devolver a corrida a fila limpa o entregador anterior.
  if new.status = 'searching_courier' then
    new.courier_id := null;
    new.assigned_at := null;
  end if;

  new.assigned_at   := case when new.status = 'assigned' then now() else new.assigned_at end;
  new.picked_up_at  := case when new.status = 'picked_up' then now() else new.picked_up_at end;
  new.delivered_at  := case when new.status = 'delivered' then now() else new.delivered_at end;
  new.cancelled_at  := case when new.status = 'cancelled' then now() else new.cancelled_at end;

  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- Sair para entrega vira consequencia da retirada
-- -----------------------------------------------------------------------------
-- O `where status = 'ready'` e o que torna isto seguro de rodar sempre: no
-- caminho antigo o pedido ja esta em 'out_for_delivery' quando o entregador
-- retira, e ai o update nao acha linha e nao faz nada.
create or replace function app.promote_order_on_pickup()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'picked_up' and old.status is distinct from 'picked_up' then
    update orders
       set status = 'out_for_delivery'
     where id = new.order_id
       and status = 'ready';
  end if;

  return null;
end;
$$;

comment on function app.promote_order_on_pickup is
  'Quando a entrega e retirada, o pedido sai para a rua. Antes disto, "saiu para entrega" era um clique do balcao que podia acontecer sem entregador nenhum.';

drop trigger if exists deliveries_promote_order_on_pickup on deliveries;
create trigger deliveries_promote_order_on_pickup
  after update of status on deliveries
  for each row execute function app.promote_order_on_pickup();
