-- =============================================================================
-- Tronvix Facil - editar o pedido e pedir mais na mesa
--
-- O pedido muda, a conta acompanha: subtotal, comissao, valor a receber e
-- estoque refeitos pelo banco. E so muda enquanto pode — aberto, nao pago,
-- e por quem tem o direito.
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

insert into restaurants (id, slug, name, status, is_open, min_order_cents, commission_bps)
values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'loja', 'A Loja', 'approved', true, 0, 1000),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'outra', 'Outra', 'approved', true, 0, 1000);

insert into restaurant_members (restaurant_id, user_id, role)
values ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'owner');

insert into categories (id, restaurant_id, name) values
  ('cccccccc-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'Pratos'),
  ('cccccccc-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000002', 'Pratos');

insert into products (id, restaurant_id, category_id, name, price_cents, track_stock, stock_quantity)
values
  -- Prato com estoque contado.
  ('dddddddd-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001',
   'cccccccc-0000-0000-0000-000000000001', 'Prato', 3000, true, 50),
  -- Suco com sabor obrigatorio.
  ('dddddddd-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000001',
   'cccccccc-0000-0000-0000-000000000001', 'Suco', 1000, false, 0),
  -- Produto de outra loja.
  ('dddddddd-0000-0000-0000-000000000003', 'aaaaaaaa-0000-0000-0000-000000000002',
   'cccccccc-0000-0000-0000-000000000002', 'Alheio', 1000, false, 0);

insert into addon_groups (id, restaurant_id, product_id, name, is_required, min_select, max_select)
values ('eeeeeeee-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001',
        'dddddddd-0000-0000-0000-000000000002', 'Sabor', true, 1, 1);

insert into addons (id, restaurant_id, group_id, name, price_cents) values
  ('ffffffff-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001',
   'eeeeeeee-0000-0000-0000-000000000001', 'Laranja', 0),
  ('ffffffff-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000001',
   'eeeeeeee-0000-0000-0000-000000000001', 'Morango', 200);

do $$
begin
  perform pg_temp.virar('11111111-1111-1111-1111-111111111111');
  perform criar_mesas('aaaaaaaa-0000-0000-0000-000000000001', 1);
end;
$$;

-- Um pedido com 2 pratos (R$ 60), na mesa ou na retirada, a pagar no caixa.
create or replace function pg_temp.pedido(p_tipo fulfillment_type default 'dine_in')
returns uuid language plpgsql as $$
declare v_cart uuid;
begin
  perform pg_temp.virar('22222222-2222-2222-2222-222222222222');
  delete from carts where user_id = '22222222-2222-2222-2222-222222222222';
  insert into carts (user_id, restaurant_id)
  values ('22222222-2222-2222-2222-222222222222', 'aaaaaaaa-0000-0000-0000-000000000001')
  returning id into v_cart;
  insert into cart_items (cart_id, product_id, quantity)
  values (v_cart, 'dddddddd-0000-0000-0000-000000000001', 2);
  return fechar_pedido(v_cart, p_tipo, 'cash', 'on_delivery', null, null, null, null, null,
    case when p_tipo = 'dine_in' then (select code from restaurant_tables limit 1) end);
end;
$$;

create or replace function pg_temp.estoque()
returns int language sql as $$
  select stock_quantity from products where id = 'dddddddd-0000-0000-0000-000000000001';
$$;

-- -----------------------------------------------------------------------------
-- A loja edita, e a conta acompanha
-- -----------------------------------------------------------------------------
do $$
declare v_id uuid; v_o orders; v_item uuid; v_antes int;
begin
  v_id := pg_temp.pedido('pickup');
  v_antes := pg_temp.estoque();
  select id into v_item from order_items where order_id = v_id;

  perform pg_temp.virar('11111111-1111-1111-1111-111111111111');
  perform editar_pedido(v_id, jsonb_build_object(
    'itens', jsonb_build_array(jsonb_build_object('id', v_item, 'quantidade', 3)),
    'novos', jsonb_build_array(jsonb_build_object(
      'produto_id', 'dddddddd-0000-0000-0000-000000000002',
      'quantidade', 2,
      'observacao', 'Sem gelo',
      'adicionais', jsonb_build_array('ffffffff-0000-0000-0000-000000000002')))
  ));

  select * into v_o from orders where id = v_id;
  -- 3 x 3000 + 2 x (1000 + 200) = 11400
  perform pg_temp.conferir(v_o.subtotal_cents = 11400,
    'o subtotal soma a quantidade nova e o item acrescentado, com adicional');
  perform pg_temp.conferir(v_o.total_cents = 11400, 'o total fecha com as partes');
  perform pg_temp.conferir(v_o.commission_cents = 1140,
    'a comissao volta a incidir sobre a mercadoria');
  perform pg_temp.conferir(
    (select amount_cents from payments where order_id = v_id) = 11400,
    'o valor a receber no caixa acompanha o novo total');
  perform pg_temp.conferir(pg_temp.estoque() = v_antes - 1,
    'o prato a mais sai do estoque');
  perform pg_temp.conferir(
    (select notes from order_items where order_id = v_id and product_name = 'Suco') = 'Sem gelo',
    'a observacao do item novo chega na cozinha');
  perform pg_temp.conferir(v_o.customer_added_at is null,
    'edicao da loja nao finge que o cliente pediu');

  -- Remover devolve ao estoque.
  perform editar_pedido(v_id, jsonb_build_object(
    'itens', jsonb_build_array(jsonb_build_object('id', v_item, 'quantidade', 0))));
  perform pg_temp.conferir(pg_temp.estoque() = v_antes + 2,
    'o item removido volta para o estoque');
  perform pg_temp.conferir(
    (select subtotal_cents from orders where id = v_id) = 2400,
    'e sai da conta');

  -- Mas o pedido nao fica vazio.
  perform pg_temp.deve_falhar(format(
    $q$select editar_pedido('%s', jsonb_build_object('itens', jsonb_build_array(
         jsonb_build_object('id', (select id from order_items where order_id = '%s'), 'quantidade', 0))))$q$,
    v_id, v_id),
    'tirar o ultimo item do pedido — isso e cancelar');
end;
$$;

-- -----------------------------------------------------------------------------
-- As regras do cardapio valem na edicao
-- -----------------------------------------------------------------------------
do $$
declare v_id uuid;
begin
  v_id := pg_temp.pedido('pickup');
  perform pg_temp.virar('11111111-1111-1111-1111-111111111111');

  perform pg_temp.deve_falhar(format(
    $q$select editar_pedido('%s', '{"novos":[{"produto_id":"dddddddd-0000-0000-0000-000000000002","quantidade":1}]}')$q$, v_id),
    'suco sem escolher o sabor obrigatorio');
  perform pg_temp.deve_falhar(format(
    $q$select editar_pedido('%s', '{"novos":[{"produto_id":"dddddddd-0000-0000-0000-000000000002","quantidade":1,
       "adicionais":["ffffffff-0000-0000-0000-000000000001","ffffffff-0000-0000-0000-000000000002"]}]}')$q$, v_id),
    'dois sabores num grupo de escolha unica');
  perform pg_temp.deve_falhar(format(
    $q$select editar_pedido('%s', '{"novos":[{"produto_id":"dddddddd-0000-0000-0000-000000000003","quantidade":1}]}')$q$, v_id),
    'produto de outra loja no pedido');
  perform pg_temp.deve_falhar(format(
    $q$select editar_pedido('%s', '{"novos":[{"produto_id":"dddddddd-0000-0000-0000-000000000001","quantidade":99}]}')$q$, v_id),
    'mais pratos do que ha no estoque');

  perform pg_temp.deve_falhar(format(
    $q$select editar_pedido('%s', '{"novos":[{"produto_id":"dddddddd-0000-0000-0000-000000000002","quantidade":1,
       "adicionais":[{"id":"ffffffff-0000-0000-0000-000000000002","quantidade":2}]}]}')$q$, v_id),
    'adicional acima da quantidade maxima dele');

  -- Adicional com quantidade, como o aplicativo manda.
  update addons set max_quantity = 3 where id = 'ffffffff-0000-0000-0000-000000000002';
  update addon_groups set max_select = 3 where id = 'eeeeeeee-0000-0000-0000-000000000001';
  perform editar_pedido(v_id, '{"novos":[{"produto_id":"dddddddd-0000-0000-0000-000000000002","quantidade":1,
     "adicionais":[{"id":"ffffffff-0000-0000-0000-000000000002","quantidade":2}]}]}');
  perform pg_temp.conferir(
    (select addons_total_cents from order_items where order_id = v_id and product_name = 'Suco') = 400,
    'adicional com quantidade cobra cada unidade');
  update addon_groups set max_select = 1 where id = 'eeeeeeee-0000-0000-0000-000000000001';

  update products set is_available = false where id = 'dddddddd-0000-0000-0000-000000000002';
  perform pg_temp.deve_falhar(format(
    $q$select editar_pedido('%s', '{"novos":[{"produto_id":"dddddddd-0000-0000-0000-000000000002","quantidade":1,
       "adicionais":["ffffffff-0000-0000-0000-000000000001"]}]}')$q$, v_id),
    'produto fora do ar');
  update products set is_available = true where id = 'dddddddd-0000-0000-0000-000000000002';
