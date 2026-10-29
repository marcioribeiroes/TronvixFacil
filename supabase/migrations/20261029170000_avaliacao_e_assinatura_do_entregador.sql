-- =============================================================================
-- Tronvix Facil - a nota do cliente e a assinatura do entregador autonomo
--
-- Duas pecas da fase 4 do autonomo:
--
-- 1. A AVALIACAO. A tabela reviews existe desde a fundacao, com nota da loja
--    e do entregador, e o recalculo da media por gatilho. Faltava o caminho:
--    o aplicativo gravava numa coluna que nao existe (`rating`) e nenhuma tela
--    chamava. Agora `avaliar_pedido` grava pelo banco - quem avalia, qual loja
--    e qual entregador saem do pedido, e nao do que o cliente manda.
--
--    O autonomo com media abaixo de 3,5 depois de 10 avaliacoes sai da fila
--    (suspenso, com o motivo). O do estabelecimento nao: quem decide sobre ele
--    e o estabelecimento.
--
-- 2. A ASSINATURA. R$ 10 por mes para o autonomo receber corridas, desligada
--    ate a plataforma escolher a data de inicio. Depois dela, cada autonomo tem
--    30 dias gratis contados da aprovacao (ou do inicio da cobranca, o que vier
--    depois). O pagamento e Pix estatico para a chave da plataforma; quem
--    confirma e o admin, vendo o dinheiro entrar - como o balcao faz com o Pix
--    do pedido.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- A avaliacao
-- -----------------------------------------------------------------------------

