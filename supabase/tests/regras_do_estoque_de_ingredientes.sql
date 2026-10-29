-- =============================================================================
-- Tronvix Facil - estoque de ingredientes
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

create or replace function pg_temp.saldo(p_nome text)
returns numeric language sql as $$
  select stock_quantity from ingredients where name = p_nome and deleted_at is null;
$$;

grant usage on schema public to authenticated;
grant select, delete on all tables in schema public to authenticated;

-- -----------------------------------------------------------------------------
-- Cenario: uma loja com dono e cozinheiro, e uma vizinha
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
   'cccccccc-0000-0000-0000-000000000001', 'Filé à Parmegiana', 4500),
  ('dddddddd-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000001',
   'cccccccc-0000-0000-0000-000000000001', 'Refrigerante', 600);

-- -----------------------------------------------------------------------------
-- O cadastro
-- -----------------------------------------------------------------------------
do $$
begin
  perform set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
  perform salvar_ingrediente('aaaaaaaa-0000-0000-0000-000000000001', 'Filé mignon', 'kg');
  perform salvar_ingrediente('aaaaaaaa-0000-0000-0000-000000000001', 'Queijo', 'kg');
  perform salvar_ingrediente('aaaaaaaa-0000-0000-0000-000000000001', 'Tomate', 'kg');
  perform pg_temp.conferir(
    (select count(*) = 3 and bool_and(stock_quantity = 0) from ingredients),
    'a gestao cadastra ingrediente, que nasce com saldo zero');

  perform pg_temp.deve_falhar(
    $q$select salvar_ingrediente('aaaaaaaa-0000-0000-0000-000000000001', 'file MIGNON', 'kg')$q$,
    'o mesmo ingrediente cadastrado duas vezes, mudando acento e caixa');
  perform pg_temp.deve_falhar(
    $q$select salvar_ingrediente('aaaaaaaa-0000-0000-0000-000000000001', 'Leite', 'litro')$q$,
    'unidade fora da lista');

  perform set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);
  perform pg_temp.deve_falhar(
    $q$select salvar_ingrediente('aaaaaaaa-0000-0000-0000-000000000001', 'Leite', 'L')$q$,
    'o atendente cadastrando ingrediente');

  perform set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', true);
  perform pg_temp.deve_falhar(
    $q$select salvar_ingrediente('aaaaaaaa-0000-0000-0000-000000000001', 'Leite', 'L')$q$,
    'dono de outra loja cadastrando aqui');
end;
$$;

-- -----------------------------------------------------------------------------
-- Entrada e saida manuais
-- -----------------------------------------------------------------------------
do $$
declare
  v_file uuid := (select id from ingredients where name = 'Filé mignon');
  v_queijo uuid := (select id from ingredients where name = 'Queijo');
begin
  perform set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
  perform movimentar_ingredientes('aaaaaaaa-0000-0000-0000-000000000001', 'in',
    jsonb_build_array(
      jsonb_build_object('ingrediente', v_file, 'quantidade', '10.5'),
      jsonb_build_object('ingrediente', v_queijo, 'quantidade', 4)),
    'Nota 55');
  perform pg_temp.conferir(pg_temp.saldo('Filé mignon') = 10.5 and pg_temp.saldo('Queijo') = 4,
    'a entrada soma no saldo, com casas decimais');

  perform movimentar_ingredientes('aaaaaaaa-0000-0000-0000-000000000001', 'out',
    jsonb_build_array(jsonb_build_object('ingrediente', v_queijo, 'quantidade', 0.5)),
    'Caiu no chao');
  perform pg_temp.conferir(pg_temp.saldo('Queijo') = 3.5, 'a saida manual tira do saldo');

  perform pg_temp.conferir(
    (select count(*) = 3 and bool_and(source = 'manual' and created_by is not null)
       from ingredient_movements),
    'cada lancamento deixa uma linha no livro, com autor');
  perform pg_temp.conferir(
    (select balance_after = 3.5 and reason = 'Caiu no chao'
       from ingredient_movements where kind = 'out'),
    'o livro guarda o motivo e o saldo depois');

  -- Tudo ou nada.
  perform pg_temp.deve_falhar(
    format($q$select movimentar_ingredientes('aaaaaaaa-0000-0000-0000-000000000001', 'in',
       '[{"ingrediente": "%s", "quantidade": 1}, {"ingrediente": "%s", "quantidade": -2}]')$q$,
       v_file, v_queijo),
    'lancamento com uma quantidade negativa');
  perform pg_temp.conferir(pg_temp.saldo('Filé mignon') = 10.5,
    'lancamento recusado nao deixa metade');

  perform pg_temp.deve_falhar(
    format($q$select salvar_ingrediente('aaaaaaaa-0000-0000-0000-000000000001',
       'Queijo', 'g', '%s')$q$, v_queijo),
    'trocar a unidade de quem ja tem lancamento');

  perform set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);
  perform pg_temp.deve_falhar(
    format($q$select movimentar_ingredientes('aaaaaaaa-0000-0000-0000-000000000001', 'in',
       '[{"ingrediente": "%s", "quantidade": 100}]')$q$, v_file),
    'o atendente dando entrada');
end;
$$;

-- -----------------------------------------------------------------------------
-- O preparo gasta, e apagar o preparo devolve
-- -----------------------------------------------------------------------------
do $$
declare
  v_numero int;
