-- =============================================================================
-- Quem cancelou o pedido.
--
-- `cancellation_reason` existia, e `order_status_history` guardava o auth.uid()
-- de quem mudou o estado. Mas nenhuma tela mostrava isso, e ler o historico
-- para descobrir quem desistiu e trabalho que ninguem faz no meio do almoco.
--
-- O pedido passa a dizer sozinho: cancelado pelo CLIENTE, pelo
-- ESTABELECIMENTO, ou pela PLATAFORMA. A diferenca importa:
--
--   cliente         desistiu. Nao ha o que cobrar de ninguem.
--   estabelecimento recusou. O cliente merece o motivo, e a loja acumula isso
--                   na reputacao dela.
--   plataforma      suporte resolvendo um problema.
--
-- Quem decide o autor e o BANCO, a partir de quem chamou — nao um parametro. A
-- alternativa seria o cliente cancelar dizendo que foi o restaurante.
-- =============================================================================

alter table orders
  add column if not exists cancelled_by text;

alter table orders drop constraint if exists orders_cancelled_by_valido;
alter table orders add constraint orders_cancelled_by_valido check (
  cancelled_by is null
  or cancelled_by in ('cliente', 'estabelecimento', 'plataforma')
);

comment on column orders.cancelled_by is
  'Quem cancelou. Escrito por app.cancelar_pedido a partir de quem chamou, nunca informado pela tela.';

-- -----------------------------------------------------------------------------
-- Cancelar
-- -----------------------------------------------------------------------------
create or replace function public.cancelar_pedido(
  p_pedido uuid,
  p_motivo text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pedido orders;
  v_autor text;
  v_motivo text := nullif(trim(coalesce(p_motivo, '')), '');
begin
  select * into v_pedido from orders where id = p_pedido;
  if v_pedido.id is null then
    raise exception 'Pedido nao encontrado.' using errcode = 'no_data_found';
  end if;

  -- Quem e quem. A ordem importa: o dono de um restaurante tambem pode ser
  -- cliente de outro, e o vinculo com ESTE pedido e que decide.
  if app.is_member(v_pedido.restaurant_id) then
    v_autor := 'estabelecimento';
  elsif app.is_platform_admin() then
    v_autor := 'plataforma';
  elsif v_pedido.customer_id = auth.uid() then
    v_autor := 'cliente';
  else
    raise exception 'Este pedido nao e seu.' using errcode = 'insufficient_privilege';
  end if;

  if v_pedido.status in ('cancelled', 'rejected') then
    raise exception 'Este pedido ja foi cancelado.' using errcode = 'check_violation';
  end if;
  if v_pedido.status = 'delivered' then
    raise exception 'Pedido entregue nao se cancela.' using errcode = 'check_violation';
  end if;

  -- O cliente desiste ate a loja aceitar. Depois disso a comida esta sendo
  -- feita, e quem paga a conta do cancelamento e o restaurante — a partir dai
  -- ele pede ao balcao, que decide.
  if v_autor = 'cliente' and v_pedido.status not in ('awaiting_payment', 'received') then
    raise exception
      'O restaurante ja comecou a preparar. Fale com a loja para cancelar.'
      using errcode = 'check_violation';
  end if;

  -- O motivo e obrigatorio para quem recusa, e opcional para quem desiste. O
  -- cliente nao deve explicacao; o restaurante deve.
  if v_autor = 'estabelecimento' and v_motivo is null then
    raise exception 'Diga o motivo: o cliente le esta mensagem.'
      using errcode = 'check_violation';
  end if;

  update orders
     set status = 'cancelled',
         cancelled_by = v_autor,
         cancellation_reason = coalesce(
           v_motivo,
           case v_autor
             when 'cliente' then 'Cancelado pelo cliente.'
             else 'Cancelado pela plataforma.'
           end)
   where id = p_pedido;

  -- A corrida morre junto: ninguem vai buscar comida que nao sera feita.
  update deliveries
     set status = 'cancelled'
   where order_id = p_pedido
     and status not in ('delivered', 'cancelled');
end;
$$;

revoke all on function public.cancelar_pedido(uuid, text) from public;
grant execute on function public.cancelar_pedido(uuid, text) to authenticated;

comment on function public.cancelar_pedido is
  'Cancela o pedido e registra QUEM cancelou, decidido pelo banco a partir de quem chamou. O cliente so desiste antes de a loja aceitar.';

-- -----------------------------------------------------------------------------
-- E a recusa do balcao passa a marcar o autor tambem
-- -----------------------------------------------------------------------------
-- `recusarPedido` leva o pedido para 'rejected' com o motivo. Quem recusa e
-- sempre o estabelecimento; deixar cancelled_by nulo ali faria a tela do
-- cliente dizer "cancelado" sem dizer por quem.
create or replace function app.marcar_autor_da_recusa()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'rejected' and old.status <> 'rejected' and new.cancelled_by is null then
    new.cancelled_by := 'estabelecimento';
  end if;
  return new;
end;
$$;

drop trigger if exists orders_autor_da_recusa on orders;
create trigger orders_autor_da_recusa
  before update on orders
  for each row execute function app.marcar_autor_da_recusa();
