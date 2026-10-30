-- =============================================================================
-- Tronvix Facil - quem paga o entregador e quanto, e o aviso de corrida nova
--
-- 1. O VALOR DA CORRIDA. Ate aqui o entregador recebia exatamente o frete que
--    o cliente pagou. Com frete gratis, a corrida valia R$ 0,00 - ninguem
--    aceitava, e quem aceitava trabalhava de graca. Agora:
--
--      restaurants.courier_pay_base_cents     quanto a loja paga por corrida
--                                             (nulo = o frete cobrado do cliente)
--      restaurants.courier_pay_per_km_cents   adicional por km, se a loja quiser
--      platform_settings.min_courier_fee_cents  o piso: nenhuma corrida paga
--                                             menos, nem com frete gratis
--
--    O dono que paga mais leva os melhores entregadores primeiro - e isso e
--    escolha dele. O piso e o que impede a concorrencia de puxar para baixo.
--    A loja pode AUMENTAR o valor de uma corrida parada (aumentar_valor_da_
--    corrida); diminuir, nao.
--
-- 2. O AVISO. A corrida nova chega ao celular de quem pode aceita-la - os
--    entregadores da loja na hora, e os autonomos quando a espera da loja
--    termina (um relogio do banco, a cada minuto). Quem pode ver e a mesma
--    regra da fila: app.corrida_oferecida_ao_entregador.
-- =============================================================================

alter table restaurants
  add column if not exists courier_pay_base_cents bigint
    check (courier_pay_base_cents is null or courier_pay_base_cents between 0 and 100000),
  add column if not exists courier_pay_per_km_cents bigint not null default 0
    check (courier_pay_per_km_cents between 0 and 10000);

comment on column restaurants.courier_pay_base_cents is
  'Quanto a loja paga ao entregador por corrida. Nulo = o frete cobrado do cliente. O piso da plataforma vale sempre.';

alter table platform_settings
  add column if not exists min_courier_fee_cents bigint not null default 600
    check (min_courier_fee_cents between 0 and 100000);

alter table deliveries
  add column if not exists autonomos_avisados_em timestamptz;

-- -----------------------------------------------------------------------------
-- O valor, quando a corrida nasce
-- -----------------------------------------------------------------------------

create or replace function app.piso_da_corrida()
returns bigint
language sql
stable
as $$
  select coalesce((select min_courier_fee_cents from platform_settings limit 1), 600);
$$;

-- Depois de deliveries_fill_distance (ordem alfabetica): a distancia ja esta
-- calculada quando o valor por km e aplicado.
create or replace function app.valor_da_corrida()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_loja restaurants;
begin
  select * into v_loja from restaurants where id = new.restaurant_id;

  new.courier_fee_cents := greatest(
    app.piso_da_corrida(),
    coalesce(v_loja.courier_pay_base_cents, new.courier_fee_cents, 0)
      + round(v_loja.courier_pay_per_km_cents * coalesce(new.distance_km, 0))::bigint
  );
  return new;
end;
$$;

drop trigger if exists deliveries_valor_da_corrida on deliveries;
create trigger deliveries_valor_da_corrida
  before insert on deliveries
  for each row execute function app.valor_da_corrida();

-- Ninguem baixa o valor de uma corrida ja oferecida: o entregador decidiu ir
-- olhando aquele numero. Subir pode (e o aumento da loja).
create or replace function app.guardar_valor_da_corrida()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.courier_fee_cents < old.courier_fee_cents
     and not (app.is_service_role() or app.is_platform_admin()) then
    raise exception 'O valor da corrida so pode aumentar.' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

drop trigger if exists deliveries_guardar_valor on deliveries;
create trigger deliveries_guardar_valor
  before update of courier_fee_cents on deliveries
  for each row execute function app.guardar_valor_da_corrida();

-- -----------------------------------------------------------------------------
-- Quem pode ver a corrida - agora por entregador, nao so por "mim"
-- -----------------------------------------------------------------------------