begin
  perform set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);
  v_numero := lancar_preparo('aaaaaaaa-0000-0000-0000-000000000001', current_date,
    'Molho', 'Filé à Parmegiana',
    '[{"nome": "tomate", "quantidade": "2"}, {"nome": "Queijo", "quantidade": 1}]');

  perform pg_temp.conferir(pg_temp.saldo('Tomate') = -2,
    'o preparo gasta o que nao havia: o saldo fica negativo, e o lancamento entra');
  perform pg_temp.conferir(pg_temp.saldo('Queijo') = 2.5, 'e tira o queijo');
  perform pg_temp.conferir(
    (select count(*) = 2 and bool_and(source = 'prep' and kind = 'out' and prep_id is not null)
       from ingredient_movements where source = 'prep'),
    'a saida do preparo fica no livro, apontando para ele');

  perform set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
  set local role authenticated;
  delete from kitchen_preps where number = v_numero;
  reset role;

  perform pg_temp.conferir(pg_temp.saldo('Tomate') = 0 and pg_temp.saldo('Queijo') = 3.5,
    'apagar o preparo devolve ao estoque o que ele tirou');
  perform pg_temp.conferir(
    (select count(*) = 2 from ingredient_movements
      where source = 'prep' and kind = 'in' and reason like '%apagado'),
    'e a devolucao fica no livro');
end;
$$;

-- -----------------------------------------------------------------------------
-- A ficha tecnica e o pedido pronto
-- -----------------------------------------------------------------------------
do $$
declare
  v_file uuid := (select id from ingredients where name = 'Filé mignon');
  v_queijo uuid := (select id from ingredients where name = 'Queijo');
begin
  perform set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
  perform salvar_ficha_tecnica('dddddddd-0000-0000-0000-000000000001',
    jsonb_build_array(
      jsonb_build_object('ingrediente', v_file, 'quantidade', 0.25),
      jsonb_build_object('ingrediente', v_queijo, 'quantidade', 0.1)));
  perform pg_temp.conferir(
    (select count(*) = 2 from product_ingredients
      where product_id = 'dddddddd-0000-0000-0000-000000000001'),
    'a gestao monta a ficha tecnica do produto');

  perform pg_temp.deve_falhar(
    format($q$select salvar_ficha_tecnica('dddddddd-0000-0000-0000-000000000001',
       '[{"ingrediente": "%s", "quantidade": 1}, {"ingrediente": "%s", "quantidade": 2}]')$q$,
       v_file, v_file),
    'o mesmo ingrediente duas vezes na ficha');
  perform pg_temp.conferir(
    (select count(*) = 2 from product_ingredients),
    'ficha recusada continua como estava');

  perform set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);
  perform pg_temp.deve_falhar(
    $q$select salvar_ficha_tecnica('dddddddd-0000-0000-0000-000000000001', '[]')$q$,
    'o atendente mexendo na ficha tecnica');
end;
$$;

insert into orders (id, restaurant_id, number, customer_name, status, fulfillment,
                    subtotal_cents, delivery_fee_cents, total_cents)
values ('eeeeeeee-0000-0000-0000-000000000001',
        'aaaaaaaa-0000-0000-0000-000000000001', 7, 'Mesa 3', 'received', 'pickup',
        9600, 0, 9600);

insert into order_items (order_id, product_id, product_name, unit_price_cents, quantity, total_cents)
values
  ('eeeeeeee-0000-0000-0000-000000000001', 'dddddddd-0000-0000-0000-000000000001',
   'Filé à Parmegiana', 4500, 2, 9000),
  ('eeeeeeee-0000-0000-0000-000000000001', 'dddddddd-0000-0000-0000-000000000002',
   'Refrigerante', 600, 1, 600);

do $$
begin
  update orders set status = 'confirmed' where id = 'eeeeeeee-0000-0000-0000-000000000001';
  perform pg_temp.conferir(pg_temp.saldo('Filé mignon') = 10.5,
    'pedido aceito ainda nao gasta nada');

  update orders set status = 'ready' where id = 'eeeeeeee-0000-0000-0000-000000000001';
  perform pg_temp.conferir(
    pg_temp.saldo('Filé mignon') = 10 and pg_temp.saldo('Queijo') = 3.3,
    'pedido pronto gasta a ficha tecnica vezes a quantidade de cada item');
  perform pg_temp.conferir(
    (select count(*) = 2 and bool_and(source = 'order' and reason = 'Pedido nº 7')
       from ingredient_movements where order_id = 'eeeeeeee-0000-0000-0000-000000000001'),
    'produto sem ficha (o refrigerante) nao gasta nada, e a saida aponta para o pedido');

  update orders set status = 'delivered' where id = 'eeeeeeee-0000-0000-0000-000000000001';
  perform pg_temp.conferir(pg_temp.saldo('Filé mignon') = 10,
    'concluir o pedido nao gasta de novo');
end;
$$;

-- -----------------------------------------------------------------------------
-- Quem enxerga
-- -----------------------------------------------------------------------------
do $$
declare
  n int;
begin
  perform set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);
  set local role authenticated;
  select count(*) into n from ingredients;
  perform pg_temp.conferir(n = 3, 'a cozinha ve os ingredientes da loja');
  reset role;

  perform set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', true);
  set local role authenticated;
  select count(*) into n from ingredients;
  perform pg_temp.conferir(n = 0, 'outra loja nao ve os ingredientes daqui');
  select count(*) into n from ingredient_movements;
  perform pg_temp.conferir(n = 0, 'nem o livro');
  select count(*) into n from product_ingredients;
  perform pg_temp.conferir(n = 0, 'nem a ficha tecnica');
  reset role;
end;
$$;

-- Arquivar tira o ingrediente da ficha, e o livro continua.
do $$
begin
  perform set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
  perform arquivar_ingrediente((select id from ingredients where name = 'Queijo'));
  perform pg_temp.conferir(
    (select count(*) = 1 from product_ingredients)
    and (select count(*) > 0 from ingredient_movements m
           join ingredients i on i.id = m.ingredient_id where i.name = 'Queijo'),
    'arquivar tira da ficha tecnica e preserva o livro');
end;
$$;

rollback;
