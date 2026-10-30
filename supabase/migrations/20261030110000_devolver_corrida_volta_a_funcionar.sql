-- =============================================================================
-- Tronvix Facil - o entregador volta a conseguir devolver a corrida
--
-- 20261029160000 trocou a leitura de deliveries por
-- app.corrida_oferecida_a_mim(id), que procura a corrida PELO ID. Numa
-- atualizacao, o Postgres confere a linha nova contra essa politica - e a
-- funcao, procurando pelo id, enxerga a linha VELHA. Na devolucao ("nao vou
-- conseguir"), a linha velha ainda e "a caminho da loja", nao "procurando
-- entregador": a linha nova era recusada e o entregador ficava preso a uma
-- corrida que nao ia fazer.
--
-- A regra e a mesma; o que muda e de onde ela le. A politica passa a entregar
-- as colunas da propria linha (loja, distancia, desde quando procura) a
-- app.corrida_cabe_ao_entregador, que nao consulta deliveries.
-- =============================================================================

create or replace function app.corrida_cabe_ao_entregador(
  p_restaurante uuid,
  p_distancia numeric,
  p_procurando_desde timestamptz,
  p_entregador uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
      from restaurants r
      join couriers c on c.id = p_entregador
                     and c.deleted_at is null
                     and c.status = 'approved'
      left join courier_vehicle_rules v on v.vehicle_type = c.vehicle_type
     where r.id = p_restaurante
       and (
         (c.restaurant_id = p_restaurante
          and (v.max_trip_km is null or p_distancia is null or p_distancia <= v.max_trip_km))
         or
         (c.restaurant_id is null
          and r.accepts_platform_couriers
          and app.assinatura_em_dia(c.id)
          and now() >= p_procurando_desde
                       + make_interval(mins => coalesce(
                           (select platform_courier_delay_minutes from platform_settings limit 1), 3))
          and (v.max_trip_km is null
               or (p_distancia is not null and p_distancia <= v.max_trip_km))
          and (v.max_pickup_km is null
               or (c.current_latitude is not null
                   and c.location_updated_at > now() - interval '15 minutes'
                   and app.haversine_km(c.current_latitude, c.current_longitude,
                                        r.latitude, r.longitude) <= v.max_pickup_km)))
       )
  );
$$;

-- As duas de antes passam a delegar: uma regra so.
create or replace function app.corrida_oferecida_ao_entregador(p_entrega uuid, p_entregador uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from deliveries d
     where d.id = p_entrega
       and d.status = 'searching_courier'
       and app.corrida_cabe_ao_entregador(
             d.restaurant_id, d.distance_km, coalesce(d.searching_since, d.created_at), p_entregador)
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
    or (status = 'searching_courier'
        and app.corrida_cabe_ao_entregador(
              restaurant_id, distance_km, coalesce(searching_since, created_at), app.my_courier_id()))
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
    or (status = 'searching_courier'
        and app.corrida_cabe_ao_entregador(
              restaurant_id, distance_km, coalesce(searching_since, created_at), app.my_courier_id()))
  )
  with check (
    app.is_member(restaurant_id)
    or app.is_platform_admin()
    or courier_id = app.my_courier_id()
    or (status = 'searching_courier' and app.courier_serves(restaurant_id))
  );

-- -----------------------------------------------------------------------------
-- A devolucao vira uma funcao
-- -----------------------------------------------------------------------------
-- Mesmo com a politica lendo a linha, o AUTONOMO nao conseguiria devolver por
-- UPDATE direto: a corrida volta para a fila com a espera da loja zerada, ele
-- deixa de enxerga-la, e o Postgres recusa a linha nova que o proprio usuario
-- nao pode ver. A devolucao confere o que importa - a corrida e dele, e ainda
-- nao saiu da loja - e devolve. O gatilho app.guard_delivery_status limpa o
-- entregador e carimba a volta para a fila.
create or replace function public.devolver_corrida(p_entrega uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_entregador uuid := app.my_courier_id();
begin
  if v_entregador is null then
    raise exception 'So entregador devolve corrida.' using errcode = 'insufficient_privilege';
  end if;

  update deliveries
     set status = 'searching_courier'
   where id = p_entrega
     and courier_id = v_entregador
     and status in ('assigned', 'heading_to_restaurant');

  if not found then
    raise exception 'Essa corrida nao esta com voce, ou ja saiu da loja.' using errcode = 'no_data_found';
  end if;

  update couriers set availability = 'online' where id = v_entregador;
end;
$$;

revoke all on function public.devolver_corrida(uuid) from public;
grant execute on function public.devolver_corrida(uuid) to authenticated;
