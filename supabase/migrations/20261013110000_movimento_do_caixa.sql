-- =============================================================================
-- Tronvix Facil - movimento do caixa
--
-- O caixa do dia tem tres tipos de lancamento:
--
--   fundo de caixa  o dinheiro que entra na gaveta antes do primeiro cliente,
--                   para ter troco. Um por dia.
--   recebimento     o pagamento de um pedido (`payments`, ja existente).
--   sangria         o dinheiro que sai da gaveta no meio do dia, para o cofre
--                   ou para o banco. Sempre com motivo.
--
-- Fundo e sangria vivem aqui. Recebimento continua em `payments`: copiar o
-- pagamento para ca seria ter dois registros do mesmo dinheiro, e um dia eles
-- discordariam.
--
-- O "dia" e o dia da LOJA, no fuso dela (`restaurants.timezone`), e nao o do
-- servidor. Com o servidor em UTC, o caixa de Goiania virava as 21h.
-- =============================================================================

create type cash_movement_type as enum ('opening_float', 'withdrawal');

create table cash_movements (
  id uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references restaurants (id) on delete cascade,
  type cash_movement_type not null,
  amount_cents bigint not null,
  note text,

  -- O dia do caixa a que o lancamento pertence, no fuso da loja. Gravado, e
  -- nao calculado na leitura: e ele que impede dois fundos no mesmo dia.
  business_date date not null,

  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),

  -- Lancamento errado nao se apaga: se cancela, e fica no relatorio riscado.
  -- Caixa com linha sumida e caixa em que ninguem confia.
  cancelled_at timestamptz,
  cancelled_by uuid references auth.users (id) on delete set null,

  constraint cash_movements_amount_positive check (amount_cents > 0),
  constraint cash_movements_withdrawal_has_note check (
    type <> 'withdrawal' or length(trim(coalesce(note, ''))) >= 3
  )
);

create index cash_movements_day_idx on cash_movements (restaurant_id, business_date);

-- Um fundo valendo por dia. Cancelado nao conta: errou o valor, cancela e
-- registra de novo.
create unique index cash_movements_one_float_per_day
  on cash_movements (restaurant_id, business_date)
  where type = 'opening_float' and cancelled_at is null;

alter table cash_movements enable row level security;

-- So leitura por politica. Escrita apenas pelas funcoes abaixo, que conferem
-- o saldo e o fundo unico — insert direto pularia as duas regras.
create policy "movimento do caixa visivel a equipe"
  on cash_movements for select
  to authenticated
  using (app.is_member(restaurant_id) or app.is_platform_admin());

-- -----------------------------------------------------------------------------
-- O dia da loja
-- -----------------------------------------------------------------------------

create or replace function app.business_date(p_restaurante uuid, p_momento timestamptz)
returns date
language sql
stable
security definer
set search_path = public
as $$
  select (p_momento at time zone coalesce(
    (select timezone from restaurants where id = p_restaurante),
    'America/Sao_Paulo'
  ))::date;
$$;

comment on function app.business_date(uuid, timestamptz) is
  'Em que dia do caixa da loja cai este instante, no fuso dela.';

-- -----------------------------------------------------------------------------
-- Quanto dinheiro deveria estar na gaveta
-- -----------------------------------------------------------------------------

create or replace function app.cash_in_drawer(p_restaurante uuid, p_dia date)
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select
    coalesce((
      select sum(amount_cents) from cash_movements
      where restaurant_id = p_restaurante and business_date = p_dia
        and type = 'opening_float' and cancelled_at is null
    ), 0)
    + coalesce((
      select sum(pay.amount_cents)
      from payments pay
      join orders o on o.id = pay.order_id
      where o.restaurant_id = p_restaurante
        and pay.status = 'paid'
        and pay.method = 'cash'
        and app.business_date(p_restaurante, pay.paid_at) = p_dia
    ), 0)
    - coalesce((
      select sum(amount_cents) from cash_movements
      where restaurant_id = p_restaurante and business_date = p_dia
        and type = 'withdrawal' and cancelled_at is null
    ), 0);
$$;

comment on function app.cash_in_drawer(uuid, date) is
  'Fundo + recebido em dinheiro - sangrias, no dia da loja. E o que a gaveta tem de ter na conferencia.';

