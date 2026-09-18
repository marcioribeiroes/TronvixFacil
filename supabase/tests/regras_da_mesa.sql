-- =============================================================================
-- Tronvix Facil - o pedido feito na mesa
--
-- O salao e o terceiro caminho, ao lado da entrega e da retirada. Estes testes
-- cuidam do que e diferente nele, e do que nao pode mudar so porque o cliente
-- esta sentado:
--
--   diferente   mesa obrigatoria, sem frete, sem corrida, sem pedido minimo
--   igual       preco recalculado do cardapio, comissao, estoque, cupom
--
-- E cuidam do buraco obvio de um QR Code: pedir para a mesa de outra loja.
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
  when check_violation or insufficient_privilege or foreign_key_violation
    or not_null_violation or unique_violation or no_data_found then
    raise notice 'ok - rejeitado como esperado: %', p_contexto;
end;
$$;

create or replace function pg_temp.virar(p_user uuid)
returns void language sql as $$
  select set_config('request.jwt.claim.sub', p_user::text, true);
$$;

-- -----------------------------------------------------------------------------
-- Cenario: uma churrascaria com salao, e um concorrente com as mesas dele
-- -----------------------------------------------------------------------------
insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'dono@churrasco.test'),
  ('22222222-2222-2222-2222-222222222222', 'cliente@teste.test'),
  ('33333333-3333-3333-3333-333333333333', 'dono@vizinho.test');

insert into restaurants (id, slug, name, status, is_open,
                         delivery_fee_cents, min_order_cents, commission_bps)
values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'churrasco', 'Espeto de Prata',
   'approved', true, 900, 4000, 1000),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'vizinho', 'Vizinho',
   'approved', true, 900, 0, 1000);

insert into restaurant_members (restaurant_id, user_id, role) values
  ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'owner'),
  ('aaaaaaaa-0000-0000-0000-000000000002', '33333333-3333-3333-3333-333333333333', 'owner');

