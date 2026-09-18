-- =============================================================================
-- Tronvix Facil - o horario de funcionamento
--
-- restaurant_hours existia desde o primeiro dia, com tela no painel, e nunca
-- foi lida por ninguem. Quem cadastrava "abre as 18h" via a loja aberta as seis
-- da manha e recebia pedido que nao tinha como atender.
--
-- Estes testes prendem as duas pontas: que o horario fecha de verdade, e que
-- ele nao fecha quem nunca o preencheu.
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


-- -----------------------------------------------------------------------------
-- Cenario: tres lojas em Goiania
--
--   almoco    11:00 as 15:00, de segunda a sexta
--   noite     18:00 as 02:00, todo dia — a faixa que atravessa a meia-noite
--   sem hora  nunca preencheu a tela
-- -----------------------------------------------------------------------------
insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'dono@teste.test'),
  ('22222222-2222-2222-2222-222222222222', 'cliente@teste.test');

insert into restaurants (id, slug, name, status, is_open, min_order_cents, timezone)
values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'almoco', 'Marmita da Praca',
   'approved', true, 0, 'America/Sao_Paulo'),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'noite', 'Pizzaria da Madrugada',
   'approved', true, 0, 'America/Sao_Paulo'),
  ('aaaaaaaa-0000-0000-0000-000000000003', 'sem-hora', 'Sem Horario',
   'approved', true, 0, 'America/Sao_Paulo');

