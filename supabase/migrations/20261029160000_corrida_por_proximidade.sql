-- =============================================================================
-- Tronvix Facil - a corrida chega ao autonomo pela distancia
--
-- Ate aqui o autonomo via toda corrida de quem aceita gente de fora, perto ou
-- longe, desde o primeiro segundo. Agora:
--
--   1. O entregador do proprio estabelecimento ve primeiro. So depois de
--      `platform_settings.platform_courier_delay_minutes` sem ninguem aceitar
--      a corrida abre para os autonomos.
--   2. Cada veiculo tem dois limites (courier_vehicle_rules):
--        max_trip_km     do estabelecimento ate o cliente
--        max_pickup_km   de onde o autonomo esta ate o estabelecimento
--      A pe: 2 km e 1 km. Bicicleta: 5 e 3. Moto e carro: 15 e 8.
--   3. A corrida fora do limite nem aparece: e melhor do que mostrar e recusar
--      o aceite.
--
-- Tudo isso mora numa funcao so, app.corrida_oferecida_a_mim, que a RLS de
-- deliveries e de orders usa para ver E para aceitar. A tela nao filtra nada.
--
-- Distancias em linha reta (app.haversine_km). Sem coordenada nao ha como
-- conferir: para o autonomo, corrida ou posicao desconhecida nao entra; para o
-- entregador do estabelecimento, entra - quem o escalou conhece a cidade.
-- =============================================================================

create table if not exists courier_vehicle_rules (
  vehicle_type text primary key
    check (vehicle_type in ('foot', 'bicycle', 'motorcycle', 'car')),
  max_trip_km numeric(6, 2) check (max_trip_km is null or max_trip_km > 0),
  max_pickup_km numeric(6, 2) check (max_pickup_km is null or max_pickup_km > 0)
);

comment on table courier_vehicle_rules is
  'Limites de distancia por veiculo. Nulo = sem limite. A plataforma ajusta pelo admin.';

insert into courier_vehicle_rules (vehicle_type, max_trip_km, max_pickup_km) values
  ('foot', 2, 1),
  ('bicycle', 5, 3),
  ('motorcycle', 15, 8),
  ('car', 15, 8)
on conflict (vehicle_type) do nothing;

alter table courier_vehicle_rules enable row level security;

drop policy if exists "todos leem os limites" on courier_vehicle_rules;
create policy "todos leem os limites"
  on courier_vehicle_rules for select
  to authenticated
  using (true);

drop policy if exists "plataforma ajusta os limites" on courier_vehicle_rules;
create policy "plataforma ajusta os limites"
  on courier_vehicle_rules for update
  to authenticated
  using (app.is_platform_admin())
  with check (app.is_platform_admin());

alter table platform_settings
  add column if not exists platform_courier_delay_minutes int not null default 3
    check (platform_courier_delay_minutes between 0 and 60);

comment on column platform_settings.platform_courier_delay_minutes is
  'Minutos que a corrida espera pelos entregadores do estabelecimento antes de abrir aos autonomos.';

-- -----------------------------------------------------------------------------
-- Desde quando a corrida procura entregador
-- -----------------------------------------------------------------------------

alter table deliveries
  add column if not exists searching_since timestamptz;

create or replace function app.carimbar_procura()
returns trigger
language plpgsql
as $$
begin
  if new.status = 'searching_courier'
     and (tg_op = 'INSERT' or old.status is distinct from 'searching_courier') then
    new.searching_since := now();
  end if;
  return new;
end;
$$;

drop trigger if exists deliveries_carimbar_procura on deliveries;
create trigger deliveries_carimbar_procura
  before insert or update of status on deliveries
  for each row execute function app.carimbar_procura();

-- As que ja estao na fila contam a partir de agora.
update deliveries set searching_since = now()
 where status = 'searching_courier' and searching_since is null;

-- -----------------------------------------------------------------------------
-- Quem ve a corrida
-- -----------------------------------------------------------------------------

create or replace function app.corrida_oferecida_a_mim(p_entrega uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
      from deliveries d
      join restaurants r on r.id = d.restaurant_id
      join couriers c on c.user_id = auth.uid()
                     and c.deleted_at is null
                     and c.status = 'approved'
      left join courier_vehicle_rules v on v.vehicle_type = c.vehicle_type
     where d.id = p_entrega
       and d.status = 'searching_courier'
       and (
         -- O entregador do estabelecimento: na hora. O limite da viagem vale
         -- quando a distancia e conhecida.
         (c.restaurant_id = d.restaurant_id
          and (v.max_trip_km is null or d.distance_km is null
               or d.distance_km <= v.max_trip_km))
         or
         -- O autonomo: depois da espera, perto do estabelecimento, e numa
         -- viagem que o veiculo dele aguenta.
         (c.restaurant_id is null
          and r.accepts_platform_couriers
          and now() >= coalesce(d.searching_since, d.created_at)
                       + make_interval(mins => coalesce(
                           (select platform_courier_delay_minutes from platform_settings limit 1), 3))
          and (v.max_trip_km is null
               or (d.distance_km is not null and d.distance_km <= v.max_trip_km))
          and (v.max_pickup_km is null
               or (c.current_latitude is not null
                   and c.location_updated_at > now() - interval '15 minutes'
                   and app.haversine_km(c.current_latitude, c.current_longitude,
                                        r.latitude, r.longitude) <= v.max_pickup_km)))
       )
  );
$$;

comment on function app.corrida_oferecida_a_mim(uuid) is
  'A corrida esta na fila e e para mim: sou do estabelecimento, ou sou autonomo, ja passou a espera e estou dentro dos limites do meu veiculo.';

-- O pedido por tras da corrida segue a mesma regra: quem nao ve a corrida nao
-- ve o endereco do cliente.
create or replace function app.is_order_offered_to_courier(p_order uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from deliveries d
     where d.order_id = p_order
       and app.corrida_oferecida_a_mim(d.id)
  );
$$;

drop policy if exists "entrega visivel a quem participa" on deliveries;
create policy "entrega visivel a quem participa"
  on deliveries for select
  to authenticated
  using (
    app.is_member(restaurant_id)
    or app.is_platform_admin()
    or courier_id = app.my_courier_id()
    or app.corrida_oferecida_a_mim(id)
    or app.is_order_customer(order_id)
  );

drop policy if exists "entregador e equipe atualizam a entrega" on deliveries;
create policy "entregador e equipe atualizam a entrega"
  on deliveries for update
  to authenticated
  using (
    app.is_member(restaurant_id)
    or app.is_platform_admin()
    or courier_id = app.my_courier_id()
    or app.corrida_oferecida_a_mim(id)
  )
  with check (
    app.is_member(restaurant_id)
    or app.is_platform_admin()
    or courier_id = app.my_courier_id()
    or (status = 'searching_courier' and app.courier_serves(restaurant_id))
  );
