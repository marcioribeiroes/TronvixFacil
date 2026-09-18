-- =============================================================================
-- Tronvix Facil - testes de public.fechar_pedido
--
-- O que estes testes protegem, em uma frase: o preco nao vem do aplicativo.
--
-- Cada bloco monta um carrinho, mexe no cardapio pelas costas do cliente e
-- confere que o pedido gravado conta a verdade do cardapio, nao a do celular.
--
-- Como rodar:
--   npm run db:test
--   psql -d <banco> -f supabase/tests/regras_do_fechamento.sql
-- =============================================================================

\set ON_ERROR_STOP on

begin;

create or replace function pg_temp.deve_falhar(p_sql text, p_contexto text)
returns void
language plpgsql
as $$
begin
  execute p_sql;
  raise exception 'FALHOU: % deveria ter sido rejeitado, mas passou.', p_contexto;
exception
  when check_violation or insufficient_privilege or foreign_key_violation
    or not_null_violation or unique_violation or no_data_found then
    raise notice 'ok - rejeitado como esperado: %', p_contexto;
end;
$$;

create or replace function pg_temp.conferir(p_condicao boolean, p_contexto text)
returns void
language plpgsql
as $$
begin
  if not p_condicao then
    raise exception 'FALHOU: %', p_contexto;
  end if;
  raise notice 'ok - %', p_contexto;
end;
$$;

create or replace function pg_temp.virar(p_user uuid)
returns void language sql as $$
  select set_config('request.jwt.claim.sub', p_user::text, true);
$$;

-- -----------------------------------------------------------------------------
-- Cenario: uma hamburgueria, um cliente com endereco, um cardapio com adicional
-- -----------------------------------------------------------------------------

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'dono@burger.test'),
  ('22222222-2222-2222-2222-222222222222', 'cliente@teste.test'),
  ('33333333-3333-3333-3333-333333333333', 'outro@teste.test');

update profiles set full_name = 'MARIA DA SILVA', phone = '27999998888'
 where id = '22222222-2222-2222-2222-222222222222';

insert into restaurants (
  id, slug, name, status, is_open,
  delivery_fee_cents, free_delivery_above_cents, min_order_cents, commission_bps
) values (
  'aaaaaaaa-0000-0000-0000-000000000001', 'burger', 'Burger House', 'approved', true,
  700, 8000, 2000, 1200
);

insert into restaurant_members (restaurant_id, user_id, role)
values ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'owner');

