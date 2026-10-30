-- =============================================================================
-- Tronvix Facil - quem paga o entregador e quanto, e quem recebe o aviso
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
grant select, update on all tables in schema public to authenticated;

insert into platform_settings (id) values (true) on conflict (id) do nothing;

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'dono@teste.test'),
  ('22222222-2222-2222-2222-222222222222', 'atendente@teste.test'),
  ('33333333-3333-3333-3333-333333333333', 'motoboy.da.loja@teste.test'),
  ('44444444-4444-4444-4444-444444444444', 'autonomo@teste.test'),
  ('55555555-5555-5555-5555-555555555555', 'motoboy.offline@teste.test');

insert into restaurants (id, slug, name, status, delivery_fee_cents, accepts_platform_couriers,
                         latitude, longitude)
values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'gratis', 'Frete Gratis', 'approved', 0, true,
   -20.8489, -41.1129),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'generosa', 'Generosa', 'approved', 500, false,
   -20.8489, -41.1129);

update restaurants set courier_pay_base_cents = 900, courier_pay_per_km_cents = 150
 where id = 'aaaaaaaa-0000-0000-0000-000000000002';

insert into restaurant_members (restaurant_id, user_id, role) values
  ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'owner'),
  ('aaaaaaaa-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 'staff');

insert into couriers (id, user_id, restaurant_id, status, availability, vehicle_type,
                      current_latitude, current_longitude, location_updated_at) values
  ('77777777-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333',
   'aaaaaaaa-0000-0000-0000-000000000001', 'approved', 'online', 'motorcycle', null, null, null),
  ('77777777-0000-0000-0000-000000000002', '44444444-4444-4444-4444-444444444444',
   null, 'approved', 'online', 'motorcycle', -20.8500, -41.1129, now()),
  ('77777777-0000-0000-0000-000000000003', '55555555-5555-5555-5555-555555555555',
   'aaaaaaaa-0000-0000-0000-000000000001', 'approved', 'offline', 'motorcycle', null, null, null);

insert into orders (id, restaurant_id, number, customer_name, status, fulfillment,
                    address_summary, subtotal_cents, delivery_fee_cents, total_cents)
values
  ('eeeeeeee-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 1,
   'Gratis', 'ready', 'delivery', 'Rua A, 1', 3000, 0, 3000),
  ('eeeeeeee-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000002', 1,
   'Generosa', 'ready', 'delivery', 'Rua B, 2', 3000, 500, 3500);

-- O fechamento grava o frete do cliente como valor da corrida; o gatilho
-- decide o valor de verdade.
insert into deliveries (id, order_id, restaurant_id, status, courier_fee_cents, distance_km) values
  ('dddddddd-0000-0000-0000-000000000001', 'eeeeeeee-0000-0000-0000-000000000001',
   'aaaaaaaa-0000-0000-0000-000000000001', 'pending', 0, 2),
  ('dddddddd-0000-0000-0000-000000000002', 'eeeeeeee-0000-0000-0000-000000000002',
   'aaaaaaaa-0000-0000-0000-000000000002', 'pending', 500, 4);

-- -----------------------------------------------------------------------------
-- O valor
-- -----------------------------------------------------------------------------
do $$
begin
  perform pg_temp.conferir(
    (select courier_fee_cents = 600 from deliveries where id = 'dddddddd-0000-0000-0000-000000000001'),
    'frete gratis nao zera a corrida: vale o piso de R$ 6,00');
  perform pg_temp.conferir(
    (select courier_fee_cents = 1500 from deliveries where id = 'dddddddd-0000-0000-0000-000000000002'),
    'a loja que paga mais: R$ 9,00 fixos + R$ 1,50 por km em 4 km = R$ 15,00');

  -- O atendente nao mexe em dinheiro; ninguem baixa o valor.
  perform set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);
  perform pg_temp.deve_falhar(
    $q$select aumentar_valor_da_corrida('dddddddd-0000-0000-0000-000000000001', 900)$q$,
    'o atendente aumentando o valor da corrida');

  perform set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
  perform pg_temp.deve_falhar(
    $q$select aumentar_valor_da_corrida('dddddddd-0000-0000-0000-000000000001', 500)$q$,
    'aumentar para um valor menor que o atual');
  perform aumentar_valor_da_corrida('dddddddd-0000-0000-0000-000000000001', 900);
  perform pg_temp.conferir(
    (select courier_fee_cents = 900 from deliveries where id = 'dddddddd-0000-0000-0000-000000000001'),
    'o dono aumenta o valor da corrida parada');

  set local role authenticated;
  perform pg_temp.deve_falhar(
    $q$update deliveries set courier_fee_cents = 100
        where id = 'dddddddd-0000-0000-0000-000000000001'$q$,
    'baixar o valor da corrida direto na tabela');
  reset role;
end;
$$;

-- -----------------------------------------------------------------------------
-- Quem recebe o aviso
-- -----------------------------------------------------------------------------
update deliveries set status = 'searching_courier' where id = 'dddddddd-0000-0000-0000-000000000001';

do $$
begin
  perform set_config('request.jwt.claim.sub', '', true);
  perform pg_temp.conferir(
    (select array_agg(user_id) = array['33333333-3333-3333-3333-333333333333'::uuid]
       from entregadores_para_avisar('dddddddd-0000-0000-0000-000000000001')),
    'na hora, so o entregador da loja que esta online (o offline nao)');

  perform pg_temp.conferir(app.avisar_autonomos() = 0,
    'antes da espera, o relogio nao avisa autonomo nenhum');

  update deliveries set searching_since = now() - interval '10 minutes'
   where id = 'dddddddd-0000-0000-0000-000000000001';

  perform pg_temp.conferir(
    (select array_agg(user_id) = array['44444444-4444-4444-4444-444444444444'::uuid]
       from entregadores_para_avisar('dddddddd-0000-0000-0000-000000000001', true)),
    'depois da espera, o autonomo perto entra na lista dos autonomos');

  perform pg_temp.conferir(app.avisar_autonomos() = 1, 'o relogio avisa a corrida que passou da espera');
  perform pg_temp.conferir(app.avisar_autonomos() = 0, 'e nao avisa a mesma corrida duas vezes');
end;
$$;

rollback;