-- -----------------------------------------------------------------------------
-- Registrar
-- -----------------------------------------------------------------------------

create or replace function public.registrar_fundo_de_caixa(
  p_restaurante uuid,
  p_valor_cents bigint
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_dia date;
  v_id uuid;
begin
  if not (app.is_member(p_restaurante) or app.is_platform_admin()) then
    raise exception 'Somente a equipe da loja mexe no caixa.'
      using errcode = 'insufficient_privilege';
  end if;
  if p_valor_cents is null or p_valor_cents <= 0 then
    raise exception 'Informe o valor do fundo de caixa.' using errcode = 'check_violation';
  end if;

  v_dia := app.business_date(p_restaurante, now());

  if exists (
    select 1 from cash_movements
    where restaurant_id = p_restaurante and business_date = v_dia
      and type = 'opening_float' and cancelled_at is null
  ) then
    raise exception 'O fundo de caixa de hoje ja foi registrado.'
      using errcode = 'check_violation';
  end if;

  insert into cash_movements (restaurant_id, type, amount_cents, business_date, created_by)
  values (p_restaurante, 'opening_float', p_valor_cents, v_dia, auth.uid())
  returning id into v_id;

  return v_id;
end;
$$;

create or replace function public.registrar_sangria(
  p_restaurante uuid,
  p_valor_cents bigint,
  p_motivo text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_dia date;
  v_saldo bigint;
  v_id uuid;
begin
  if not (app.is_member(p_restaurante) or app.is_platform_admin()) then
    raise exception 'Somente a equipe da loja mexe no caixa.'
      using errcode = 'insufficient_privilege';
  end if;
  if p_valor_cents is null or p_valor_cents <= 0 then
    raise exception 'Informe o valor da sangria.' using errcode = 'check_violation';
  end if;
  if length(trim(coalesce(p_motivo, ''))) < 3 then
    raise exception 'Diga o motivo da sangria.' using errcode = 'check_violation';
  end if;

  v_dia := app.business_date(p_restaurante, now());

  -- Trava as sangrias do dia: duas pessoas tirando dinheiro no mesmo instante
  -- passariam as duas pela conferencia de saldo, e a gaveta ficaria negativa.
  perform 1 from restaurants where id = p_restaurante for update;

  v_saldo := app.cash_in_drawer(p_restaurante, v_dia);
  if p_valor_cents > v_saldo then
    raise exception 'A sangria passa do dinheiro na gaveta (R$ %).',
      to_char(v_saldo / 100.0, 'FM999G999G990D00')
      using errcode = 'check_violation';
  end if;

  insert into cash_movements (restaurant_id, type, amount_cents, note, business_date, created_by)
  values (p_restaurante, 'withdrawal', p_valor_cents, trim(p_motivo), v_dia, auth.uid())
  returning id into v_id;

  return v_id;
end;
$$;

-- Cancelar e da gestao. O atendente que errou chama o gerente — e o gerente
-- fica registrado como quem cancelou.
create or replace function public.cancelar_movimento_de_caixa(p_movimento uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_m cash_movements;
begin
  select * into v_m from cash_movements where id = p_movimento;
  if v_m.id is null then
    raise exception 'Lancamento nao encontrado.' using errcode = 'no_data_found';
  end if;
  if not (app.can_manage(v_m.restaurant_id) or app.is_platform_admin()) then
    raise exception 'Somente proprietario ou gerente cancela lancamento do caixa.'
      using errcode = 'insufficient_privilege';
  end if;
  if v_m.cancelled_at is not null then
    raise exception 'Este lancamento ja foi cancelado.' using errcode = 'check_violation';
  end if;
  -- Caixa de dia passado esta conferido e fechado.
  if v_m.business_date <> app.business_date(v_m.restaurant_id, now()) then
    raise exception 'So se cancela lancamento do caixa de hoje.' using errcode = 'check_violation';
  end if;

  update cash_movements
     set cancelled_at = now(), cancelled_by = auth.uid()
   where id = p_movimento;
end;
$$;

-- -----------------------------------------------------------------------------
-- O movimento de um dia, inteiro
--
-- Uma consulta so para a tela do caixa, o relatorio e o aplicativo. Calcular o
-- dia em cada um deles e o caminho de tres telas com tres totais diferentes.
-- -----------------------------------------------------------------------------

create or replace function public.movimento_do_caixa(
  p_restaurante uuid,
  p_dia date default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_hoje date;
  v_dia date;
begin
  if not (app.is_member(p_restaurante) or app.is_platform_admin()) then
    raise exception 'Somente a equipe da loja ve o caixa.'
      using errcode = 'insufficient_privilege';
  end if;

  v_hoje := app.business_date(p_restaurante, now());
  v_dia := coalesce(p_dia, v_hoje);

  return jsonb_build_object(
    'dia', v_dia,
    'hoje', v_dia = v_hoje,
    'fuso', coalesce((select timezone from restaurants where id = p_restaurante), 'America/Sao_Paulo'),
    'dinheiro_na_gaveta_cents', app.cash_in_drawer(p_restaurante, v_dia),

    'lancamentos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', m.id,
        'tipo', m.type,
        'valor_cents', m.amount_cents,
        'observacao', m.note,
        'feito_em', m.created_at,
        'feito_por', nullif(p.full_name, ''),
        'cancelado_em', m.cancelled_at,
        'cancelado_por', nullif(pc.full_name, '')
      ) order by m.created_at)
      from cash_movements m
      left join profiles p on p.id = m.created_by
      left join profiles pc on pc.id = m.cancelled_by
      where m.restaurant_id = p_restaurante and m.business_date = v_dia
    ), '[]'::jsonb),

    'recebimentos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'pedido_id', o.id,
        'numero', o.number,
        'cliente', o.customer_name,
        'tipo_de_entrega', o.fulfillment,
        'mesa', o.table_label,
        'forma', pay.method,
        'momento', pay.timing,
        'valor_cents', pay.amount_cents,
        'pago_em', pay.paid_at
      ) order by pay.paid_at)
      from payments pay
      join orders o on o.id = pay.order_id
      where o.restaurant_id = p_restaurante
        and pay.status = 'paid'
        and app.business_date(p_restaurante, pay.paid_at) = v_dia
    ), '[]'::jsonb),

    -- Pedido do dia, ainda valendo, pago na entrega e nao recebido.
    'a_receber', coalesce((
      select jsonb_agg(jsonb_build_object(
        'pedido_id', o.id,
        'numero', o.number,
        'cliente', o.customer_name,
        'tipo_de_entrega', o.fulfillment,
        'mesa', o.table_label,
        'forma', pay.method,
        'valor_cents', pay.amount_cents
      ) order by o.created_at)
      from payments pay
      join orders o on o.id = pay.order_id
      where o.restaurant_id = p_restaurante
        and pay.status = 'pending'
        and pay.timing = 'on_delivery'
        and o.status not in ('cancelled', 'rejected')
        and app.business_date(p_restaurante, o.created_at) = v_dia
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.registrar_fundo_de_caixa(uuid, bigint) from public;
revoke all on function public.registrar_sangria(uuid, bigint, text) from public;
revoke all on function public.cancelar_movimento_de_caixa(uuid) from public;
revoke all on function public.movimento_do_caixa(uuid, date) from public;
grant execute on function public.registrar_fundo_de_caixa(uuid, bigint) to authenticated;
grant execute on function public.registrar_sangria(uuid, bigint, text) to authenticated;
grant execute on function public.cancelar_movimento_de_caixa(uuid) to authenticated;
grant execute on function public.movimento_do_caixa(uuid, date) to authenticated;

comment on function public.registrar_sangria is
  'Tira dinheiro da gaveta no meio do dia. Exige motivo e nao deixa a gaveta ficar negativa.';
comment on function public.movimento_do_caixa is
  'Fundo, recebimentos, sangrias e o que falta receber de um dia da loja, no fuso dela. Fonte unica da tela do caixa, do relatorio e do aplicativo.';

-- O caixa aberto em duas telas ve a sangria da outra.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'cash_movements'
  ) then
    alter publication supabase_realtime add table public.cash_movements;
  end if;
end;
$$;
