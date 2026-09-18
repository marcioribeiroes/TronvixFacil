-- =============================================================================
-- Tronvix Facil - o entregador e do estabelecimento
--
-- A promessa do produto e "o sistema nao gerencia a entrega". Estes testes
-- verificam que o banco cumpre isso: a corrida nao e leiloada para a
-- plataforma, e quem aprova o entregador e quem vai confiar a mochila a ele.
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

create or replace function pg_temp.visiveis(p_user uuid, p_tabela text)
returns int language plpgsql as $$
declare n int;
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  set local role authenticated;
  execute format('select count(*) from %I', p_tabela) into n;
  reset role;
  return n;
end;
$$;

-- -----------------------------------------------------------------------------
-- Cenario: dois estabelecimentos, tres entregadores
-- -----------------------------------------------------------------------------
insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'dono.burger@teste.test'),
  ('aaaa1111-1111-1111-1111-111111111111', 'dono.pizza@teste.test'),
  ('22222222-2222-2222-2222-222222222222', 'cliente@teste.test'),
  ('44444444-4444-4444-4444-444444444444', 'entregador.burger@teste.test'),
  ('55555555-5555-5555-5555-555555555555', 'entregador.pizza@teste.test'),
  ('66666666-6666-6666-6666-666666666666', 'autonomo@teste.test');

insert into restaurants (id, slug, name, status, is_open, delivery_fee_cents,
                         accepts_platform_couriers)
values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'burger', 'Burger House', 'approved', true, 700, false),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'pizza', 'Pizzaria', 'approved', true, 600, true);

insert into restaurant_members (restaurant_id, user_id, role) values
  ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'owner'),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'aaaa1111-1111-1111-1111-111111111111', 'owner');

insert into couriers (id, user_id, restaurant_id, status, availability) values
  ('77777777-0000-0000-0000-000000000001', '44444444-4444-4444-4444-444444444444',
   'aaaaaaaa-0000-0000-0000-000000000001', 'approved', 'online'),
  ('77777777-0000-0000-0000-000000000002', '55555555-5555-5555-5555-555555555555',
   'aaaaaaaa-0000-0000-0000-000000000002', 'approved', 'online'),
  -- Autonomo: sem estabelecimento.
  ('77777777-0000-0000-0000-000000000003', '66666666-6666-6666-6666-666666666666',
   null, 'approved', 'online');

insert into categories (id, restaurant_id, name)
values ('cccccccc-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'Lanches');

insert into products (id, restaurant_id, category_id, name, price_cents)
values ('dddddddd-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000001', 'X-Salada', 2500);

insert into addresses (id, user_id, street, number, district, city, state, postal_code)
values ('bbbbbbbb-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222',
        'Rua das Flores', '100', 'Centro', 'Vitoria', 'ES', '29010000');

-- Um pedido na Burger House, despachado.
do $$
declare v_cart uuid;
begin
  perform set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);
  insert into carts (user_id, restaurant_id)
  values ('22222222-2222-2222-2222-222222222222', 'aaaaaaaa-0000-0000-0000-000000000001')
  returning id into v_cart;
  insert into cart_items (cart_id, product_id, quantity)
  values (v_cart, 'dddddddd-0000-0000-0000-000000000001', 1);
  perform public.fechar_pedido(v_cart, 'delivery', 'cash', 'on_delivery',
                               'bbbbbbbb-0000-0000-0000-000000000001'::uuid);
end;
$$;

update deliveries set status = 'searching_courier';

grant usage on schema public to authenticated;
grant select on all tables in schema public to authenticated;

-- -----------------------------------------------------------------------------
-- A corrida e de quem emprega
-- -----------------------------------------------------------------------------
do $$
begin
  perform pg_temp.conferir(
    pg_temp.visiveis('44444444-4444-4444-4444-444444444444', 'deliveries') = 1,
    'o entregador do estabelecimento ve a corrida dele');
  perform pg_temp.conferir(
    pg_temp.visiveis('55555555-5555-5555-5555-555555555555', 'deliveries') = 0,
    'o entregador de outro estabelecimento nao ve a corrida');
  perform pg_temp.conferir(
    pg_temp.visiveis('66666666-6666-6666-6666-666666666666', 'deliveries') = 0,
    'o autonomo nao ve a corrida de quem nao aceita gente de fora');
end;
$$;

-- Ligar a chave abre a corrida ao autonomo — e so por isso.
do $$
begin
  update restaurants set accepts_platform_couriers = true
   where id = 'aaaaaaaa-0000-0000-0000-000000000001';

  perform pg_temp.conferir(
    pg_temp.visiveis('66666666-6666-6666-6666-666666666666', 'deliveries') = 1,
    'com a chave ligada, o autonomo passa a ver a corrida');
  perform pg_temp.conferir(
    pg_temp.visiveis('55555555-5555-5555-5555-555555555555', 'deliveries') = 0,
    'nem assim o entregador de outro estabelecimento ve');

  update restaurants set accepts_platform_couriers = false
   where id = 'aaaaaaaa-0000-0000-0000-000000000001';
