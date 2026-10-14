-- =============================================================================
-- Tronvix Facil - taxa de entrega por distancia
--
-- A taxa sai da faixa em que o endereco cai; acima da ultima faixa, a loja nao
-- entrega — e o fechamento recusa. Loja sem faixas segue com a taxa unica,
-- mas o raio passa a valer.
--
-- Pontos em Goiania. 0,01 grau de latitude ~ 1,11 km.
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
  ('33333333-3333-3333-3333-333333333333', 'atendente@teste.test');

insert into restaurants (id, slug, name, status, is_open, min_order_cents,
                         latitude, longitude, delivery_fee_cents, delivery_radius_km,
                         free_delivery_above_cents)
values
  -- Com faixas.
  ('aaaaaaaa-0000-0000-0000-000000000001', 'faixas', 'Com Faixas', 'approved', true, 0,
   -16.6869, -49.2648, 500, 5, 10000),
  -- Sem faixas: taxa unica R$ 5, raio 5 km.
  ('aaaaaaaa-0000-0000-0000-000000000002', 'unica', 'Taxa Unica', 'approved', true, 0,
   -16.6869, -49.2648, 500, 5, null);

insert into restaurant_members (restaurant_id, user_id, role) values
  ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'owner'),
  ('aaaaaaaa-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333', 'staff');