create or replace function public.avaliar_pedido(
  p_pedido uuid,
  p_nota_da_loja int,
  p_nota_do_entregador int default null,
  p_comentario text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pedido orders;
  v_entregador uuid;
begin
  select * into v_pedido from orders where id = p_pedido;

  if v_pedido.id is null or v_pedido.customer_id is distinct from auth.uid() then
    raise exception 'Pedido nao encontrado.' using errcode = 'no_data_found';
  end if;

  if v_pedido.status <> 'delivered' then
    raise exception 'So da para avaliar depois de receber o pedido.'
      using errcode = 'check_violation';
  end if;

  if p_nota_da_loja is null or p_nota_da_loja not between 1 and 5 then
    raise exception 'De uma nota de 1 a 5 para o estabelecimento.' using errcode = 'check_violation';
  end if;

  select courier_id into v_entregador
    from deliveries where order_id = p_pedido and status = 'delivered';

  -- Sem entregador (retirada, mesa) a nota dele nao tem a quem ir.
  if v_entregador is null then
    p_nota_do_entregador := null;
  elsif p_nota_do_entregador is not null and p_nota_do_entregador not between 1 and 5 then
    raise exception 'De uma nota de 1 a 5 para o entregador.' using errcode = 'check_violation';
  end if;

  insert into reviews (order_id, restaurant_id, customer_id, courier_id,
                       restaurant_rating, courier_rating, comment)
  values (p_pedido, v_pedido.restaurant_id, auth.uid(), v_entregador,
          p_nota_da_loja, p_nota_do_entregador,
          nullif(left(btrim(coalesce(p_comentario, '')), 1000), ''))
  on conflict (order_id) do update
    set restaurant_rating = excluded.restaurant_rating,
        courier_rating = excluded.courier_rating,
        comment = excluded.comment;
end;
$$;

revoke all on function public.avaliar_pedido(uuid, int, int, text) from public;
grant execute on function public.avaliar_pedido(uuid, int, int, text) to authenticated;

create or replace function app.suspender_autonomo_mal_avaliado()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_entregador uuid := coalesce(new.courier_id, old.courier_id);
begin
  if v_entregador is null then
    return null;
  end if;

  update couriers
     set status = 'suspended',
         availability = 'offline',
         review_note = 'Sua nota média ficou abaixo de 3,5. Fale com o suporte para voltar.'
   where id = v_entregador
     and restaurant_id is null
     and status = 'approved'
     and rating_count >= 10
     and rating_avg < 3.5;

  return null;
end;
$$;

-- Depois de reviews_refresh_ratings (os gatilhos rodam em ordem alfabetica):
-- a media ja esta recalculada quando este olha.
drop trigger if exists reviews_suspender_autonomo on reviews;
create trigger reviews_suspender_autonomo
  after insert or update on reviews
  for each row execute function app.suspender_autonomo_mal_avaliado();

-- -----------------------------------------------------------------------------
-- O Pix copia-e-cola, no banco
-- -----------------------------------------------------------------------------

-- Espelho de src/lib/pix.ts (gerarBrCode). Mora aqui para o site e o
-- aplicativo mostrarem o MESMO codigo sem duas implementacoes de CRC.
create or replace function app.pix_campo(p_id text, p_valor text)
returns text
language sql
immutable
as $$
  select p_id || lpad(length(p_valor)::text, 2, '0') || p_valor;
$$;

create or replace function app.pix_crc16(p_texto text)
returns text
language plpgsql
immutable
as $$
declare
  crc int := 65535;
  i int;
  b int;
begin
  for i in 1..length(p_texto) loop
    crc := crc # (ascii(substr(p_texto, i, 1)) << 8);
    for b in 1..8 loop
      if (crc & 32768) <> 0 then
        crc := ((crc << 1) # 4129) & 65535;
      else
        crc := (crc << 1) & 65535;
      end if;
    end loop;
  end loop;
  return upper(lpad(to_hex(crc), 4, '0'));
end;
$$;

create or replace function app.pix_limpar(p_texto text, p_limite int)
returns text
language sql
immutable
as $$
  select upper(left(btrim(regexp_replace(
    unaccent('unaccent', coalesce(p_texto, '')), '[^A-Za-z0-9 .\-]', '', 'g')), p_limite));
$$;

create or replace function app.pix_br_code(
  p_chave text,
  p_nome text,
  p_cidade text,
  p_centavos bigint,
  p_identificador text
)
returns text
language plpgsql
stable
as $$
declare
  v_txid text := coalesce(nullif(left(regexp_replace(coalesce(p_identificador, ''),
                   '[^A-Za-z0-9]', '', 'g'), 25), ''), '***');
  v_sem_crc text;
begin
  v_sem_crc :=
    app.pix_campo('00', '01') ||
    app.pix_campo('26', app.pix_campo('00', 'br.gov.bcb.pix') || app.pix_campo('01', p_chave)) ||
    app.pix_campo('52', '0000') ||
    app.pix_campo('53', '986') ||
    app.pix_campo('54', to_char(p_centavos / 100.0, 'FM999999990.00')) ||
    app.pix_campo('58', 'BR') ||
    app.pix_campo('59', app.pix_limpar(p_nome, 25)) ||
    app.pix_campo('60', app.pix_limpar(p_cidade, 15)) ||
    app.pix_campo('62', app.pix_campo('05', v_txid)) ||
    '6304';
  return v_sem_crc || app.pix_crc16(v_sem_crc);
end;
$$;

-- -----------------------------------------------------------------------------
-- A assinatura
-- -----------------------------------------------------------------------------

alter table platform_settings
  add column if not exists courier_subscription_price_cents bigint not null default 1000
    check (courier_subscription_price_cents between 0 and 100000),
  add column if not exists courier_subscription_starts_on date,
  add column if not exists platform_pix_key text,
  add column if not exists platform_pix_holder text,
  add column if not exists platform_pix_city text;

comment on column platform_settings.courier_subscription_starts_on is
  'Dia em que a assinatura do autonomo passa a ser cobrada. Nulo = cobranca desligada.';

alter table couriers
  add column if not exists paid_until date;

comment on column couriers.paid_until is
  'Ate quando a assinatura do autonomo esta paga. Nulo = ainda no mes gratis.';

create table if not exists courier_payments (
  id uuid primary key default gen_random_uuid(),
  courier_id uuid not null references couriers (id) on delete cascade,
  amount_cents bigint not null check (amount_cents > 0),
  reference text not null unique,
  status text not null default 'pending' check (status in ('pending', 'confirmed', 'cancelled')),
  created_at timestamptz not null default now(),
  confirmed_at timestamptz,
  confirmed_by uuid references profiles (id) on delete set null
);

create index if not exists courier_payments_courier_idx
  on courier_payments (courier_id, created_at desc);
create unique index if not exists courier_payments_one_pending
  on courier_payments (courier_id) where status = 'pending';

alter table courier_payments enable row level security;

drop policy if exists "entregador e plataforma veem os pagamentos" on courier_payments;
create policy "entregador e plataforma veem os pagamentos"
  on courier_payments for select
  to authenticated
  using (courier_id = app.my_courier_id() or app.is_platform_admin());

-- O vencimento: pago ate, ou o fim do mes gratis.
create or replace function app.vencimento_da_assinatura(p_entregador uuid)
returns date
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    c.paid_until,
    greatest(coalesce(c.approved_at::date, c.created_at::date), s.courier_subscription_starts_on) + 30
  )
    from couriers c
    cross join (select courier_subscription_starts_on from platform_settings limit 1) s
   where c.id = p_entregador;
$$;

create or replace function app.assinatura_em_dia(p_entregador uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case
    when s.courier_subscription_starts_on is null then true
    when current_date < s.courier_subscription_starts_on then true
    when s.courier_subscription_price_cents = 0 then true
    else current_date <= app.vencimento_da_assinatura(p_entregador)
  end
  from (select courier_subscription_starts_on, courier_subscription_price_cents
          from platform_settings limit 1) s;
$$;

-- O que a tela do entregador mostra.
create or replace function public.minha_assinatura()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_entregador couriers;
  v_config platform_settings;
  v_pendente courier_payments;
begin
  select * into v_entregador from couriers where id = app.my_courier_id();
  if v_entregador.id is null or v_entregador.restaurant_id is not null then
    return jsonb_build_object('aplica', false);
  end if;

  select * into v_config from platform_settings limit 1;
  select * into v_pendente from courier_payments
   where courier_id = v_entregador.id and status = 'pending';

  return jsonb_build_object(
    'aplica', true,
    'cobrando', v_config.courier_subscription_starts_on is not null
                and v_config.courier_subscription_price_cents > 0,
    'inicio', v_config.courier_subscription_starts_on,
    'vence', app.vencimento_da_assinatura(v_entregador.id),
    'em_dia', app.assinatura_em_dia(v_entregador.id),
    'preco_centavos', v_config.courier_subscription_price_cents,
    'pendente', case when v_pendente.id is null then null else jsonb_build_object(
      'id', v_pendente.id,
      'valor_centavos', v_pendente.amount_cents,
      'referencia', v_pendente.reference,
      'copia_e_cola', app.pix_br_code(v_config.platform_pix_key, v_config.platform_pix_holder,
                                      v_config.platform_pix_city, v_pendente.amount_cents,
                                      v_pendente.reference)
    ) end
  );
end;
$$;

grant execute on function public.minha_assinatura() to authenticated;

-- O entregador pede o Pix de um mes. Se ja ha um pendente, e o mesmo: dois
-- codigos para o mesmo mes so confundiriam quem confere o extrato.
create or replace function public.gerar_pagamento_da_assinatura()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_entregador couriers;
  v_config platform_settings;
begin
  select * into v_entregador from couriers where id = app.my_courier_id();
  if v_entregador.id is null or v_entregador.restaurant_id is not null then
    raise exception 'A assinatura e so do entregador autonomo.' using errcode = 'insufficient_privilege';
  end if;

  select * into v_config from platform_settings limit 1;
  if v_config.platform_pix_key is null or v_config.courier_subscription_price_cents = 0 then
    raise exception 'A plataforma ainda nao configurou o recebimento.' using errcode = 'check_violation';
  end if;

  if exists (select 1 from courier_payments
              where courier_id = v_entregador.id and status = 'pending') then
    return;
  end if;

  insert into courier_payments (courier_id, amount_cents, reference)
  values (v_entregador.id, v_config.courier_subscription_price_cents,
          'TVX' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10)));