end;
$$;

-- -----------------------------------------------------------------------------
-- Quem e quando
-- -----------------------------------------------------------------------------
do $$
declare v_id uuid;
begin
  v_id := pg_temp.pedido('pickup');

  perform pg_temp.virar('22222222-2222-2222-2222-222222222222');
  perform pg_temp.deve_falhar(format(
    $q$select editar_pedido('%s', '{"novos":[{"produto_id":"dddddddd-0000-0000-0000-000000000001","quantidade":1}]}')$q$, v_id),
    'o cliente usando a edicao da loja');

  perform pg_temp.virar('33333333-3333-3333-3333-333333333333');
  perform pg_temp.deve_falhar(format(
    $q$select editar_pedido('%s', '{"novos":[{"produto_id":"dddddddd-0000-0000-0000-000000000001","quantidade":1}]}')$q$, v_id),
    'um estranho editando pedido da loja');

  -- Recebido no caixa: a conta esta fechada.
  perform pg_temp.virar('11111111-1111-1111-1111-111111111111');
  perform receber_pagamento(v_id, 'cash');
  perform pg_temp.deve_falhar(format(
    $q$select editar_pedido('%s', '{"novos":[{"produto_id":"dddddddd-0000-0000-0000-000000000001","quantidade":1}]}')$q$, v_id),
    'editar pedido ja recebido no caixa');