insert into categories (id, restaurant_id, name)
values ('cccccccc-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'Lanches');

insert into products (id, restaurant_id, category_id, name, price_cents)
values
  ('dddddddd-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001',
   'cccccccc-0000-0000-0000-000000000001', 'X-Salada', 2500),
  ('dddddddd-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000001',
   'cccccccc-0000-0000-0000-000000000001', 'X-Bacon', 3000);

insert into addon_groups (id, restaurant_id, product_id, name, is_required, min_select, max_select)
values ('eeeeeeee-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001',
        'dddddddd-0000-0000-0000-000000000001', 'Ponto da carne', true, 1, 1);

insert into addons (id, restaurant_id, group_id, name, price_cents)
values
  ('ffffffff-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001',
   'eeeeeeee-0000-0000-0000-000000000001', 'Ao ponto', 0),
  ('ffffffff-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000001',
   'eeeeeeee-0000-0000-0000-000000000001', 'Bem passada', 200);

insert into addresses (id, user_id, street, number, district, city, state, postal_code, is_default)
values ('bbbbbbbb-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222',
        'Rua das Flores', '100', 'Centro', 'Vitoria', 'ES', '29010000', true);

-- Monta um carrinho com 2 X-Salada bem passada. Devolve o id do carrinho.
create or replace function pg_temp.carrinho_padrao()
returns uuid
language plpgsql
as $$
declare
  v_cart uuid;
  v_item uuid;
begin
  -- So existe um carrinho aberto por cliente e por estabelecimento
  -- (carts_open_per_restaurant_idx). O helper limpa o anterior, como o
  -- aplicativo faz ao abrir o carrinho.
  delete from carts
   where user_id = '22222222-2222-2222-2222-222222222222'
     and restaurant_id = 'aaaaaaaa-0000-0000-0000-000000000001';

  insert into carts (user_id, restaurant_id)
  values ('22222222-2222-2222-2222-222222222222', 'aaaaaaaa-0000-0000-0000-000000000001')
  returning id into v_cart;

  insert into cart_items (cart_id, product_id, quantity)
  values (v_cart, 'dddddddd-0000-0000-0000-000000000001', 2)
  returning id into v_item;

  insert into cart_item_addons (cart_item_id, addon_id)
  values (v_item, 'ffffffff-0000-0000-0000-000000000002');

  return v_cart;
end;
$$;

-- -----------------------------------------------------------------------------
-- A conta basica
-- -----------------------------------------------------------------------------
do $$
declare
  v_cart uuid;
  v_pedido uuid;
  o orders;
begin
  perform pg_temp.virar('22222222-2222-2222-2222-222222222222');
  v_cart := pg_temp.carrinho_padrao();

  v_pedido := public.fechar_pedido(
    p_cart_id => v_cart,
    p_fulfillment => 'delivery',
    p_payment_method => 'cash',
    p_payment_timing => 'on_delivery',
    p_address_id => 'bbbbbbbb-0000-0000-0000-000000000001',
    p_change_for_cents => 10000
  );

  select * into o from orders where id = v_pedido;

  -- (2500 + 200) x 2 = 5400; abaixo dos 8000 de frete gratis, entao taxa 700.
  perform pg_temp.conferir(o.subtotal_cents = 5400, 'subtotal sai do cardapio, com adicional');
  perform pg_temp.conferir(o.delivery_fee_cents = 700, 'taxa de entrega cobrada abaixo do minimo de frete gratis');
  perform pg_temp.conferir(o.total_cents = 6100, 'total fecha com subtotal mais frete');
  -- 12% sobre a mercadoria, nao sobre o frete.
  perform pg_temp.conferir(o.commission_cents = 648, 'comissao incide so sobre o subtotal');
  perform pg_temp.conferir(o.status = 'received', 'pagamento na entrega ja chega ao balcao como recebido');
  perform pg_temp.conferir(o.customer_name = 'MARIA DA SILVA', 'nome do cliente copiado no pedido');
  perform pg_temp.conferir(o.address_summary = 'Rua das Flores, 100', 'endereco virou snapshot');
  perform pg_temp.conferir(o.number = 1, 'numeracao do estabelecimento comeca no 1');
  perform pg_temp.conferir(
    (select count(*) from order_item_addons oia
      join order_items oi on oi.id = oia.order_item_id
     where oi.order_id = v_pedido) = 1,
    'adicional escolhido foi copiado para o pedido');
  perform pg_temp.conferir(
    (select change_for_cents from payments where order_id = v_pedido) = 10000,
    'troco registrado no pagamento');
  perform pg_temp.conferir(
    (select count(*) from deliveries where order_id = v_pedido) = 1,
    'pedido de entrega nasce com corrida pendente');
  perform pg_temp.conferir(
    (select count(*) from carts where id = v_cart) = 0,
    'carrinho morre junto com o fechamento');
end;
$$;

-- -----------------------------------------------------------------------------
-- O preco nao vem do aplicativo
-- -----------------------------------------------------------------------------
do $$
declare
  v_cart uuid;
  v_pedido uuid;
begin
  perform pg_temp.virar('22222222-2222-2222-2222-222222222222');
  v_cart := pg_temp.carrinho_padrao();

  -- O restaurante reajusta entre montar o carrinho e fechar.
  update products set price_cents = 3200 where id = 'dddddddd-0000-0000-0000-000000000001';

  v_pedido := public.fechar_pedido(
    p_cart_id => v_cart, p_fulfillment => 'pickup',
    p_payment_method => 'pix', p_payment_timing => 'online'
  );

  perform pg_temp.conferir(
    (select subtotal_cents from orders where id = v_pedido) = 6800,
    'reajuste no cardapio vale no fechamento: (3200 + 200) x 2');
  perform pg_temp.conferir(
    (select delivery_fee_cents from orders where id = v_pedido) = 0,
    'retirada no balcao nao cobra entrega');
  perform pg_temp.conferir(
    (select count(*) from deliveries where order_id = v_pedido) = 0,
    'retirada nao cria corrida');
  perform pg_temp.conferir(
    (select status from orders where id = v_pedido) = 'awaiting_payment',
    'pagamento pelo aplicativo espera o pagamento');

  update products set price_cents = 2500 where id = 'dddddddd-0000-0000-0000-000000000001';
end;
$$;

-- -----------------------------------------------------------------------------
-- A promocao so vale dentro da janela
-- -----------------------------------------------------------------------------
do $$
declare
  v_cart uuid;
  v_pedido uuid;
begin
  perform pg_temp.virar('22222222-2222-2222-2222-222222222222');

  update products
     set promo_price_cents = 1900,
         promo_starts_at = now() - interval '1 hour',
         promo_ends_at = now() + interval '1 hour'
   where id = 'dddddddd-0000-0000-0000-000000000001';

  v_cart := pg_temp.carrinho_padrao();
  v_pedido := public.fechar_pedido(
    p_cart_id => v_cart, p_fulfillment => 'pickup',
    p_payment_method => 'pix', p_payment_timing => 'online');

  perform pg_temp.conferir(
    (select subtotal_cents from orders where id = v_pedido) = 4200,
    'promocao dentro da janela e o preco que vale: (1900 + 200) x 2');

  -- Janela vencida: volta a valer o preco cheio.
  update products set promo_ends_at = now() - interval '1 minute'
   where id = 'dddddddd-0000-0000-0000-000000000001';

  v_cart := pg_temp.carrinho_padrao();
  v_pedido := public.fechar_pedido(
    p_cart_id => v_cart, p_fulfillment => 'pickup',
    p_payment_method => 'pix', p_payment_timing => 'online');

  perform pg_temp.conferir(
    (select subtotal_cents from orders where id = v_pedido) = 5400,
    'promocao vencida nao vale: volta ao preco cheio');

  update products set promo_price_cents = null, promo_starts_at = null, promo_ends_at = null
   where id = 'dddddddd-0000-0000-0000-000000000001';
end;
$$;

-- -----------------------------------------------------------------------------
-- Frete gratis acima do valor cadastrado
-- -----------------------------------------------------------------------------
do $$
declare
  v_cart uuid;
  v_item uuid;
  v_pedido uuid;
begin
  perform pg_temp.virar('22222222-2222-2222-2222-222222222222');

  delete from carts where user_id = '22222222-2222-2222-2222-222222222222';
  insert into carts (user_id, restaurant_id)
  values ('22222222-2222-2222-2222-222222222222', 'aaaaaaaa-0000-0000-0000-000000000001')
  returning id into v_cart;

  insert into cart_items (cart_id, product_id, quantity)
  values (v_cart, 'dddddddd-0000-0000-0000-000000000002', 3)
  returning id into v_item;

  v_pedido := public.fechar_pedido(
    p_cart_id => v_cart, p_fulfillment => 'delivery',
    p_payment_method => 'cash', p_payment_timing => 'on_delivery',
    p_address_id => 'bbbbbbbb-0000-0000-0000-000000000001');

  perform pg_temp.conferir(
    (select delivery_fee_cents from orders where id = v_pedido) = 0,
    'acima de R$ 80,00 a entrega sai de graca');
end;
$$;

-- -----------------------------------------------------------------------------
-- Cupons
-- -----------------------------------------------------------------------------
insert into coupons (id, scope, restaurant_id, code, discount, value, min_order_cents)
values
  ('99999999-0000-0000-0000-000000000001', 'restaurant', 'aaaaaaaa-0000-0000-0000-000000000001',
   'BURGER10', 'percentage', 1000, 0),
  ('99999999-0000-0000-0000-000000000002', 'platform', null,
   'FRETEGRATIS', 'free_shipping', 0, 0),
  ('99999999-0000-0000-0000-000000000003', 'restaurant', 'aaaaaaaa-0000-0000-0000-000000000001',
   'CAROU', 'percentage', 5000, 900000);

do $$
declare
  v_cart uuid;
  v_pedido uuid;
begin
  perform pg_temp.virar('22222222-2222-2222-2222-222222222222');

  v_cart := pg_temp.carrinho_padrao();
  v_pedido := public.fechar_pedido(
    p_cart_id => v_cart, p_fulfillment => 'delivery',
    p_payment_method => 'cash', p_payment_timing => 'on_delivery',
    p_address_id => 'bbbbbbbb-0000-0000-0000-000000000001',
    p_coupon_code => 'burger10');

  perform pg_temp.conferir(
    (select discount_cents from orders where id = v_pedido) = 540,
    'cupom percentual incide sobre o subtotal, ignorando maiusculas');
  perform pg_temp.conferir(
    (select total_cents from orders where id = v_pedido) = 5560,
    'total desconta o cupom: 5400 + 700 - 540');
  perform pg_temp.conferir(
    (select count(*) from coupon_redemptions where order_id = v_pedido) = 1,
    'uso do cupom fica registrado');
  perform pg_temp.conferir(
    (select used_count from coupons where id = '99999999-0000-0000-0000-000000000001') = 1,
    'contador do cupom avanca');

  v_cart := pg_temp.carrinho_padrao();
  v_pedido := public.fechar_pedido(
    p_cart_id => v_cart, p_fulfillment => 'delivery',
    p_payment_method => 'cash', p_payment_timing => 'on_delivery',
    p_address_id => 'bbbbbbbb-0000-0000-0000-000000000001',
    p_coupon_code => 'FRETEGRATIS');

  perform pg_temp.conferir(
    (select discount_cents from orders where id = v_pedido) = 700,
    'frete gratis desconta exatamente a taxa de entrega');
end;
$$;

-- Cupom ja usado uma vez por este cliente (max_uses_per_customer = 1).
do $$
declare v_cart uuid;
begin
  perform pg_temp.virar('22222222-2222-2222-2222-222222222222');
  v_cart := pg_temp.carrinho_padrao();
  perform pg_temp.deve_falhar(
    format($f$select public.fechar_pedido(%L::uuid, 'delivery', 'cash', 'on_delivery',
            'bbbbbbbb-0000-0000-0000-000000000001'::uuid, null, 'BURGER10')$f$, v_cart),
    'reusar cupom de uso unico por cliente');
end;
$$;

do $$
declare v_cart uuid;
begin
  perform pg_temp.virar('22222222-2222-2222-2222-222222222222');
  v_cart := pg_temp.carrinho_padrao();
  perform pg_temp.deve_falhar(
    format($f$select public.fechar_pedido(%L::uuid, 'pickup', 'pix', 'online',
            null, null, 'CAROU')$f$, v_cart),
    'cupom com pedido minimo acima do carrinho');
  perform pg_temp.deve_falhar(
    format($f$select public.fechar_pedido(%L::uuid, 'pickup', 'pix', 'online',
            null, null, 'NAOEXISTE')$f$, v_cart),
    'cupom inexistente');
end;
$$;

-- -----------------------------------------------------------------------------
-- O que o fechamento tem de recusar
-- -----------------------------------------------------------------------------
do $$
declare
  v_cart uuid;
begin
  perform pg_temp.virar('22222222-2222-2222-2222-222222222222');
  v_cart := pg_temp.carrinho_padrao();

  -- Carrinho dos outros.
  perform pg_temp.virar('33333333-3333-3333-3333-333333333333');
  perform pg_temp.deve_falhar(
    format($f$select public.fechar_pedido(%L::uuid, 'pickup', 'pix', 'online')$f$, v_cart),
    'fechar o carrinho de outra pessoa');

  -- Sem estar autenticado.
  perform set_config('request.jwt.claim.sub', '', true);
  perform pg_temp.deve_falhar(
    format($f$select public.fechar_pedido(%L::uuid, 'pickup', 'pix', 'online')$f$, v_cart),
    'fechar pedido sem estar autenticado');

  -- Entrega sem endereco.
  perform pg_temp.virar('22222222-2222-2222-2222-222222222222');
  perform pg_temp.deve_falhar(
    format($f$select public.fechar_pedido(%L::uuid, 'delivery', 'cash', 'on_delivery')$f$, v_cart),
    'pedido de entrega sem endereco escolhido');

  -- Endereco de outra pessoa.
  insert into addresses (id, user_id, street, number, district, city, state, postal_code)
  values ('bbbbbbbb-0000-0000-0000-000000000009', '33333333-3333-3333-3333-333333333333',
          'Rua de Outro', '1', 'Centro', 'Vitoria', 'ES', '29010001');
  perform pg_temp.deve_falhar(
    format($f$select public.fechar_pedido(%L::uuid, 'delivery', 'cash', 'on_delivery',
            'bbbbbbbb-0000-0000-0000-000000000009'::uuid)$f$, v_cart),
    'usar endereco de outra pessoa');

  -- Produto que saiu do cardapio.
  update products set is_available = false where id = 'dddddddd-0000-0000-0000-000000000001';
  perform pg_temp.deve_falhar(
    format($f$select public.fechar_pedido(%L::uuid, 'pickup', 'pix', 'online')$f$, v_cart),
    'produto indisponivel no momento do fechamento');
  update products set is_available = true where id = 'dddddddd-0000-0000-0000-000000000001';

  -- Loja fechada.
  update restaurants set is_open = false where id = 'aaaaaaaa-0000-0000-0000-000000000001';
  perform pg_temp.deve_falhar(
    format($f$select public.fechar_pedido(%L::uuid, 'pickup', 'pix', 'online')$f$, v_cart),
    'pedido com o estabelecimento fechado');
  update restaurants set is_open = true where id = 'aaaaaaaa-0000-0000-0000-000000000001';
end;
$$;

-- Pedido minimo do estabelecimento.
do $$
declare
  v_cart uuid;
  v_item uuid;
begin
  perform pg_temp.virar('22222222-2222-2222-2222-222222222222');
  update restaurants set min_order_cents = 900000
   where id = 'aaaaaaaa-0000-0000-0000-000000000001';

  v_cart := pg_temp.carrinho_padrao();
  perform pg_temp.deve_falhar(
    format($f$select public.fechar_pedido(%L::uuid, 'pickup', 'pix', 'online')$f$, v_cart),
    'carrinho abaixo do pedido minimo do estabelecimento');

  update restaurants set min_order_cents = 2000
   where id = 'aaaaaaaa-0000-0000-0000-000000000001';
end;
$$;

-- Grupo obrigatorio sem escolha.
do $$
declare
  v_cart uuid;
  v_item uuid;
begin
  perform pg_temp.virar('22222222-2222-2222-2222-222222222222');

  delete from carts where user_id = '22222222-2222-2222-2222-222222222222';
  insert into carts (user_id, restaurant_id)
  values ('22222222-2222-2222-2222-222222222222', 'aaaaaaaa-0000-0000-0000-000000000001')
  returning id into v_cart;

  insert into cart_items (cart_id, product_id, quantity)
  values (v_cart, 'dddddddd-0000-0000-0000-000000000001', 1)
  returning id into v_item;

  perform pg_temp.deve_falhar(
    format($f$select public.fechar_pedido(%L::uuid, 'pickup', 'pix', 'online')$f$, v_cart),
    'item sem escolher o grupo obrigatorio');
end;
$$;

-- Estoque.
do $$
declare
  v_cart uuid;
  v_item uuid;
  v_pedido uuid;
begin
  perform pg_temp.virar('22222222-2222-2222-2222-222222222222');

  update products set track_stock = true, stock_quantity = 3
   where id = 'dddddddd-0000-0000-0000-000000000002';

  delete from carts where user_id = '22222222-2222-2222-2222-222222222222';
  insert into carts (user_id, restaurant_id)
  values ('22222222-2222-2222-2222-222222222222', 'aaaaaaaa-0000-0000-0000-000000000001')
  returning id into v_cart;
  insert into cart_items (cart_id, product_id, quantity)
  values (v_cart, 'dddddddd-0000-0000-0000-000000000002', 2);

  v_pedido := public.fechar_pedido(v_cart, 'pickup', 'pix', 'online');

  perform pg_temp.conferir(
    (select stock_quantity from products where id = 'dddddddd-0000-0000-0000-000000000002') = 1,
    'venda baixa o estoque de quem controla estoque');
  perform pg_temp.conferir(
    (select balance_after from stock_movements where order_id = v_pedido) = 1,
    'movimento de estoque registra o saldo depois da venda');

  delete from carts where user_id = '22222222-2222-2222-2222-222222222222';
  insert into carts (user_id, restaurant_id)
  values ('22222222-2222-2222-2222-222222222222', 'aaaaaaaa-0000-0000-0000-000000000001')
  returning id into v_cart;
  insert into cart_items (cart_id, product_id, quantity)
  values (v_cart, 'dddddddd-0000-0000-0000-000000000002', 5);

  perform pg_temp.deve_falhar(
    format($f$select public.fechar_pedido(%L::uuid, 'pickup', 'pix', 'online')$f$, v_cart),
    'comprar mais do que existe em estoque');

  update products set track_stock = false where id = 'dddddddd-0000-0000-0000-000000000002';
end;
$$;

-- -----------------------------------------------------------------------------
-- A politica de INSERT fechou para o cliente
-- -----------------------------------------------------------------------------
do $$
begin
  perform pg_temp.conferir(
    not exists (
      select 1 from pg_policies
      where tablename = 'orders' and policyname = 'cliente cria o proprio pedido'
    ),
    'a politica que deixava o cliente inserir pedido foi removida');

  perform pg_temp.conferir(
    exists (
      select 1 from pg_policies
      where tablename = 'orders' and policyname = 'balcao lanca pedido manual'
    ),
    'o balcao continua podendo lancar pedido manual');
end;
$$;

rollback;
