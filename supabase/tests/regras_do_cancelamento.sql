-- =============================================================================
-- Tronvix Facil - quem cancelou o pedido
--
-- A diferenca entre "o cliente desistiu" e "o restaurante recusou" nao e
-- detalhe: uma nao cobra nada de ninguem, a outra deve explicacao e pesa na
-- reputacao da loja. Por isso o autor e decidido pelo BANCO, a partir de quem
-- chamou — e nao por um parametro que a tela informa.
--
-- Como rodar:  npm run db:test
-- =============================================================================

\set ON_ERROR_STOP on

begin;

create or replace function pg_temp.conferir(p_condicao boolean, p_contexto text)
returns void language plpgsql as $$
begin
  if not p_condicao then
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
  ('33333333-3333-3333-3333-333333333333', 'estranho@teste.test');

insert into restaurants (id, slug, name, status, is_open, min_order_cents)
values ('aaaaaaaa-0000-0000-0000-000000000001', 'loja', 'A Loja', 'approved', true, 0);

insert into restaurant_members (restaurant_id, user_id, role)
values ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'owner');

insert into categories (id, restaurant_id, name)
values ('cccccccc-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'Pratos');

insert into products (id, restaurant_id, category_id, name, price_cents)
values ('dddddddd-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000001', 'Prato', 3000);

-- Um pedido novo, pronto para ser cancelado.
create or replace function pg_temp.pedido()
returns uuid language plpgsql as $$
declare v_cart uuid; v_id uuid;
begin
  perform pg_temp.virar('22222222-2222-2222-2222-222222222222');
  delete from carts where user_id = '22222222-2222-2222-2222-222222222222';
  insert into carts (user_id, restaurant_id)
  values ('22222222-2222-2222-2222-222222222222', 'aaaaaaaa-0000-0000-0000-000000000001')
  returning id into v_cart;
  insert into cart_items (cart_id, product_id, quantity)
  values (v_cart, 'dddddddd-0000-0000-0000-000000000001', 1);
  v_id := fechar_pedido(v_cart, 'pickup', 'cash', 'on_delivery');
  return v_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- O cliente desiste
-- -----------------------------------------------------------------------------
do $$
declare v_id uuid; v_o orders;
begin
  v_id := pg_temp.pedido();

  perform pg_temp.virar('22222222-2222-2222-2222-222222222222');
  perform cancelar_pedido(v_id);

  select * into v_o from orders where id = v_id;

  perform pg_temp.conferir(v_o.status = 'cancelled', 'o pedido fica cancelado');
  perform pg_temp.conferir(v_o.cancelled_by = 'cliente',
    'e o banco registra que foi o CLIENTE — nao a tela que disse');
  perform pg_temp.conferir(v_o.cancellation_reason = 'Cancelado pelo cliente.',
    'sem motivo escrito, entra o texto padrao: o cliente nao deve explicacao');
  perform pg_temp.conferir(v_o.cancelled_at is not null,
    'a hora do cancelamento e carimbada pelo banco');
end;
$$;

-- -----------------------------------------------------------------------------
-- O restaurante recusa, e deve o motivo
-- -----------------------------------------------------------------------------
do $$
declare v_id uuid; v_o orders;
begin
  v_id := pg_temp.pedido();

  perform pg_temp.virar('11111111-1111-1111-1111-111111111111');
  perform pg_temp.deve_falhar(
    format($q$select cancelar_pedido('%s')$q$, v_id),
    'o estabelecimento cancelando sem dizer o motivo');

  perform cancelar_pedido(v_id, 'Acabou o ingrediente.');
  select * into v_o from orders where id = v_id;

  perform pg_temp.conferir(v_o.cancelled_by = 'estabelecimento',
    'quem tem vinculo com a loja cancela como estabelecimento');
  perform pg_temp.conferir(v_o.cancellation_reason = 'Acabou o ingrediente.',
    'e o motivo e o que o cliente vai ler');
end;
$$;

-- -----------------------------------------------------------------------------
-- Depois que a cozinha comeca, o cliente nao desiste sozinho
-- -----------------------------------------------------------------------------
do $$
declare v_id uuid;
begin
  v_id := pg_temp.pedido();

  perform pg_temp.virar('11111111-1111-1111-1111-111111111111');
  update orders set status = 'confirmed' where id = v_id;

  perform pg_temp.virar('22222222-2222-2222-2222-222222222222');
  perform pg_temp.deve_falhar(
    format($q$select cancelar_pedido('%s')$q$, v_id),
    'o cliente cancelando depois de a loja aceitar');

  -- Mas a loja ainda pode, porque quem paga a conta e ela.
  perform pg_temp.virar('11111111-1111-1111-1111-111111111111');
  perform cancelar_pedido(v_id, 'Faltou entregador.');
  perform pg_temp.conferir(
    (select cancelled_by from orders where id = v_id) = 'estabelecimento',
    'a loja cancela em qualquer ponto, e assume o motivo');
end;
$$;

-- -----------------------------------------------------------------------------
-- O que nao se cancela
-- -----------------------------------------------------------------------------
do $$
declare v_id uuid;
begin
  v_id := pg_temp.pedido();

  -- Quem nao tem nada com o pedido.
  perform pg_temp.virar('33333333-3333-3333-3333-333333333333');
  perform pg_temp.deve_falhar(
    format($q$select cancelar_pedido('%s')$q$, v_id),
    'um estranho cancelando pedido alheio');

  -- Duas vezes.
  perform pg_temp.virar('22222222-2222-2222-2222-222222222222');
  perform cancelar_pedido(v_id);
  perform pg_temp.deve_falhar(
    format($q$select cancelar_pedido('%s')$q$, v_id),
    'cancelar o que ja esta cancelado');
end;
$$;

do $$
declare v_id uuid;
begin
  v_id := pg_temp.pedido();
  perform pg_temp.virar('11111111-1111-1111-1111-111111111111');
  update orders set status = 'confirmed' where id = v_id;
  update orders set status = 'preparing' where id = v_id;
  update orders set status = 'ready' where id = v_id;
  update orders set status = 'delivered' where id = v_id;

  perform pg_temp.deve_falhar(
    format($q$select cancelar_pedido('%s')$q$, v_id),
    'cancelar pedido que ja foi entregue');
end;
$$;

-- -----------------------------------------------------------------------------
-- A corrida morre junto
-- -----------------------------------------------------------------------------
do $$
declare v_cart uuid; v_id uuid;
begin
  perform pg_temp.virar('22222222-2222-2222-2222-222222222222');
  insert into addresses (id, user_id, street, number, district, city, state, postal_code)
  values ('bbbbbbbb-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222',
          'Rua A', '1', 'Centro', 'Goiania', 'GO', '74000000');

  delete from carts where user_id = '22222222-2222-2222-2222-222222222222';
  insert into carts (user_id, restaurant_id)
  values ('22222222-2222-2222-2222-222222222222', 'aaaaaaaa-0000-0000-0000-000000000001')
  returning id into v_cart;
  insert into cart_items (cart_id, product_id, quantity)
  values (v_cart, 'dddddddd-0000-0000-0000-000000000001', 1);

  v_id := fechar_pedido(v_cart, 'delivery', 'cash', 'on_delivery',
                        'bbbbbbbb-0000-0000-0000-000000000001');

  perform pg_temp.conferir(
    (select count(*) from deliveries where order_id = v_id) = 1,
    'o pedido de entrega nasceu com corrida');

  perform cancelar_pedido(v_id);

  perform pg_temp.conferir(
    (select status from deliveries where order_id = v_id) = 'cancelled',
    'cancelar o pedido cancela a corrida: ninguem busca comida que nao sera feita');
end;
$$;

-- -----------------------------------------------------------------------------
-- A recusa pelo caminho antigo tambem marca o autor
-- -----------------------------------------------------------------------------
do $$
declare v_id uuid;
begin
  v_id := pg_temp.pedido();

  perform pg_temp.virar('11111111-1111-1111-1111-111111111111');
  update orders set status = 'rejected', cancellation_reason = 'Fora da area.'
   where id = v_id;

  perform pg_temp.conferir(
    (select cancelled_by from orders where id = v_id) = 'estabelecimento',
    'recusa pelo balcao marca o autor sozinha, pelo gatilho');
end;
$$;

rollback;