insert into categories (id, restaurant_id, name) values
  ('cccccccc-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'Carnes');

insert into products (id, restaurant_id, category_id, name, price_cents) values
  ('dddddddd-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001',
   'cccccccc-0000-0000-0000-000000000001', 'Picanha', 8900),
  ('dddddddd-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000001',
   'cccccccc-0000-0000-0000-000000000001', 'Agua', 500);

-- Um carrinho com o que for pedido. Devolve o id.
create or replace function pg_temp.carrinho(p_produto uuid, p_quantidade int default 1)
returns uuid language plpgsql as $$
declare v_cart uuid;
begin
  delete from carts
   where user_id = '22222222-2222-2222-2222-222222222222'
     and restaurant_id = 'aaaaaaaa-0000-0000-0000-000000000001';
  insert into carts (user_id, restaurant_id)
  values ('22222222-2222-2222-2222-222222222222', 'aaaaaaaa-0000-0000-0000-000000000001')
  returning id into v_cart;
  insert into cart_items (cart_id, product_id, quantity)
  values (v_cart, p_produto, p_quantidade);
  return v_cart;
end;
$$;

-- -----------------------------------------------------------------------------
-- Criar mesas
-- -----------------------------------------------------------------------------
do $$
declare v_criadas int;
begin
  perform pg_temp.virar('11111111-1111-1111-1111-111111111111');

  v_criadas := criar_mesas('aaaaaaaa-0000-0000-0000-000000000001', 4);
  perform pg_temp.conferir(v_criadas = 4, 'o dono cria quatro mesas de uma vez');

  perform pg_temp.conferir(
    (select count(*) from restaurant_tables
      where restaurant_id = 'aaaaaaaa-0000-0000-0000-000000000001'
        and label in ('Mesa 1','Mesa 2','Mesa 3','Mesa 4')) = 4,
    'as mesas saem numeradas de 1 a 4');

  -- Pedir mais quatro continua de onde parou, e nao repete a Mesa 1.
  v_criadas := criar_mesas('aaaaaaaa-0000-0000-0000-000000000001', 2);
  perform pg_temp.conferir(
    (select count(*) from restaurant_tables
      where restaurant_id = 'aaaaaaaa-0000-0000-0000-000000000001') = 6
    and exists (select 1 from restaurant_tables where label = 'Mesa 6'),
    'criar de novo continua da ultima: chega na Mesa 6');

  perform pg_temp.conferir(
    (select count(distinct code) from restaurant_tables
      where restaurant_id = 'aaaaaaaa-0000-0000-0000-000000000001') = 6,
    'cada mesa tem um codigo proprio');

  perform pg_temp.conferir(
    (select bool_and(code ~ '^[a-z0-9]{6,16}$' and code !~ '[ilo01]')
       from restaurant_tables
      where restaurant_id = 'aaaaaaaa-0000-0000-0000-000000000001'),
    'o codigo nao usa i, l, o, 0 nem 1 — alguem vai digitar a mao');

  perform pg_temp.conferir(
    not exists (select 1 from restaurant_tables
                 where restaurant_id = 'aaaaaaaa-0000-0000-0000-000000000001'
                   and code ilike '%1%'),
    'o codigo nao e o numero da mesa: pedido de casa para a mesa 7 nao se adivinha');
end;
$$;

do $$
begin
  -- O vizinho nao cria mesa na casa dos outros.
  perform pg_temp.virar('33333333-3333-3333-3333-333333333333');
  perform pg_temp.deve_falhar(
    $q$select criar_mesas('aaaaaaaa-0000-0000-0000-000000000001', 1)$q$,
    'criar mesa em estabelecimento alheio');

  perform pg_temp.virar('11111111-1111-1111-1111-111111111111');
  perform pg_temp.deve_falhar(
    $q$select criar_mesas('aaaaaaaa-0000-0000-0000-000000000001', 0)$q$,
    'criar zero mesas');
  perform pg_temp.deve_falhar(
    $q$select criar_mesas('aaaaaaaa-0000-0000-0000-000000000001', 500)$q$,
    'criar quinhentas mesas de uma vez');
end;
$$;

-- -----------------------------------------------------------------------------
-- O pedido na mesa
-- -----------------------------------------------------------------------------
do $$
declare
  v_cart uuid;
  v_pedido uuid;
  v_codigo text;
  v_o orders;
begin
  select code into v_codigo from restaurant_tables where label = 'Mesa 3';

  perform pg_temp.virar('22222222-2222-2222-2222-222222222222');
  v_cart := pg_temp.carrinho('dddddddd-0000-0000-0000-000000000001', 2);

  v_pedido := fechar_pedido(
    v_cart, 'dine_in', 'cash', 'on_delivery',
    null, null, null, null, null, v_codigo);

  select * into v_o from orders where id = v_pedido;

  perform pg_temp.conferir(v_o.fulfillment = 'dine_in', 'o pedido nasce como de mesa');
  perform pg_temp.conferir(v_o.table_label = 'Mesa 3',
    'o pedido diz em qual mesa foi feito');
  perform pg_temp.conferir(v_o.delivery_fee_cents = 0,
    'mesa nao paga frete');
  perform pg_temp.conferir(v_o.total_cents = 17800,
    'o total e so a mercadoria: 8900 x 2');
  perform pg_temp.conferir(v_o.commission_cents = 1780,
    'a comissao da plataforma continua valendo no salao');
  perform pg_temp.conferir(v_o.address_summary is null,
    'nao ha endereco: o cliente esta dentro do restaurante');
  perform pg_temp.conferir(v_o.status = 'received',
    'pagando na mesa, o pedido ja cai no balcao');
  perform pg_temp.conferir(
    not exists (select 1 from deliveries where order_id = v_pedido),
    'mesa nao cria corrida: ninguem vai entregar nada');
  perform pg_temp.conferir(
    (select count(*) from order_items where order_id = v_pedido) = 1,
    'os itens foram gravados');
end;
$$;

-- -----------------------------------------------------------------------------
-- O que a mesa dispensa
-- -----------------------------------------------------------------------------
do $$
declare
  v_cart uuid;
  v_pedido uuid;
  v_codigo text;
begin
  select code into v_codigo from restaurant_tables where label = 'Mesa 1';
  perform pg_temp.virar('22222222-2222-2222-2222-222222222222');

  -- A loja tem minimo de R$ 40,00. Uma agua de R$ 5,00 passa na mesa.
  v_cart := pg_temp.carrinho('dddddddd-0000-0000-0000-000000000002', 1);
  v_pedido := fechar_pedido(v_cart, 'dine_in', 'cash', 'on_delivery',
                            null, null, null, null, null, v_codigo);

  perform pg_temp.conferir(
    (select total_cents from orders where id = v_pedido) = 500,
    'o pedido minimo nao vale na mesa: quem esta sentado pede uma agua');

  -- E na entrega continua valendo.
  v_cart := pg_temp.carrinho('dddddddd-0000-0000-0000-000000000002', 1);
  perform pg_temp.deve_falhar(
    format($q$select fechar_pedido('%s', 'delivery', 'cash', 'on_delivery',
             'bbbbbbbb-0000-0000-0000-000000000009')$q$, v_cart),
    'a mesma agua pedida para entrega, abaixo do minimo');
end;
$$;

-- -----------------------------------------------------------------------------
-- O QR de outra loja
-- -----------------------------------------------------------------------------
do $$
declare
  v_cart uuid;
  v_codigo_do_vizinho text;
  v_codigo text;
begin
  perform pg_temp.virar('33333333-3333-3333-3333-333333333333');
  perform criar_mesas('aaaaaaaa-0000-0000-0000-000000000002', 1);
  select code into v_codigo_do_vizinho from restaurant_tables
   where restaurant_id = 'aaaaaaaa-0000-0000-0000-000000000002' limit 1;

  perform pg_temp.virar('22222222-2222-2222-2222-222222222222');
  v_cart := pg_temp.carrinho('dddddddd-0000-0000-0000-000000000001', 1);

  perform pg_temp.deve_falhar(
    format($q$select fechar_pedido('%s', 'dine_in', 'cash', 'on_delivery',
             null, null, null, null, null, '%s')$q$, v_cart, v_codigo_do_vizinho),
    'usar o QR da mesa de outro estabelecimento');

  v_cart := pg_temp.carrinho('dddddddd-0000-0000-0000-000000000001', 1);
  perform pg_temp.deve_falhar(
    format($q$select fechar_pedido('%s', 'dine_in', 'cash', 'on_delivery',
             null, null, null, null, null, 'naoexiste')$q$, v_cart),
    'codigo de mesa inventado');

  v_cart := pg_temp.carrinho('dddddddd-0000-0000-0000-000000000001', 1);
  perform pg_temp.deve_falhar(
    format($q$select fechar_pedido('%s', 'dine_in', 'cash', 'on_delivery')$q$, v_cart),
    'pedido de mesa sem informar mesa nenhuma');

  -- Mesa desativada: a loja fechou aquele canto do salao hoje.
  select code into v_codigo from restaurant_tables where label = 'Mesa 4';
  update restaurant_tables set is_active = false where code = v_codigo;

  perform pg_temp.virar('22222222-2222-2222-2222-222222222222');
  v_cart := pg_temp.carrinho('dddddddd-0000-0000-0000-000000000001', 1);
  perform pg_temp.deve_falhar(
    format($q$select fechar_pedido('%s', 'dine_in', 'cash', 'on_delivery',
             null, null, null, null, null, '%s')$q$, v_cart, v_codigo),
    'pedir numa mesa que a loja tirou de uso');
end;
$$;

-- -----------------------------------------------------------------------------
-- O caminho do pedido no salao
-- -----------------------------------------------------------------------------
do $$
declare
  v_cart uuid;
  v_pedido uuid;
  v_codigo text;
begin
  select code into v_codigo from restaurant_tables where label = 'Mesa 2';
  perform pg_temp.virar('22222222-2222-2222-2222-222222222222');
  v_cart := pg_temp.carrinho('dddddddd-0000-0000-0000-000000000001', 1);
  v_pedido := fechar_pedido(v_cart, 'dine_in', 'cash', 'on_delivery',
                            null, null, null, null, null, v_codigo);

  perform pg_temp.virar('11111111-1111-1111-1111-111111111111');
  update orders set status = 'confirmed' where id = v_pedido;
  update orders set status = 'preparing' where id = v_pedido;
  update orders set status = 'ready' where id = v_pedido;

  -- "Saiu para entrega" nao existe no salao. O garcom leva ate a mesa.
  perform pg_temp.deve_falhar(
    format($q$update orders set status = 'out_for_delivery' where id = '%s'$q$, v_pedido),
    'pedido de mesa saindo para entrega');

  update orders set status = 'delivered' where id = v_pedido;
  perform pg_temp.conferir(
    (select status from orders where id = v_pedido) = 'delivered',
    'de pronto, o pedido de mesa e servido direto');
end;
$$;

-- -----------------------------------------------------------------------------
-- A conta da mesa: varios pedidos, um total
-- -----------------------------------------------------------------------------
do $$
declare
  v_cart uuid;
  v_codigo text;
  v_mesa uuid;
begin
  select code, id into v_codigo, v_mesa from restaurant_tables where label = 'Mesa 5';

  -- A entrada, a bebida e a sobremesa, em tres pedidos, como acontece.
  perform pg_temp.virar('22222222-2222-2222-2222-222222222222');
  for _ in 1..3 loop
    v_cart := pg_temp.carrinho('dddddddd-0000-0000-0000-000000000002', 1);
    perform fechar_pedido(v_cart, 'dine_in', 'cash', 'on_delivery',
                          null, null, null, null, null, v_codigo);
  end loop;

  perform pg_temp.conferir(
    (select count(*) from orders where table_id = v_mesa) = 3,
    'a mesma mesa acumula varios pedidos');

  perform pg_temp.conferir(
    (select sum(total_cents) from orders
      where table_id = v_mesa and status not in ('cancelled','rejected')) = 1500,
    'a conta da mesa e a soma dos pedidos dela');
end;
$$;

-- -----------------------------------------------------------------------------
-- A mesa vai embora, o pedido fica
-- -----------------------------------------------------------------------------
do $$
declare v_pedido uuid;
begin
  perform pg_temp.virar('11111111-1111-1111-1111-111111111111');
  select id into v_pedido from orders where table_label = 'Mesa 3' limit 1;

  delete from restaurant_tables where label = 'Mesa 3';

  perform pg_temp.conferir(
    (select table_label from orders where id = v_pedido) = 'Mesa 3',
    'apagar a mesa nao apaga de onde o pedido veio: o rotulo foi copiado');
  perform pg_temp.conferir(
    (select table_id from orders where id = v_pedido) is null,
    'o vinculo com a mesa some, mas o pedido continua inteiro');
end;
$$;

rollback;