insert into restaurant_members (restaurant_id, user_id, role) values
  ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'owner'),
  ('aaaaaaaa-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'owner'),
  ('aaaaaaaa-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111', 'owner');

-- Segunda a sexta, 11h as 15h.
insert into restaurant_hours (restaurant_id, weekday, opens_at, closes_at)
select 'aaaaaaaa-0000-0000-0000-000000000001', d, '11:00', '15:00'
  from generate_series(1, 5) d;

-- Todo dia, 18h as 02h.
insert into restaurant_hours (restaurant_id, weekday, opens_at, closes_at)
select 'aaaaaaaa-0000-0000-0000-000000000002', d, '18:00', '02:00'
  from generate_series(0, 6) d;

-- Um momento conhecido, para nao depender do relogio de quem roda o teste.
-- 2026-09-16 e uma quarta-feira.
create or replace function pg_temp.em(p_local text)
returns timestamptz language sql immutable as $$
  select (p_local::timestamp at time zone 'America/Sao_Paulo');
$$;

-- -----------------------------------------------------------------------------
-- A faixa comum
-- -----------------------------------------------------------------------------
do $$
begin
  perform pg_temp.conferir(
    app.dentro_do_horario('aaaaaaaa-0000-0000-0000-000000000001',
                          pg_temp.em('2026-09-16 12:30')),
    'quarta ao meio-dia: a marmitaria esta no horario');

  perform pg_temp.conferir(
    not app.dentro_do_horario('aaaaaaaa-0000-0000-0000-000000000001',
                              pg_temp.em('2026-09-16 06:00')),
    'quarta as seis da manha: fora do horario — era este o defeito');

  perform pg_temp.conferir(
    not app.dentro_do_horario('aaaaaaaa-0000-0000-0000-000000000001',
                              pg_temp.em('2026-09-16 15:00')),
    'as 15:00 em ponto ja fechou: a faixa nao inclui o fim');

  perform pg_temp.conferir(
    app.dentro_do_horario('aaaaaaaa-0000-0000-0000-000000000001',
                          pg_temp.em('2026-09-16 11:00')),
    'as 11:00 em ponto abriu: a faixa inclui o comeco');

  perform pg_temp.conferir(
    not app.dentro_do_horario('aaaaaaaa-0000-0000-0000-000000000001',
                              pg_temp.em('2026-09-20 12:30')),
    'domingo ao meio-dia: a marmitaria nao abre no fim de semana');
end;
$$;

-- -----------------------------------------------------------------------------
-- A faixa que atravessa a meia-noite — onde a pizzaria mais vende
-- -----------------------------------------------------------------------------
do $$
begin
  perform pg_temp.conferir(
    app.dentro_do_horario('aaaaaaaa-0000-0000-0000-000000000002',
                          pg_temp.em('2026-09-16 20:00')),
    'oito da noite: a pizzaria esta aberta');

  perform pg_temp.conferir(
    app.dentro_do_horario('aaaaaaaa-0000-0000-0000-000000000002',
                          pg_temp.em('2026-09-17 00:30')),
    'meia-noite e meia: continua aberta — a faixa veio de ontem');

  perform pg_temp.conferir(
    app.dentro_do_horario('aaaaaaaa-0000-0000-0000-000000000002',
                          pg_temp.em('2026-09-17 01:59')),
    'uma e cinquenta e nove: ainda dentro');

  perform pg_temp.conferir(
    not app.dentro_do_horario('aaaaaaaa-0000-0000-0000-000000000002',
                              pg_temp.em('2026-09-17 02:00')),
    'duas em ponto: fechou');

  perform pg_temp.conferir(
    not app.dentro_do_horario('aaaaaaaa-0000-0000-0000-000000000002',
                              pg_temp.em('2026-09-16 15:00')),
    'tres da tarde: a pizzaria ainda nao abriu');
end;
$$;

-- -----------------------------------------------------------------------------
-- Quem nunca preencheu a tela nao pode ser fechado por isso
-- -----------------------------------------------------------------------------
do $$
begin
  perform pg_temp.conferir(
    app.dentro_do_horario('aaaaaaaa-0000-0000-0000-000000000003',
                          pg_temp.em('2026-09-16 04:00')),
    'sem horario cadastrado, quem manda e so a chave da mao');
end;
$$;

-- -----------------------------------------------------------------------------
-- O fuso e da loja, nao do servidor
-- -----------------------------------------------------------------------------
do $$
begin
  -- O Postgres do Supabase roda em UTC. 12:30 em Goiania e 15:30 UTC; comparar
  -- direto abriria a loja tres horas cedo.
  perform pg_temp.conferir(
    app.dentro_do_horario('aaaaaaaa-0000-0000-0000-000000000001',
                          '2026-09-16 15:30+00'::timestamptz),
    'meio-dia e meia em Goiania, que e 15:30 em UTC: aberto');

  perform pg_temp.conferir(
    not app.dentro_do_horario('aaaaaaaa-0000-0000-0000-000000000001',
                              '2026-09-16 12:30+00'::timestamptz),
    'meio-dia e meia em UTC, que e 09:30 em Goiania: fechado');
end;
$$;

-- -----------------------------------------------------------------------------
-- A coluna calculada, que e o que a vitrine le
-- -----------------------------------------------------------------------------
do $$
declare v_loja restaurants;
begin
  select * into v_loja from restaurants
   where id = 'aaaaaaaa-0000-0000-0000-000000000003';

  perform pg_temp.conferir(aberto_agora(v_loja),
    'loja sem horario, com a chave ligada: aberta');

  update restaurants set is_open = false
   where id = 'aaaaaaaa-0000-0000-0000-000000000003';
  select * into v_loja from restaurants
   where id = 'aaaaaaaa-0000-0000-0000-000000000003';

  perform pg_temp.conferir(not aberto_agora(v_loja),
    'a chave da mao fecha, mesmo sem horario nenhum');

  -- Suspender e ato da plataforma: app.guard_restaurant_platform_fields recusa
  -- que a propria loja mexa na situacao. A chave de servico e a outra forma de
  -- ser a plataforma.
  perform set_config('request.jwt.claim.role', 'service_role', true);
  update restaurants set is_open = true, status = 'suspended'
   where id = 'aaaaaaaa-0000-0000-0000-000000000003';
  perform set_config('request.jwt.claim.role', '', true);
  select * into v_loja from restaurants
   where id = 'aaaaaaaa-0000-0000-0000-000000000003';

  perform pg_temp.conferir(not aberto_agora(v_loja),
    'loja suspensa nao esta aberta, por mais ligada que a chave esteja');
end;
$$;

-- -----------------------------------------------------------------------------
-- E o pedido? Fora do horario, o banco recusa.
-- -----------------------------------------------------------------------------
insert into categories (id, restaurant_id, name)
values ('cccccccc-0000-0000-0000-000000000001',
        'aaaaaaaa-0000-0000-0000-000000000001', 'Pratos');

insert into products (id, restaurant_id, category_id, name, price_cents)
values ('dddddddd-0000-0000-0000-000000000001',
        'aaaaaaaa-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000001', 'Marmita', 2200);

do $$
declare v_cart uuid;
begin
  perform pg_temp.virar('22222222-2222-2222-2222-222222222222');

  delete from carts where user_id = '22222222-2222-2222-2222-222222222222';
  insert into carts (user_id, restaurant_id)
  values ('22222222-2222-2222-2222-222222222222',
          'aaaaaaaa-0000-0000-0000-000000000001')
  returning id into v_cart;
  insert into cart_items (cart_id, product_id, quantity)
  values (v_cart, 'dddddddd-0000-0000-0000-000000000001', 1);

  -- A marmitaria so abre as 11h. Este teste roda a qualquer hora do dia, entao
  -- o que se confere e a regra, nao o relogio: com o horario apagado passa,
  -- com o horario valendo fora da faixa recusa.
  delete from restaurant_hours
   where restaurant_id = 'aaaaaaaa-0000-0000-0000-000000000001';

  perform fechar_pedido(v_cart, 'pickup', 'cash', 'on_delivery');
  perform pg_temp.conferir(true,
    'sem horario cadastrado, o pedido passa a qualquer hora');
end;
$$;

do $$
declare v_cart uuid;
begin
  perform pg_temp.virar('22222222-2222-2222-2222-222222222222');

  -- Uma faixa de um minuto, num dia que nao e hoje: garantidamente fora.
  insert into restaurant_hours (restaurant_id, weekday, opens_at, closes_at)
  values ('aaaaaaaa-0000-0000-0000-000000000001',
          (extract(dow from (now() at time zone 'America/Sao_Paulo'))::int + 3) % 7,
          '03:00', '03:01');

  delete from carts where user_id = '22222222-2222-2222-2222-222222222222';
  insert into carts (user_id, restaurant_id)
  values ('22222222-2222-2222-2222-222222222222',
          'aaaaaaaa-0000-0000-0000-000000000001')
  returning id into v_cart;
  insert into cart_items (cart_id, product_id, quantity)
  values (v_cart, 'dddddddd-0000-0000-0000-000000000001', 1);

  perform pg_temp.deve_falhar(
    format($q$select fechar_pedido('%s', 'pickup', 'cash', 'on_delivery')$q$, v_cart),
    'pedido fora do horario de funcionamento');
end;
$$;

rollback;
