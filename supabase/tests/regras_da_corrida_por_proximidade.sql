-- =============================================================================
-- Tronvix Facil - a corrida chega ao autonomo pela distancia
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

-- Quais corridas (pelo cliente do pedido) a pessoa enxerga.
create or replace function pg_temp.ve(p_usuario uuid)
returns text language plpgsql as $$
declare v text;
begin
  perform set_config('request.jwt.claim.sub', p_usuario::text, true);
  set local role authenticated;
  select coalesce(string_agg(o.customer_name, ',' order by o.customer_name), '')
    into v
    from deliveries d join orders o on o.id = d.order_id;
  reset role;
  return v;
end;
$$;

grant usage on schema public to authenticated;
grant select on all tables in schema public to authenticated;
grant update on deliveries, couriers to authenticated;

-- -----------------------------------------------------------------------------
-- Cenario: uma loja no centro de Cachoeiro que aceita autonomos
-- -----------------------------------------------------------------------------
insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'dono@teste.test'),
  ('21111111-1111-1111-1111-111111111111', 'proprio.ape@teste.test'),
  ('31111111-1111-1111-1111-111111111111', 'ape.perto@teste.test'),
  ('41111111-1111-1111-1111-111111111111', 'ape.longe@teste.test'),
  ('51111111-1111-1111-1111-111111111111', 'moto.5km@teste.test'),
  ('61111111-1111-1111-1111-111111111111', 'moto.sem.gps@teste.test');

insert into restaurants (id, slug, name, status, delivery_fee_cents,
                         accepts_platform_couriers, latitude, longitude)
values ('aaaaaaaa-0000-0000-0000-000000000001', 'centro', 'Centro', 'approved', 700,
        true, -20.8489, -41.1129);

insert into restaurant_members (restaurant_id, user_id, role)
values ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'owner');

-- 0,01 grau de latitude e pouco mais de 1 km.
insert into couriers (user_id, restaurant_id, status, vehicle_type,
                      current_latitude, current_longitude, location_updated_at) values
  ('21111111-1111-1111-1111-111111111111', 'aaaaaaaa-0000-0000-0000-000000000001',
   'approved', 'foot', null, null, null),
  ('31111111-1111-1111-1111-111111111111', null, 'approved', 'foot',
   -20.8530, -41.1129, now()),
  ('41111111-1111-1111-1111-111111111111', null, 'approved', 'foot',
   -20.8760, -41.1129, now()),
  ('51111111-1111-1111-1111-111111111111', null, 'approved', 'motorcycle',
   -20.8939, -41.1129, now()),
  ('61111111-1111-1111-1111-111111111111', null, 'approved', 'motorcycle',
   null, null, null);

-- Tres corridas: curta, longa, e sem endereco marcado no mapa.
insert into orders (id, restaurant_id, number, customer_name, status, fulfillment,
                    address_summary, subtotal_cents, delivery_fee_cents, total_cents)
values
  ('eeeeeeee-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 1,
   'Curta', 'ready', 'delivery', 'Rua A, 1', 2000, 700, 2700),
  ('eeeeeeee-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000001', 2,
   'Longa', 'ready', 'delivery', 'Rua B, 2', 2000, 700, 2700),
  ('eeeeeeee-0000-0000-0000-000000000003', 'aaaaaaaa-0000-0000-0000-000000000001', 3,
   'SemMapa', 'ready', 'delivery', 'Rua C, 3', 2000, 700, 2700);

