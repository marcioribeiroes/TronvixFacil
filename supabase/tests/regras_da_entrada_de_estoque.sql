-- =============================================================================
-- Tronvix Facil - codigo de barras e entrada de estoque
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
  when check_violation or insufficient_privilege or unique_violation or no_data_found then
    raise notice 'ok - rejeitado como esperado: %', p_contexto;
end;
$$;

-- -----------------------------------------------------------------------------
-- Cenario: duas lojas; na primeira, um dono e um atendente
-- -----------------------------------------------------------------------------
insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'dono@teste.test'),
  ('22222222-2222-2222-2222-222222222222', 'atendente@teste.test'),
  ('33333333-3333-3333-3333-333333333333', 'dono.vizinho@teste.test');

insert into restaurants (id, slug, name, status, delivery_fee_cents) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'mercearia', 'Mercearia', 'approved', 700),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'vizinho', 'Vizinho', 'approved', 700);

insert into restaurant_members (restaurant_id, user_id, role) values
  ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'owner'),
  ('aaaaaaaa-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 'staff'),
  ('aaaaaaaa-0000-0000-0000-000000000002', '33333333-3333-3333-3333-333333333333', 'owner');

insert into categories (id, restaurant_id, name) values
  ('cccccccc-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'Bebidas'),
  ('cccccccc-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000002', 'Bebidas');

insert into products (id, restaurant_id, category_id, name, price_cents, barcode, track_stock, stock_quantity) values
  ('dddddddd-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001',
   'cccccccc-0000-0000-0000-000000000001', 'Refrigerante lata', 600, '7894900011517', true, 5),
  ('dddddddd-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000001',
   'cccccccc-0000-0000-0000-000000000001', 'Agua', 400, null, false, 0),
  ('dddddddd-0000-0000-0000-000000000003', 'aaaaaaaa-0000-0000-0000-000000000002',
   'cccccccc-0000-0000-0000-000000000002', 'Refrigerante do vizinho', 600, '7894900011517', false, 0);

-- -----------------------------------------------------------------------------
-- O codigo de barras
-- -----------------------------------------------------------------------------
do $$
begin
  perform pg_temp.conferir(true, 'o mesmo codigo vale em lojas diferentes');

  perform pg_temp.deve_falhar(
    $q$insert into products (restaurant_id, category_id, name, price_cents, barcode)
       values ('aaaaaaaa-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-000000000001',
               'Outro', 500, '7894900011517')$q$,
    'dois produtos ativos da mesma loja com o mesmo codigo');

  perform pg_temp.deve_falhar(
    $q$update products set barcode = '789 490' where id = 'dddddddd-0000-0000-0000-000000000002'$q$,
    'codigo com espaco');

  perform pg_temp.deve_falhar(
    $q$update products set barcode = '' where id = 'dddddddd-0000-0000-0000-000000000002'$q$,
    'codigo vazio');

  -- Produto apagado libera o codigo para o substituto.
  update products set deleted_at = now() where id = 'dddddddd-0000-0000-0000-000000000001';
  insert into products (id, restaurant_id, category_id, name, price_cents, barcode)
  values ('dddddddd-0000-0000-0000-000000000009', 'aaaaaaaa-0000-0000-0000-000000000001',
          'cccccccc-0000-0000-0000-000000000001', 'Substituto', 500, '7894900011517');
  perform pg_temp.conferir(true, 'produto apagado devolve o codigo');
  delete from products where id = 'dddddddd-0000-0000-0000-000000000009';
  update products set deleted_at = null where id = 'dddddddd-0000-0000-0000-000000000001';
end;
$$;

-- -----------------------------------------------------------------------------
-- A entrada
-- -----------------------------------------------------------------------------
do $$
declare
  v_total int;
begin
  perform set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
  set local role authenticated;

  v_total := dar_entrada_no_estoque(
    'aaaaaaaa-0000-0000-0000-000000000001',
    '[{"produto": "dddddddd-0000-0000-0000-000000000001", "quantidade": 12},
      {"produto": "dddddddd-0000-0000-0000-000000000002", "quantidade": 24}]',
    'Nota 1234');
  reset role;

  perform pg_temp.conferir(v_total = 36, 'a entrada devolve quantas unidades entraram');
  perform pg_temp.conferir(
    (select stock_quantity from products where id = 'dddddddd-0000-0000-0000-000000000001') = 17,
    'soma no saldo de quem ja controlava');
  perform pg_temp.conferir(
    (select track_stock and stock_quantity = 24 from products where id = 'dddddddd-0000-0000-0000-000000000002'),
    'quem nao controlava passa a controlar, a partir do que chegou');
  perform pg_temp.conferir(
    (select count(*) = 2 and bool_and(kind = 'in' and reason = 'Nota 1234'
                                       and created_by = '11111111-1111-1111-1111-111111111111')
       from stock_movements where restaurant_id = 'aaaaaaaa-0000-0000-0000-000000000001'),
    'cada item deixa uma linha de entrada no livro, com motivo e autor');
  perform pg_temp.conferir(
    (select balance_after = 17 from stock_movements where product_id = 'dddddddd-0000-0000-0000-000000000001'),
    'o livro guarda o saldo depois da entrada');
end;
$$;

do $$
begin
  -- Tudo ou nada: o segundo item e de outra loja, e o primeiro nao pode ficar.
  perform set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
  perform pg_temp.deve_falhar(
    $q$select dar_entrada_no_estoque('aaaaaaaa-0000-0000-0000-000000000001',
       '[{"produto": "dddddddd-0000-0000-0000-000000000001", "quantidade": 1},
         {"produto": "dddddddd-0000-0000-0000-000000000003", "quantidade": 1}]')$q$,
    'produto de outra loja');
  perform pg_temp.conferir(
    (select stock_quantity from products where id = 'dddddddd-0000-0000-0000-000000000001') = 17,
    'entrada recusada nao deixa metade');

  perform pg_temp.deve_falhar(
    $q$select dar_entrada_no_estoque('aaaaaaaa-0000-0000-0000-000000000001',
       '[{"produto": "dddddddd-0000-0000-0000-000000000001", "quantidade": 0}]')$q$,
    'quantidade zero');
  perform pg_temp.deve_falhar(
    $q$select dar_entrada_no_estoque('aaaaaaaa-0000-0000-0000-000000000001',
       '[{"produto": "dddddddd-0000-0000-0000-000000000001", "quantidade": 1.5}]')$q$,
    'quantidade quebrada');
  perform pg_temp.deve_falhar(
    $q$select dar_entrada_no_estoque('aaaaaaaa-0000-0000-0000-000000000001', '[]')$q$,
    'entrada sem itens');

  perform set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);
  perform pg_temp.deve_falhar(
    $q$select dar_entrada_no_estoque('aaaaaaaa-0000-0000-0000-000000000001',
       '[{"produto": "dddddddd-0000-0000-0000-000000000001", "quantidade": 1}]')$q$,
    'atendente dando entrada');

  perform set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', true);
  perform pg_temp.deve_falhar(
    $q$select dar_entrada_no_estoque('aaaaaaaa-0000-0000-0000-000000000001',
       '[{"produto": "dddddddd-0000-0000-0000-000000000001", "quantidade": 1}]')$q$,
    'dono de outra loja dando entrada');
end;
$$;

rollback;