end;
$$;

do $$
declare v_id uuid;
begin
  v_id := pg_temp.pedido('pickup');
  perform pg_temp.virar('11111111-1111-1111-1111-111111111111');
  update orders set status = 'confirmed' where id = v_id;
  update orders set status = 'preparing' where id = v_id;
  update orders set status = 'ready' where id = v_id;
  update orders set status = 'delivered' where id = v_id;

  perform pg_temp.deve_falhar(format(
    $q$select editar_pedido('%s', '{"novos":[{"produto_id":"dddddddd-0000-0000-0000-000000000001","quantidade":1}]}')$q$, v_id),
    'editar pedido ja entregue');
end;
$$;

do $$
declare v_id uuid;
begin
  v_id := pg_temp.pedido('pickup');
  update payments set timing = 'online', method = 'pix' where order_id = v_id;

  perform pg_temp.virar('11111111-1111-1111-1111-111111111111');
  perform pg_temp.deve_falhar(format(
    $q$select editar_pedido('%s', '{"novos":[{"produto_id":"dddddddd-0000-0000-0000-000000000001","quantidade":1}]}')$q$, v_id),
    'editar pedido pago pelo site');
end;
$$;

-- -----------------------------------------------------------------------------
-- O cliente da mesa pede mais
-- -----------------------------------------------------------------------------
do $$
declare v_id uuid; v_o orders;
begin
  v_id := pg_temp.pedido('dine_in');

  perform pg_temp.virar('22222222-2222-2222-2222-222222222222');
  perform pedir_mais_na_mesa(v_id, '[{"produto_id":"dddddddd-0000-0000-0000-000000000002","quantidade":1,
    "adicionais":["ffffffff-0000-0000-0000-000000000001"]}]');

  select * into v_o from orders where id = v_id;
  perform pg_temp.conferir(v_o.subtotal_cents = 7000,
    'o item pedido na mesa entra na mesma conta');
  perform pg_temp.conferir(v_o.customer_added_at is not null,
    'e o balcao fica sabendo que o cliente pediu mais');
  perform pg_temp.conferir(
    (select count(*) from order_items where order_id = v_id) = 2,
    'o item novo fica no mesmo pedido, e nao abre outro');

  -- Pedido de outra pessoa.
  perform pg_temp.virar('33333333-3333-3333-3333-333333333333');
  perform pg_temp.deve_falhar(format(
    $q$select pedir_mais_na_mesa('%s', '[{"produto_id":"dddddddd-0000-0000-0000-000000000001","quantidade":1}]')$q$, v_id),
    'pedir mais no pedido de outra mesa');

  -- Cozinha fechada.
  update restaurants set is_open = false where id = 'aaaaaaaa-0000-0000-0000-000000000001';
  perform pg_temp.virar('22222222-2222-2222-2222-222222222222');
  perform pg_temp.deve_falhar(format(
    $q$select pedir_mais_na_mesa('%s', '[{"produto_id":"dddddddd-0000-0000-0000-000000000001","quantidade":1}]')$q$, v_id),
    'pedir mais com a cozinha fechada');
  update restaurants set is_open = true where id = 'aaaaaaaa-0000-0000-0000-000000000001';

  perform pg_temp.deve_falhar(format(
    $q$select pedir_mais_na_mesa('%s', '[]')$q$, v_id),
    'pedir mais sem item nenhum');
