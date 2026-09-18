-- =============================================================================
-- Tronvix Facil - o ciclo entre orders e deliveries
--
-- "infinite recursion detected in policy for relation deliveries".
--
-- As duas politicas se citavam com subconsulta inline:
--
--   orders     ... or exists (select 1 from deliveries d where d.order_id = orders.id
--                              and d.courier_id = app.my_courier_id())
--   deliveries ... or exists (select 1 from orders o where o.id = deliveries.order_id
--                              and o.customer_id = auth.uid())
--
-- Subconsulta dentro de politica roda como quem consulta - `authenticated` -,
-- entao ler orders dispara a politica de orders, que le deliveries, que dispara
-- a politica de deliveries, que le orders. O Postgres corta o ciclo com erro.
--
-- Nao aparecia nos testes locais porque la o psql conecta como superusuario, e
-- superusuario ignora RLS. Apareceu na primeira consulta do aplicativo contra o
-- Supabase de verdade, que e onde o papel e `authenticated` como na vida real.
--
-- A correcao troca as duas subconsultas por funcoes SECURITY DEFINER - o mesmo
-- recurso que o resto do projeto ja usa em app.can_see_order e pela mesma
-- razao, escrita la: "precisam ler sem disparar a propria RLS dessas tabelas, o
-- que causaria recursao infinita".
--
-- As regras de quem ve o que NAO mudam. Muda so por onde a pergunta passa.
-- =============================================================================

-- Este pedido e meu?
create or replace function app.is_order_customer(p_order uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from orders o
    where o.id = p_order and o.customer_id = auth.uid()
  );
$$;

comment on function app.is_order_customer(uuid) is
  'Le orders sem disparar a RLS de orders. Existe para quebrar o ciclo orders <-> deliveries.';

-- Sou o entregador designado deste pedido?
create or replace function app.is_order_courier(p_order uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from deliveries d
    where d.order_id = p_order
      and d.courier_id is not null
      and d.courier_id = app.my_courier_id()
  );
$$;

comment on function app.is_order_courier(uuid) is
  'Le deliveries sem disparar a RLS de deliveries. O outro lado do mesmo ciclo.';

-- -----------------------------------------------------------------------------
-- orders: o ramo do entregador deixa de ler deliveries diretamente
-- -----------------------------------------------------------------------------
drop policy if exists "pedido visivel a quem participa dele" on orders;

create policy "pedido visivel a quem participa dele"
  on orders for select
  to authenticated
  using (
    customer_id = auth.uid()
    or app.is_member(restaurant_id)
    or app.is_platform_admin()
    or app.is_order_courier(id)
  );

drop policy if exists "equipe e cliente atualizam o pedido" on orders;

create policy "equipe e cliente atualizam o pedido"
  on orders for update
  to authenticated
  using (
    app.is_member(restaurant_id)
    or app.is_platform_admin()
    or customer_id = auth.uid()
    or app.is_order_courier(id)
  )
  with check (
    app.is_member(restaurant_id)
    or app.is_platform_admin()
    or customer_id = auth.uid()
    or app.is_order_courier(id)
  );

-- -----------------------------------------------------------------------------
-- deliveries: o ramo do cliente deixa de ler orders diretamente
-- -----------------------------------------------------------------------------
-- O nome e o que esta em 20260917100200_pedidos.sql, sem "dela" no fim.
drop policy if exists "entrega visivel a quem participa" on deliveries;
drop policy if exists "entrega visivel a quem participa dela" on deliveries;

create policy "entrega visivel a quem participa"
  on deliveries for select
  to authenticated
  using (
    app.is_member(restaurant_id)
    or app.is_platform_admin()
    or courier_id = app.my_courier_id()
    -- A fila aberta e visivel a qualquer entregador aprovado: e dela que sai
    -- o aceite.
    or (status = 'searching_courier' and app.is_approved_courier())
    or app.is_order_customer(order_id)
  );
