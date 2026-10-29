-- =============================================================================
-- Tronvix Facil - cozinha: o livro de preparos
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

grant usage on schema public to authenticated;
grant select, delete on all tables in schema public to authenticated;

-- -----------------------------------------------------------------------------
-- Cenario: duas lojas; na primeira, um dono e um atendente
-- -----------------------------------------------------------------------------
insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'dono@teste.test'),
  ('22222222-2222-2222-2222-222222222222', 'cozinheiro@teste.test'),
  ('33333333-3333-3333-3333-333333333333', 'dono.vizinho@teste.test');

insert into restaurants (id, slug, name, status, delivery_fee_cents) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'cantina', 'Cantina', 'approved', 700),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'vizinho', 'Vizinho', 'approved', 700);

insert into restaurant_members (restaurant_id, user_id, role) values
  ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'owner'),
  ('aaaaaaaa-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 'staff'),
  ('aaaaaaaa-0000-0000-0000-000000000002', '33333333-3333-3333-3333-333333333333', 'owner');

insert into categories (id, restaurant_id, name) values
  ('cccccccc-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'Pratos');

insert into products (id, restaurant_id, category_id, name, price_cents) values
  ('dddddddd-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001',
   'cccccccc-0000-0000-0000-000000000001', 'Filé à Parmegiana', 4500);

-- -----------------------------------------------------------------------------
-- O lancamento
-- -----------------------------------------------------------------------------
do $$
declare
  v_primeiro int;
  v_segundo int;
begin
  -- Quem lanca e a cozinha: o atendente pode.
  perform set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);
  set local role authenticated;

  v_primeiro := lancar_preparo(
    'aaaaaaaa-0000-0000-0000-000000000001', current_date, 'Molho de tomate',
    'file a parmegiana',
    '[{"nome": "Tomate", "quantidade": 2.5, "unidade": "kg"},
      {"nome": "Cebola", "quantidade": "0.4", "unidade": "kg"},
      {"nome": "Sal"}]',
    'Lote 12');

  v_segundo := lancar_preparo(
    'aaaaaaaa-0000-0000-0000-000000000001', current_date - 1, 'Purê de batata',
    'Prato executivo',
    '[{"nome": "Batata", "quantidade": 3, "unidade": "kg"}]');
  reset role;

  perform pg_temp.conferir(v_primeiro = 1 and v_segundo = 2,
    'o numero do preparo e sequencial na loja');
  perform pg_temp.conferir(
    (select product_id = 'dddddddd-0000-0000-0000-000000000001'
            and product_name = 'Filé à Parmegiana'
            and created_by = '22222222-2222-2222-2222-222222222222'
            and notes = 'Lote 12'
       from kitchen_preps where number = 1),
    'o prato que bate com o cardapio, sem acento, fica ligado ao produto');
  perform pg_temp.conferir(
    (select product_id is null and product_name = 'Prato executivo'
       from kitchen_preps where number = 2),
    'o prato fora do cardapio fica com o nome digitado');
  perform pg_temp.conferir(
    (select count(*) = 3 and sum(quantity) = 2.9
       from kitchen_prep_ingredients i join kitchen_preps p on p.id = i.prep_id
      where p.number = 1),
    'os ingredientes entram juntos, com quantidade opcional');
end;
$$;

do $$
begin
  perform set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', true);
  perform pg_temp.deve_falhar(
    $q$select lancar_preparo('aaaaaaaa-0000-0000-0000-000000000001', current_date,
       'Intruso', 'Prato', '[{"nome": "Sal"}]')$q$,
    'dono de outra loja lancando preparo aqui');

  perform set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);
  perform pg_temp.deve_falhar(
    $q$select lancar_preparo('aaaaaaaa-0000-0000-0000-000000000001', current_date,
       'Sem nada', 'Prato', '[]')$q$,
    'preparo sem ingrediente');
  perform pg_temp.deve_falhar(
    $q$select lancar_preparo('aaaaaaaa-0000-0000-0000-000000000001', current_date,
       'Molho', 'Prato', '[{"nome": "Tomate"}, {"nome": "  "}]')$q$,
    'ingrediente sem nome');
  perform pg_temp.deve_falhar(
    $q$select lancar_preparo('aaaaaaaa-0000-0000-0000-000000000001', current_date,
       'Molho', 'Prato', '[{"nome": "Tomate", "quantidade": -1}]')$q$,
    'quantidade negativa');
  perform pg_temp.deve_falhar(
    $q$select lancar_preparo('aaaaaaaa-0000-0000-0000-000000000001', current_date + 30,
       'Molho', 'Prato', '[{"nome": "Tomate"}]')$q$,
    'data no futuro');

  perform pg_temp.conferir(
    (select count(*) = 2 from kitchen_preps),
    'lancamento recusado nao deixa metade');
end;
$$;

-- -----------------------------------------------------------------------------
-- A busca e quem enxerga
-- -----------------------------------------------------------------------------
do $$
declare
  n int;
begin
  perform set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);
  set local role authenticated;

  select count(*) into n from buscar_preparos('aaaaaaaa-0000-0000-0000-000000000001',
    p_ingrediente => 'CEBOLA');
  perform pg_temp.conferir(n = 1, 'acha o preparo pelo ingrediente, sem ligar para caixa');

  select count(*) into n from buscar_preparos('aaaaaaaa-0000-0000-0000-000000000001',
    p_preparo => 'pure');
  perform pg_temp.conferir(n = 1, 'acha o preparo pelo nome, sem acento');

  select count(*) into n from buscar_preparos('aaaaaaaa-0000-0000-0000-000000000001',
    p_prato => 'parmeg');
  perform pg_temp.conferir(n = 1, 'acha pelo nome do prato');

  select count(*) into n from buscar_preparos('aaaaaaaa-0000-0000-0000-000000000001',
    p_de => current_date, p_ate => current_date);
  perform pg_temp.conferir(n = 1, 'filtra pela data');

  select count(*) into n from buscar_preparos('aaaaaaaa-0000-0000-0000-000000000001',
    p_numero => 2);
  perform pg_temp.conferir(n = 1, 'filtra pelo numero');

  -- O atendente le, mas nao apaga: o livro so vale se a linha do erro fica.
  delete from kitchen_preps where number = 1;
  perform pg_temp.conferir((select count(*) = 2 from kitchen_preps),
    'o atendente nao apaga preparo');
  reset role;

  perform set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', true);
  set local role authenticated;
  select count(*) into n from buscar_preparos('aaaaaaaa-0000-0000-0000-000000000001');
  perform pg_temp.conferir(n = 0, 'outra loja nao ve os preparos daqui');
  select count(*) into n from kitchen_prep_ingredients;
  perform pg_temp.conferir(n = 0, 'nem os ingredientes');
  reset role;

  perform set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
  set local role authenticated;
  delete from kitchen_preps where number = 1;
  reset role;
  perform pg_temp.conferir(
    (select count(*) = 1 from kitchen_preps)
    and (select count(*) = 1 from kitchen_prep_ingredients),
    'a gestao apaga, e os ingredientes vao junto');
end;
$$;

rollback;
