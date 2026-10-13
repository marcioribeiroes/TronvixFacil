-- =============================================================================
-- Tronvix Facil - a loja lanca o pedido
--
-- Balcao, mesa e entrega por telefone: mesmas regras de preco do aplicativo,
-- sem comissao, ja aceito, no caixa e no estoque.
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
  ('11111111-1111-1111-1111-111111111111', 'atendente@teste.test'),
  ('22222222-2222-2222-2222-222222222222', 'cliente@teste.test');

-- Loja com pedido minimo, frete e comissao: nada disso pode atrapalhar o
-- balcao, e o frete tem de valer na entrega.
insert into restaurants (id, slug, name, status, is_open, min_order_cents,
                         delivery_fee_cents, free_delivery_above_cents, commission_bps)
values ('aaaaaaaa-0000-0000-0000-000000000001', 'loja', 'A Loja', 'approved', false,
        5000, 700, 10000, 1200);

insert into restaurant_members (restaurant_id, user_id, role)
values ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'staff');

insert into categories (id, restaurant_id, name)
values ('cccccccc-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'Pratos');

insert into products (id, restaurant_id, category_id, name, price_cents, track_stock, stock_quantity)
values
  ('dddddddd-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001',
   'cccccccc-0000-0000-0000-000000000001', 'Agua', 400, true, 20),
  ('dddddddd-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000001',
   'cccccccc-0000-0000-0000-000000000001', 'Prato', 3000, false, 0);

insert into restaurant_tables (id, restaurant_id, label, code)
values ('bbbbbbbb-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001',
        'Mesa 4', 'mesa4abc');

-- -----------------------------------------------------------------------------
-- Balcao
-- -----------------------------------------------------------------------------
do $$
declare v_id uuid; v_o orders; v_p payments;
begin
  perform pg_temp.virar('11111111-1111-1111-1111-111111111111');
  v_id := lancar_pedido('aaaaaaaa-0000-0000-0000-000000000001',
    '{"tipo":"pickup","forma":"cash","itens":[{"produto_id":"dddddddd-0000-0000-0000-000000000001","quantidade":1}]}');

  select * into v_o from orders where id = v_id;
  select * into v_p from payments where order_id = v_id;

  perform pg_temp.conferir(v_o.total_cents = 400,
    'uma agua de R$ 4 no balcao — pedido minimo nao vale para a loja');
  perform pg_temp.conferir(v_o.commission_cents = 0, 'pedido da loja nao paga comissao');
  perform pg_temp.conferir(v_o.placed_by_store, 'e fica marcado como lancado pela loja');
  perform pg_temp.conferir(v_o.status = 'confirmed' and v_o.confirmed_at is not null,
    'nasce aceito: a loja nao aceita o proprio pedido');
  perform pg_temp.conferir(v_o.customer_id is null and v_o.customer_name = 'Balcao',
    'sem conta de cliente, e com nome de balcao');
  perform pg_temp.conferir(v_o.number > 0, 'e recebe o numero da sequencia da loja');
  perform pg_temp.conferir(v_p.status = 'pending' and v_p.amount_cents = 400,
    'o pagamento fica a receber no caixa');
  perform pg_temp.conferir(
    (select stock_quantity from products where id = 'dddddddd-0000-0000-0000-000000000001') = 19,
    'e o estoque baixa');

  -- Mesmo depois de editado, a comissao continua zero.
  perform editar_pedido(v_id, '{"novos":[{"produto_id":"dddddddd-0000-0000-0000-000000000002","quantidade":1}]}');
  perform pg_temp.conferir((select commission_cents from orders where id = v_id) = 0,
    'editar o pedido da loja nao volta a cobrar comissao');
end;
$$;

do $$
declare v_id uuid;
begin
  perform pg_temp.virar('11111111-1111-1111-1111-111111111111');
  v_id := lancar_pedido('aaaaaaaa-0000-0000-0000-000000000001',
    '{"tipo":"pickup","forma":"debit_card","receber_agora":true,"cliente":"Joana",
      "itens":[{"produto_id":"dddddddd-0000-0000-0000-000000000002","quantidade":2}]}');

  perform pg_temp.conferir(
    (select status = 'paid' and paid_at is not null and method = 'debit_card'
       from payments where order_id = v_id),
    'pago na hora: ja entra recebido no caixa');
  perform pg_temp.conferir((select customer_name from orders where id = v_id) = 'Joana',
    'com o nome que a loja digitou');
end;
$$;

-- -----------------------------------------------------------------------------
-- Mesa
-- -----------------------------------------------------------------------------
do $$
declare v_id uuid; v_o orders;
begin
  perform pg_temp.virar('11111111-1111-1111-1111-111111111111');
  v_id := lancar_pedido('aaaaaaaa-0000-0000-0000-000000000001',
    '{"tipo":"dine_in","mesa_id":"bbbbbbbb-0000-0000-0000-000000000001",
      "itens":[{"produto_id":"dddddddd-0000-0000-0000-000000000002","quantidade":1}]}');
  select * into v_o from orders where id = v_id;
  perform pg_temp.conferir(v_o.table_label = 'Mesa 4' and v_o.customer_name = 'Mesa 4',
    'mesa cadastrada: o pedido diz para onde vai o prato');

  v_id := lancar_pedido('aaaaaaaa-0000-0000-0000-000000000001',
    '{"tipo":"dine_in","mesa":"Varanda 2",
      "itens":[{"produto_id":"dddddddd-0000-0000-0000-000000000002","quantidade":1}]}');
  perform pg_temp.conferir((select table_label from orders where id = v_id) = 'Varanda 2',
    'loja sem mesas cadastradas escreve o nome da mesa');

  perform pg_temp.deve_falhar(
    $q$select lancar_pedido('aaaaaaaa-0000-0000-0000-000000000001',
      '{"tipo":"dine_in","itens":[{"produto_id":"dddddddd-0000-0000-0000-000000000002","quantidade":1}]}')$q$,
    'pedido de mesa sem dizer a mesa');
end;
$$;

-- -----------------------------------------------------------------------------
-- Entrega por telefone
-- -----------------------------------------------------------------------------
do $$
declare v_id uuid; v_o orders;
begin
  perform pg_temp.virar('11111111-1111-1111-1111-111111111111');
  v_id := lancar_pedido('aaaaaaaa-0000-0000-0000-000000000001',
    '{"tipo":"delivery","cliente":"Carlos","telefone":"(62) 99999-0000","forma":"cash",
      "troco_para_cents":10000,
      "endereco":{"rua":"Rua 10","numero":"200","bairro":"Centro","cidade":"Goiania"},
      "itens":[{"produto_id":"dddddddd-0000-0000-0000-000000000002","quantidade":1}]}');
  select * into v_o from orders where id = v_id;

  perform pg_temp.conferir(v_o.delivery_fee_cents = 700 and v_o.total_cents = 3700,
    'entrega cobra o frete da loja');
  perform pg_temp.conferir(v_o.address_summary = 'Rua 10, 200' and v_o.address_district = 'Centro',
    'com o endereco que o cliente disse');
  perform pg_temp.conferir(v_o.customer_phone = '62999990000', 'telefone so com numeros');
  perform pg_temp.conferir(
    (select status from deliveries where order_id = v_id) = 'pending',
    'a corrida fica pronta para chamar o entregador');
  perform pg_temp.conferir(
    (select change_for_cents from payments where order_id = v_id) = 10000,
    'e o troco vai anotado');

  -- Acima de R$ 100, frete gratis — a regra da loja vale aqui tambem.
  v_id := lancar_pedido('aaaaaaaa-0000-0000-0000-000000000001',
    '{"tipo":"delivery","telefone":"62999990000",
      "endereco":{"rua":"Rua 10","numero":"200","bairro":"Centro"},
      "itens":[{"produto_id":"dddddddd-0000-0000-0000-000000000002","quantidade":4}]}');
  perform pg_temp.conferir((select delivery_fee_cents from orders where id = v_id) = 0,
    'frete gratis acima do valor da loja');

  perform pg_temp.deve_falhar(
    $q$select lancar_pedido('aaaaaaaa-0000-0000-0000-000000000001',
      '{"tipo":"delivery","telefone":"62999990000","endereco":{"rua":"Rua 10"},
        "itens":[{"produto_id":"dddddddd-0000-0000-0000-000000000002","quantidade":1}]}')$q$,
    'entrega sem numero e bairro');
  perform pg_temp.deve_falhar(
    $q$select lancar_pedido('aaaaaaaa-0000-0000-0000-000000000001',
      '{"tipo":"delivery","endereco":{"rua":"Rua 10","numero":"1","bairro":"Centro"},
        "itens":[{"produto_id":"dddddddd-0000-0000-0000-000000000002","quantidade":1}]}')$q$,
    'entrega sem telefone');
end;
$$;

-- -----------------------------------------------------------------------------
-- Quem lanca
-- -----------------------------------------------------------------------------
do $$
begin
  perform pg_temp.virar('22222222-2222-2222-2222-222222222222');
  perform pg_temp.deve_falhar(
    $q$select lancar_pedido('aaaaaaaa-0000-0000-0000-000000000001',
      '{"tipo":"pickup","itens":[{"produto_id":"dddddddd-0000-0000-0000-000000000002","quantidade":1}]}')$q$,
    'cliente lancando pedido sem comissao por fora do aplicativo');

  perform pg_temp.virar('11111111-1111-1111-1111-111111111111');
  perform pg_temp.deve_falhar(
    $q$select lancar_pedido('aaaaaaaa-0000-0000-0000-000000000001', '{"tipo":"pickup","itens":[]}')$q$,
    'pedido sem item');
end;
$$;

rollback;
