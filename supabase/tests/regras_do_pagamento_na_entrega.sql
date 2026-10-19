-- =============================================================================
-- Tronvix Facil - pagar na entrega, e o fechamento da comissao
--
-- Como rodar:  npm run db:test
-- =============================================================================

\set ON_ERROR_STOP on

begin;

create or replace function pg_temp.conferir(p_condicao boolean, p_contexto text)
returns void language plpgsql as $$
begin
  if not coalesce(p_condicao, false) then
    raise exception 'FALHOU: %', p_contexto;
  end if;
  raise notice 'ok - %', p_contexto;
end;
$$;

create or replace function pg_temp.deve_falhar(p_sql text, p_contexto text)
returns void language plpgsql as $$
begin
  execute p_sql;
  raise exception 'FALHOU: % deveria ter sido rejeitado, mas passou.', p_contexto;
exception
  when check_violation or insufficient_privilege or no_data_found then
    raise notice 'ok - rejeitado como esperado: %', p_contexto;
end;
$$;

create or replace function pg_temp.virar(p_user uuid)
returns void language sql as $$
  select set_config('request.jwt.claim.sub', p_user::text, true);
$$;

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'dono@teste.test'),
  ('22222222-2222-2222-2222-222222222222', 'cliente@teste.test'),
  ('33333333-3333-3333-3333-333333333333', 'plataforma@teste.test'),
  ('44444444-4444-4444-4444-444444444444', 'dono-vizinho@teste.test');

select set_config('request.jwt.claim.role', 'service_role', true);
update profiles set platform_role = 'platform_admin'
 where id = '33333333-3333-3333-3333-333333333333';
select set_config('request.jwt.claim.role', '', true);

-- Loja SEM chave Pix: Pix na entrega tem de funcionar mesmo assim.
insert into restaurants (id, slug, name, status, is_open, min_order_cents, commission_bps)
values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'loja', 'A Loja', 'approved', true, 0, 1000),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'vizinha', 'Vizinha', 'approved', true, 0, 1000);

insert into restaurant_members (restaurant_id, user_id, role) values
  ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'owner'),
  ('aaaaaaaa-0000-0000-0000-000000000002', '44444444-4444-4444-4444-444444444444', 'owner');

insert into categories (id, restaurant_id, name)
values ('cccccccc-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'Pratos');
insert into products (id, restaurant_id, category_id, name, price_cents)
values ('dddddddd-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000001', 'Prato', 3000);

create or replace function pg_temp.carrinho()
returns uuid language plpgsql as $$
declare v_cart uuid;
begin
  perform pg_temp.virar('22222222-2222-2222-2222-222222222222');
  delete from carts where user_id = '22222222-2222-2222-2222-222222222222';
  insert into carts (user_id, restaurant_id)
  values ('22222222-2222-2222-2222-222222222222', 'aaaaaaaa-0000-0000-0000-000000000001')
  returning id into v_cart;
  insert into cart_items (cart_id, product_id, quantity)
  values (v_cart, 'dddddddd-0000-0000-0000-000000000001', 1);
  return v_cart;
end;
$$;

-- -----------------------------------------------------------------------------
-- Formas de pagamento
-- -----------------------------------------------------------------------------
do $$
declare v_id uuid;
begin
  v_id := fechar_pedido(pg_temp.carrinho(), 'pickup', 'pix', 'on_delivery');
  perform pg_temp.conferir(
    (select status from orders where id = v_id) = 'received',
    'Pix na entrega vai direto para o balcao, sem esperar pagamento');
  perform pg_temp.conferir(
    (select timing = 'on_delivery' and status = 'pending' from payments where order_id = v_id),
    'e fica a receber no caixa');

  perform pg_temp.deve_falhar(
    format($q$select fechar_pedido('%s', 'pickup', 'credit_card', 'online')$q$, pg_temp.carrinho()),
    'cartao pelo app, sem operadora para cobrar');
  perform pg_temp.deve_falhar(
    format($q$select fechar_pedido('%s', 'pickup', 'pix', 'online')$q$, pg_temp.carrinho()),
    'Pix pelo app numa loja sem chave Pix');
end;
$$;

-- -----------------------------------------------------------------------------
-- Fechamento da comissao
-- -----------------------------------------------------------------------------
do $$
declare v_id uuid; v_ext uuid; v_mes date := date_trunc('month', now() at time zone 'America/Sao_Paulo')::date;
begin
  -- Dois pedidos entregues e um cancelado.
  perform pg_temp.virar('11111111-1111-1111-1111-111111111111');
  for i in 1..2 loop
    v_id := fechar_pedido(pg_temp.carrinho(), 'pickup', 'cash', 'on_delivery');
    perform pg_temp.virar('11111111-1111-1111-1111-111111111111');
    update orders set status = 'confirmed' where id = v_id;
    update orders set status = 'preparing' where id = v_id;
    update orders set status = 'ready' where id = v_id;
    update orders set status = 'delivered' where id = v_id;
  end loop;
  v_id := fechar_pedido(pg_temp.carrinho(), 'pickup', 'cash', 'on_delivery');
  perform cancelar_pedido(v_id);

  perform pg_temp.virar('11111111-1111-1111-1111-111111111111');
  perform pg_temp.deve_falhar(
    format($q$select gerar_fechamento_de_comissoes('%s')$q$, v_mes),
    'loja fechando a propria comissao');

  perform pg_temp.virar('33333333-3333-3333-3333-333333333333');
  perform gerar_fechamento_de_comissoes(v_mes);

  select id into v_ext from commission_statements
   where restaurant_id = 'aaaaaaaa-0000-0000-0000-000000000001' and month = v_mes;
  perform pg_temp.conferir(
    (select orders_count = 2 and sales_cents = 6000 and commission_cents = 600 and status = 'open'
       from commission_statements where id = v_ext),
    'o mes soma so os pedidos entregues: 2 pedidos, R$ 60, comissao R$ 6');

  -- A loja ve o proprio extrato; a vizinha nao.
  perform pg_temp.virar('11111111-1111-1111-1111-111111111111');
  set local role authenticated;
  perform pg_temp.conferir((select count(*) from commission_statements) = 1,
    'a loja ve o quanto deve');
  reset role;
  perform pg_temp.virar('44444444-4444-4444-4444-444444444444');
  set local role authenticated;
  perform pg_temp.conferir((select count(*) from commission_statements) = 0,
    'a loja vizinha nao ve a comissao dos outros');
  reset role;

  -- Pago, nao muda mais.
  perform pg_temp.virar('33333333-3333-3333-3333-333333333333');
  perform marcar_comissao_paga(v_ext, 'Pix recebido');
  perform gerar_fechamento_de_comissoes(v_mes);
  perform pg_temp.conferir(
    (select status = 'paid' and paid_at is not null and commission_cents = 600
       from commission_statements where id = v_ext),
    'extrato pago nao e recalculado');
  perform pg_temp.deve_falhar(
    format($q$select marcar_comissao_paga('%s')$q$, v_ext),
    'dar baixa duas vezes');
end;
$$;

rollback;