create or replace function app.corrida_oferecida_ao_entregador(p_entrega uuid, p_entregador uuid)
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
      join couriers c on c.id = p_entregador
                     and c.deleted_at is null
                     and c.status = 'approved'
      left join courier_vehicle_rules v on v.vehicle_type = c.vehicle_type
     where d.id = p_entrega
       and d.status = 'searching_courier'
       and (
         (c.restaurant_id = d.restaurant_id
          and (v.max_trip_km is null or d.distance_km is null
               or d.distance_km <= v.max_trip_km))
         or
         (c.restaurant_id is null
          and r.accepts_platform_couriers
          and app.assinatura_em_dia(c.id)
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

create or replace function app.corrida_oferecida_a_mim(p_entrega uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select app.corrida_oferecida_ao_entregador(p_entrega, app.my_courier_id());
$$;

-- Para a funcao de aviso: quem esta disponivel e pode aceitar esta corrida
-- agora. So a chave de servico chama.
create or replace function public.entregadores_para_avisar(p_entrega uuid, p_so_autonomos boolean default false)
returns table (user_id uuid)
language sql
stable
security definer
set search_path = public
as $$
  select c.user_id
    from couriers c
   where c.availability = 'online'
     and (not p_so_autonomos or c.restaurant_id is null)
     and app.corrida_oferecida_ao_entregador(p_entrega, c.id);
$$;

revoke all on function public.entregadores_para_avisar(uuid, boolean) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- A loja aumenta o valor de uma corrida parada
-- -----------------------------------------------------------------------------

create or replace function public.aumentar_valor_da_corrida(p_entrega uuid, p_valor_centavos bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_entrega deliveries;
begin
  select * into v_entrega from deliveries where id = p_entrega for update;

  if v_entrega.id is null or not (app.can_manage(v_entrega.restaurant_id) or app.is_platform_admin()) then
    raise exception 'Corrida nao encontrada.' using errcode = 'no_data_found';
  end if;

  if v_entrega.status not in ('pending', 'searching_courier') then
    raise exception 'Essa corrida ja tem entregador.' using errcode = 'check_violation';
  end if;

  if p_valor_centavos is null or p_valor_centavos <= v_entrega.courier_fee_cents
     or p_valor_centavos > 100000 then
    raise exception 'O novo valor precisa ser maior que o atual.' using errcode = 'check_violation';
  end if;

  update deliveries set courier_fee_cents = p_valor_centavos where id = p_entrega;

  -- Corrida ja na fila: quem pode aceita-la fica sabendo do valor novo.
  if v_entrega.status = 'searching_courier' then
    perform app.chamar_aviso(jsonb_build_object(
      'tipo', 'corrida', 'entrega', p_entrega, 'motivo', 'aumento'));
  end if;
end;
$$;

revoke all on function public.aumentar_valor_da_corrida(uuid, bigint) from public;
grant execute on function public.aumentar_valor_da_corrida(uuid, bigint) to authenticated;

-- -----------------------------------------------------------------------------
-- O aviso
-- -----------------------------------------------------------------------------

-- A mesma porta de app.avisar_pedido: a funcao de aviso, pela pg_net, com a
-- chave do banco. Sem configuracao ou sem pg_net, nao faz nada.
create or replace function app.chamar_aviso(p_corpo jsonb)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_url text := (select valor from app.configuracao where chave = 'url_da_funcao_de_aviso');
  v_chave text := (select valor from app.configuracao where chave = 'chave_de_servico');
begin
  if v_url is null or v_url = '' or to_regproc('net.http_post') is null then
    return;
  end if;

  execute format(
    'select net.http_post(url := %L, headers := %L::jsonb, body := %L::jsonb)',
    v_url,
    jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || coalesce(v_chave, '')
    )::text,
    p_corpo::text
  );
end;
$$;

revoke all on function app.chamar_aviso(jsonb) from public;

-- A corrida entra na fila: avisa quem pode aceita-la agora (a gente da loja;
-- os autonomos, so se a espera for zero).
create or replace function app.avisar_corrida_nova()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'searching_courier'
     and (tg_op = 'INSERT' or old.status is distinct from 'searching_courier') then
    perform app.chamar_aviso(jsonb_build_object('tipo', 'corrida', 'entrega', new.id));
  end if;
  return null;
end;
$$;

drop trigger if exists deliveries_avisar_corrida on deliveries;
create trigger deliveries_avisar_corrida
  after insert or update of status on deliveries
  for each row execute function app.avisar_corrida_nova();

-- A espera da loja acabou e ninguem pegou: avisa os autonomos, uma vez.
create or replace function app.avisar_autonomos()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_entrega record;
  v_total int := 0;
  v_espera int := coalesce(
    (select platform_courier_delay_minutes from platform_settings limit 1), 3);
begin
  for v_entrega in
    select d.id
      from deliveries d
      join restaurants r on r.id = d.restaurant_id
     where d.status = 'searching_courier'
       and d.autonomos_avisados_em is null
       and r.accepts_platform_couriers
       and now() >= coalesce(d.searching_since, d.created_at) + make_interval(mins => v_espera)
     for update of d skip locked
  loop
    update deliveries set autonomos_avisados_em = now() where id = v_entrega.id;
    perform app.chamar_aviso(jsonb_build_object(
      'tipo', 'corrida', 'entrega', v_entrega.id, 'so_autonomos', true));
    v_total := v_total + 1;
  end loop;
  return v_total;
end;
$$;

-- O relogio. pg_cron existe no Supabase, nao num Postgres comum: sem ele, a
-- migracao segue e os autonomos so ficam sem o aviso (a fila continua certa).
do $$
begin
  if not exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    raise notice 'pg_cron indisponivel: autonomos sem aviso de corrida neste banco.';
    return;
  end if;

  create extension if not exists pg_cron;

  if exists (select 1 from cron.job where jobname = 'avisar-autonomos') then
    perform cron.unschedule('avisar-autonomos');
  end if;
  perform cron.schedule('avisar-autonomos', '* * * * *', 'select app.avisar_autonomos()');
end;
$$;