insert into deliveries (order_id, restaurant_id, status, distance_km) values
  ('eeeeeeee-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'searching_courier', 1.5),
  ('eeeeeeee-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000001', 'searching_courier', 4),
  ('eeeeeeee-0000-0000-0000-000000000003', 'aaaaaaaa-0000-0000-0000-000000000001', 'searching_courier', null);

-- -----------------------------------------------------------------------------
-- Antes da espera: so a gente da loja
-- -----------------------------------------------------------------------------
do $$
begin
  perform pg_temp.conferir(
    (select bool_and(searching_since is not null) from deliveries),
    'a corrida guarda desde quando procura entregador');

  perform pg_temp.conferir(
    pg_temp.ve('21111111-1111-1111-1111-111111111111') = 'Curta,SemMapa',
    'o entregador a pe da loja ve na hora a corrida curta e a sem mapa, nao a de 4 km');
  perform pg_temp.conferir(
    pg_temp.ve('31111111-1111-1111-1111-111111111111') = '',
    'o autonomo nao ve nada antes de a loja ter a sua vez');
end;
$$;

-- -----------------------------------------------------------------------------
-- Depois da espera: cada um no seu raio
-- -----------------------------------------------------------------------------
update deliveries set searching_since = now() - interval '10 minutes';

do $$
begin
  perform pg_temp.conferir(
    pg_temp.ve('31111111-1111-1111-1111-111111111111') = 'Curta',
    'a pe e perto da loja: ve so a corrida de ate 2 km, e nao a sem mapa');
  perform pg_temp.conferir(
    pg_temp.ve('41111111-1111-1111-1111-111111111111') = '',
    'a pe a 3 km da loja: longe demais para ir buscar');
  perform pg_temp.conferir(
    pg_temp.ve('51111111-1111-1111-1111-111111111111') = 'Curta,Longa',
    'de moto a 5 km: ve as duas corridas com distancia conhecida');
  perform pg_temp.conferir(
    pg_temp.ve('61111111-1111-1111-1111-111111111111') = '',
    'sem posicao no mapa, o autonomo nao recebe corrida');

  -- Posicao velha vale tanto quanto nenhuma.
  update couriers set location_updated_at = now() - interval '1 hour'
   where user_id = '31111111-1111-1111-1111-111111111111';
  perform pg_temp.conferir(
    pg_temp.ve('31111111-1111-1111-1111-111111111111') = '',
    'posicao de uma hora atras nao serve');
  update couriers set location_updated_at = now()
   where user_id = '31111111-1111-1111-1111-111111111111';
end;
$$;

-- -----------------------------------------------------------------------------
-- O limite e da plataforma, e o aceite obedece a mesma regra
-- -----------------------------------------------------------------------------
do $$
declare n int;
begin
  update courier_vehicle_rules set max_trip_km = 5 where vehicle_type = 'foot';
  perform pg_temp.conferir(
    pg_temp.ve('31111111-1111-1111-1111-111111111111') = 'Curta,Longa',
    'aumentar o limite do a pe pelo admin abre a corrida de 4 km');
  update courier_vehicle_rules set max_trip_km = 2 where vehicle_type = 'foot';

  -- Aceitar a corrida que nao ve: o UPDATE nao acha a linha.
  perform set_config('request.jwt.claim.sub', '41111111-1111-1111-1111-111111111111', true);
  set local role authenticated;
  update deliveries
     set courier_id = (select id from couriers where user_id = '41111111-1111-1111-1111-111111111111'),
         status = 'assigned'
   where order_id = 'eeeeeeee-0000-0000-0000-000000000001'
     and status = 'searching_courier';
  get diagnostics n = row_count;
  reset role;
  perform pg_temp.conferir(n = 0, 'quem esta fora do raio nao consegue aceitar');

  perform set_config('request.jwt.claim.sub', '31111111-1111-1111-1111-111111111111', true);
  set local role authenticated;
  update deliveries
     set courier_id = (select id from couriers where user_id = '31111111-1111-1111-1111-111111111111'),
         status = 'assigned'
   where order_id = 'eeeeeeee-0000-0000-0000-000000000001'
     and status = 'searching_courier';
  get diagnostics n = row_count;
  reset role;
  perform pg_temp.conferir(n = 1, 'quem esta no raio aceita');

  -- E consegue devolver: "nao vou conseguir" volta a corrida para a fila
  -- (devolver_corrida, 20261030110000 - por UPDATE direto o autonomo era
  -- recusado).
  update deliveries set status = 'heading_to_restaurant'
   where order_id = 'eeeeeeee-0000-0000-0000-000000000001';
  perform set_config('request.jwt.claim.sub', '31111111-1111-1111-1111-111111111111', true);
  set local role authenticated;
  perform devolver_corrida((select id from deliveries
                             where order_id = 'eeeeeeee-0000-0000-0000-000000000001'));
  reset role;
  perform pg_temp.conferir(
    (select status = 'searching_courier' and courier_id is null from deliveries
                where order_id = 'eeeeeeee-0000-0000-0000-000000000001'),
    'quem aceitou consegue devolver a corrida, e ela volta para a fila');
end;
$$;

rollback;