insert into categories (id, restaurant_id, name)
values ('cccccccc-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'Pratos');
insert into products (id, restaurant_id, category_id, name, price_cents)
values ('dddddddd-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000001', 'Prato', 3000);

insert into addresses (id, user_id, street, number, district, city, state, postal_code,
                       latitude, longitude)
values
  ('eeeeeeee-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222',
   'Rua Perto', '1', 'Centro', 'Goiania', 'GO', '74000000', -16.6959, -49.2648),   -- ~1 km
  ('eeeeeeee-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222222',
   'Rua Meio', '1', 'Centro', 'Goiania', 'GO', '74000000', -16.7269, -49.2648),    -- ~4,4 km
  ('eeeeeeee-0000-0000-0000-000000000003', '22222222-2222-2222-2222-222222222222',
   'Rua Longe', '1', 'Centro', 'Goiania', 'GO', '74000000', -16.7869, -49.2648),   -- ~11 km
  ('eeeeeeee-0000-0000-0000-000000000004', '22222222-2222-2222-2222-222222222222',
   'Rua Sem GPS', '1', 'Centro', 'Goiania', 'GO', '74000000', null, null);

-- -----------------------------------------------------------------------------
-- O dono monta as faixas
-- -----------------------------------------------------------------------------
do $$
begin
  perform pg_temp.virar('33333333-3333-3333-3333-333333333333');
  perform pg_temp.deve_falhar(
    $q$select salvar_faixas_de_entrega('aaaaaaaa-0000-0000-0000-000000000001',
       '[{"ate_km":2,"taxa_cents":400}]')$q$,
    'atendente mudando a taxa de entrega');

  perform pg_temp.virar('11111111-1111-1111-1111-111111111111');
  perform pg_temp.deve_falhar(
    $q$select salvar_faixas_de_entrega('aaaaaaaa-0000-0000-0000-000000000001',
       '[{"ate_km":2,"taxa_cents":400},{"ate_km":2,"taxa_cents":600}]')$q$,
    'duas faixas com a mesma distancia');
  perform pg_temp.deve_falhar(
    $q$select salvar_faixas_de_entrega('aaaaaaaa-0000-0000-0000-000000000001',
       '[{"ate_km":80,"taxa_cents":400}]')$q$,
    'faixa acima de 50 km');

  perform salvar_faixas_de_entrega('aaaaaaaa-0000-0000-0000-000000000001',
    '[{"ate_km":2,"taxa_cents":400},{"ate_km":5,"taxa_cents":700}]');
  perform pg_temp.conferir(
    (select count(*) from delivery_fee_tiers
      where restaurant_id = 'aaaaaaaa-0000-0000-0000-000000000001') = 2,
    'o dono salva as faixas');
  perform pg_temp.conferir(
    (select delivery_radius_km from restaurants
      where id = 'aaaaaaaa-0000-0000-0000-000000000001') = 5,
    'o raio da loja passa a ser o da maior faixa');
end;
$$;

-- -----------------------------------------------------------------------------
-- A cotacao
-- -----------------------------------------------------------------------------
do $$
declare v jsonb;
begin
  perform pg_temp.virar('22222222-2222-2222-2222-222222222222');

  v := cotar_entrega('aaaaaaaa-0000-0000-0000-000000000001', 'eeeeeeee-0000-0000-0000-000000000001', 3000);
  perform pg_temp.conferir((v ->> 'entrega')::boolean and (v ->> 'taxa_cents')::bigint = 400,
    'a 1 km: primeira faixa, R$ 4');

  v := cotar_entrega('aaaaaaaa-0000-0000-0000-000000000001', 'eeeeeeee-0000-0000-0000-000000000002', 3000);
  perform pg_temp.conferir((v ->> 'taxa_cents')::bigint = 700,
    'a 4,4 km: segunda faixa, R$ 7');

  v := cotar_entrega('aaaaaaaa-0000-0000-0000-000000000001', 'eeeeeeee-0000-0000-0000-000000000003', 3000);
  perform pg_temp.conferir(not (v ->> 'entrega')::boolean and v ->> 'motivo' = 'fora_da_area',
    'a 11 km: fora da area, nao entrega');

  v := cotar_entrega('aaaaaaaa-0000-0000-0000-000000000001', 'eeeeeeee-0000-0000-0000-000000000004', 3000);
  perform pg_temp.conferir((v ->> 'taxa_cents')::bigint = 700 and v ->> 'motivo' = 'sem_localizacao',
    'endereco sem localizacao: entrega, pela maior faixa');

  v := cotar_entrega('aaaaaaaa-0000-0000-0000-000000000001', 'eeeeeeee-0000-0000-0000-000000000002', 10000);
  perform pg_temp.conferir((v ->> 'taxa_cents')::bigint = 0,
    'frete gratis acima do valor da loja continua valendo');

  v := cotar_entrega('aaaaaaaa-0000-0000-0000-000000000002', 'eeeeeeee-0000-0000-0000-000000000002', 3000);
  perform pg_temp.conferir((v ->> 'taxa_cents')::bigint = 500,
    'loja sem faixas: a taxa unica de sempre');
  v := cotar_entrega('aaaaaaaa-0000-0000-0000-000000000002', 'eeeeeeee-0000-0000-0000-000000000003', 3000);
  perform pg_temp.conferir(not (v ->> 'entrega')::boolean,
    'loja sem faixas: o raio de 5 km agora vale');

  perform pg_temp.conferir(
    (select count(*) from lojas_para_o_endereco('eeeeeeee-0000-0000-0000-000000000003') where not entrega) = 2,
    'a vitrine sabe quais lojas nao entregam no endereco');

  perform pg_temp.virar('11111111-1111-1111-1111-111111111111');
  perform pg_temp.deve_falhar(
    $q$select cotar_entrega('aaaaaaaa-0000-0000-0000-000000000001', 'eeeeeeee-0000-0000-0000-000000000001', 0)$q$,
    'cotar com o endereco de outra pessoa');
end;
$$;

-- -----------------------------------------------------------------------------
-- O fechamento cobra pela distancia e recusa fora da area
-- -----------------------------------------------------------------------------
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

do $$
declare v_id uuid;
begin
  v_id := fechar_pedido(pg_temp.carrinho(), 'delivery', 'cash', 'on_delivery',
    'eeeeeeee-0000-0000-0000-000000000002');
  perform pg_temp.conferir(
    (select delivery_fee_cents = 700 and total_cents = 3700 from orders where id = v_id),
    'o pedido a 4,4 km paga a segunda faixa');
  perform pg_temp.conferir(
    (select courier_fee_cents from deliveries where order_id = v_id) = 700,
    'e a corrida leva o mesmo valor');

  perform pg_temp.deve_falhar(
    format($q$select fechar_pedido('%s', 'delivery', 'cash', 'on_delivery',
      'eeeeeeee-0000-0000-0000-000000000003')$q$, pg_temp.carrinho()),
    'pedido para endereco fora da area');

  -- Retirada nao tem distancia nenhuma.
  v_id := fechar_pedido(pg_temp.carrinho(), 'pickup', 'cash', 'on_delivery');
  perform pg_temp.conferir((select delivery_fee_cents from orders where id = v_id) = 0,
    'retirada continua sem taxa, mesmo de longe');
end;
$$;

-- O lancamento pela loja, sem coordenada, cobra a maior faixa.
do $$
declare v_id uuid;
begin
  perform pg_temp.virar('11111111-1111-1111-1111-111111111111');
  v_id := lancar_pedido('aaaaaaaa-0000-0000-0000-000000000001',
    '{"tipo":"delivery","telefone":"62999990000",
      "endereco":{"rua":"Rua X","numero":"1","bairro":"Centro"},
      "itens":[{"produto_id":"dddddddd-0000-0000-0000-000000000001","quantidade":1}]}');
  perform pg_temp.conferir((select delivery_fee_cents from orders where id = v_id) = 700,
    'pedido por telefone, sem localizacao: a maior faixa');
end;
$$;

rollback;