end;
$$;

-- -----------------------------------------------------------------------------
-- A corrida na fila mostra o pedido — e so o necessario dele
-- -----------------------------------------------------------------------------
do $$
begin
  perform pg_temp.conferir(
    pg_temp.visiveis('44444444-4444-4444-4444-444444444444', 'orders') = 1,
    'o entregador ve o pedido da corrida oferecida a ele');
  perform pg_temp.conferir(
    pg_temp.visiveis('44444444-4444-4444-4444-444444444444', 'payments') = 1,
    'e ve como o cliente vai pagar, antes de decidir se aceita');
  perform pg_temp.conferir(
    pg_temp.visiveis('44444444-4444-4444-4444-444444444444', 'order_items') = 0,
    'mas nao ve o que a pessoa comeu: isso nao e assunto de quem carrega a sacola');
  perform pg_temp.conferir(
    pg_temp.visiveis('55555555-5555-5555-5555-555555555555', 'orders') = 0,
    'o entregador de outro estabelecimento nao ve o pedido');
end;
$$;

-- -----------------------------------------------------------------------------
-- Quem aprova
-- -----------------------------------------------------------------------------
insert into auth.users (id, email)
values ('88888888-8888-8888-8888-888888888888', 'novato@teste.test');

insert into couriers (id, user_id, restaurant_id, status)
values ('77777777-0000-0000-0000-000000000004',
        '88888888-8888-8888-8888-888888888888',
        'aaaaaaaa-0000-0000-0000-000000000001', 'pending');

do $$
begin
  -- Ninguem se aprova.
  perform set_config('request.jwt.claim.sub', '88888888-8888-8888-8888-888888888888', true);
  perform pg_temp.deve_falhar(
    $f$update couriers set status = 'approved'
        where id = '77777777-0000-0000-0000-000000000004'$f$,
    'o entregador aprovando a si mesmo');

  -- Nem o estabelecimento vizinho.
  perform set_config('request.jwt.claim.sub', 'aaaa1111-1111-1111-1111-111111111111', true);
  perform pg_temp.deve_falhar(
    $f$update couriers set status = 'approved'
        where id = '77777777-0000-0000-0000-000000000004'$f$,
    'outro estabelecimento aprovando entregador alheio');

  -- O dono do estabelecimento dele, sim.
  perform set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
  update couriers set status = 'approved'
   where id = '77777777-0000-0000-0000-000000000004';
  perform pg_temp.conferir(
    (select status from couriers where id = '77777777-0000-0000-0000-000000000004') = 'approved',
    'o estabelecimento aprova o proprio entregador');
end;
$$;

-- -----------------------------------------------------------------------------
-- O vinculo nao e do entregador
-- -----------------------------------------------------------------------------
do $$
begin
  perform set_config('request.jwt.claim.sub', '88888888-8888-8888-8888-888888888888', true);
  perform pg_temp.deve_falhar(
    $f$update couriers set restaurant_id = 'aaaaaaaa-0000-0000-0000-000000000002'
        where id = '77777777-0000-0000-0000-000000000004'$f$,
    'entregador aprovado se mudando de estabelecimento por conta propria');
end;
$$;

-- E a reputacao continua fora do alcance dos dois.
do $$
begin
  perform set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
  update couriers set deliveries_count = 999, rating_avg = 5
   where id = '77777777-0000-0000-0000-000000000001';

  perform pg_temp.conferir(
    (select deliveries_count from couriers
      where id = '77777777-0000-0000-0000-000000000001') = 0,
    'nem o estabelecimento infla a reputacao do proprio entregador');
end;
$$;

-- -----------------------------------------------------------------------------
-- O estabelecimento enxerga a propria equipe de entrega
-- -----------------------------------------------------------------------------
do $$
begin
  perform pg_temp.conferir(
    pg_temp.visiveis('11111111-1111-1111-1111-111111111111', 'couriers') = 2,
    'o estabelecimento ve os dois entregadores dele');
  perform pg_temp.conferir(
    pg_temp.visiveis('aaaa1111-1111-1111-1111-111111111111', 'couriers') = 1,
    'e ve so os dele — nao os do vizinho');
  perform pg_temp.conferir(
    pg_temp.visiveis('66666666-6666-6666-6666-666666666666', 'couriers') = 1,
    'o autonomo ve apenas o proprio cadastro');
end;
$$;

-- Aceita a corrida fecha a porta para os outros: o pedido some da fila e, com
-- ele, some para quem nao vai levar.
do $$
begin
  update deliveries
     set courier_id = '77777777-0000-0000-0000-000000000001',
         status = 'assigned';

  perform pg_temp.conferir(
    pg_temp.visiveis('44444444-4444-4444-4444-444444444444', 'orders') = 1,
    'quem aceitou continua vendo o pedido');
  perform pg_temp.conferir(
    pg_temp.visiveis('88888888-8888-8888-8888-888888888888', 'orders') = 0,
    'o colega do mesmo estabelecimento deixa de ver o pedido tomado');
end;
$$;

rollback;