end;
$$;

do $$
declare v_id uuid;
begin
  v_id := pg_temp.pedido('pickup');
  perform pg_temp.virar('22222222-2222-2222-2222-222222222222');
  perform pg_temp.deve_falhar(format(
    $q$select pedir_mais_na_mesa('%s', '[{"produto_id":"dddddddd-0000-0000-0000-000000000001","quantidade":1}]')$q$, v_id),
    'pedir mais num pedido de retirada');
end;
$$;

-- -----------------------------------------------------------------------------
-- As portas que continuam fechadas
-- -----------------------------------------------------------------------------
do $$
declare v_id uuid;
begin
  v_id := pg_temp.pedido('dine_in');

  -- O total continua trancado para quem nao passa pela funcao.
  perform pg_temp.virar('11111111-1111-1111-1111-111111111111');
  perform pg_temp.deve_falhar(format(
    $q$update orders set total_cents = 1, subtotal_cents = 1 where id = '%s'$q$, v_id),
    'baixar o total do pedido direto na tabela');

  -- Item direto na tabela: sem preco conferido, nao entra.
  perform pg_temp.virar('22222222-2222-2222-2222-222222222222');
  perform pg_temp.deve_falhar(format(
    $q$set local role authenticated;
       insert into order_items (order_id, product_name, unit_price_cents, quantity, total_cents)
       values ('%s', 'Picanha de graca', 1, 1, 1)$q$, v_id),
    'cliente inserindo item direto no proprio pedido');
  reset role;
end;
$$;

rollback;