end;
$$;

grant execute on function public.gerar_pagamento_da_assinatura() to authenticated;

-- O admin viu o Pix cair: mais 30 dias, contados do vencimento (quem paga
-- adiantado nao perde dias) ou de hoje (quem pagou atrasado nao ganha os dias
-- em que ficou sem receber corrida).
create or replace function public.confirmar_pagamento_do_entregador(p_pagamento uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pagamento courier_payments;
begin
  if not app.is_platform_admin() then
    raise exception 'Somente a plataforma confirma pagamento.' using errcode = 'insufficient_privilege';
  end if;

  select * into v_pagamento from courier_payments where id = p_pagamento for update;
  if v_pagamento.id is null or v_pagamento.status <> 'pending' then
    raise exception 'Pagamento nao encontrado ou ja confirmado.' using errcode = 'no_data_found';
  end if;

  update couriers
     set paid_until = greatest(app.vencimento_da_assinatura(id), current_date) + 30
   where id = v_pagamento.courier_id;

  update courier_payments
     set status = 'confirmed', confirmed_at = now(), confirmed_by = auth.uid()
   where id = p_pagamento;
end;
$$;

revoke all on function public.confirmar_pagamento_do_entregador(uuid) from public;
grant execute on function public.confirmar_pagamento_do_entregador(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- A fila: o autonomo com a assinatura vencida nao recebe corrida
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
