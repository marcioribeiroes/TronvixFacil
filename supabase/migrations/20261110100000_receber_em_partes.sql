-- =============================================================================
-- Tronvix Facil - receber em partes
--
-- A conta de cem reais da mesa nao chega de uma vez: um paga cinquenta em
-- dinheiro, o outro passa cinquenta no cartao. Ate aqui o recebimento era um
-- ato so - o pagamento inteiro, numa forma so -, e o balcao tinha de escolher
-- uma das duas formas e mentir na outra. A gaveta nao batia, a maquininha nao
-- batia.
--
-- Agora cada recebimento e uma linha em `payment_receipts`: forma, valor, hora
-- e quem recebeu. O pagamento do pedido continua um so (`payments`), e so vira
-- "pago" quando as partes somam o total. Duas partes iguais - cinquenta e
-- cinquenta em dinheiro - sao duas linhas, e nao uma repetida por engano.
--
-- O caixa passa a somar as partes. Pagamento quitado antes desta migracao, e o
-- pago pelo site (Pix confirmado, gateway), nao tem parte: entra no caixa pela
-- propria linha de `payments`, como sempre entrou.
-- =============================================================================

create table payment_receipts (
  id uuid primary key default gen_random_uuid(),
  payment_id uuid not null references payments (id) on delete cascade,
  order_id uuid not null references orders (id) on delete cascade,
  restaurant_id uuid not null references restaurants (id) on delete cascade,
  method payment_method not null,
  amount_cents bigint not null,
  received_at timestamptz not null default now(),
  received_by uuid references profiles (id) on delete set null,
  created_at timestamptz not null default now(),

  constraint payment_receipts_amount_positive check (amount_cents > 0)
);

create index payment_receipts_payment_idx on payment_receipts (payment_id);
create index payment_receipts_restaurant_idx on payment_receipts (restaurant_id, received_at desc);

comment on table payment_receipts is
  'Cada recebimento feito no balcao, na mesa ou na porta. Um pedido pode ser pago em varias partes e varias formas; o pagamento fica pago quando elas somam o total.';

alter table payment_receipts enable row level security;

-- Le quem ve o pedido. Escrever, so pela funcao `receber_parte`: uma parte
-- inserida direto escapava da conta do que falta.
create policy "parte do pagamento segue a visibilidade do pedido"
  on payment_receipts for select
  to authenticated
  using (app.can_see_order(order_id));

-- -----------------------------------------------------------------------------
-- Quanto ja entrou
-- -----------------------------------------------------------------------------

create or replace function app.recebido_do_pagamento(p_pagamento uuid)
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(sum(amount_cents), 0)::bigint
  from payment_receipts
  where payment_id = p_pagamento;
$$;

comment on function app.recebido_do_pagamento(uuid) is
  'A soma das partes ja recebidas de um pagamento.';

-- -----------------------------------------------------------------------------
-- O total nao fica menor que o que ja entrou
--
-- Editar o pedido refaz o valor do pagamento. Com parte ja recebida, tirar um
-- item poderia deixar a conta abaixo do que esta na gaveta - e o caixa teria
-- dinheiro sem pedido para explicar.
-- -----------------------------------------------------------------------------

create or replace function app.guard_payment_amount()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_recebido bigint;
begin
  if new.amount_cents < old.amount_cents then
    v_recebido := app.recebido_do_pagamento(new.id);
    if new.amount_cents < v_recebido then
      raise exception 'Ja foram recebidos % deste pedido. O total nao pode ficar abaixo disso.',
        to_char(v_recebido / 100.0, 'FM999G999G990D00')
        using errcode = 'check_violation';
    end if;
  end if;
  return new;
end;
$$;

create trigger payments_guard_amount
  before update of amount_cents on payments
  for each row execute function app.guard_payment_amount();

-- -----------------------------------------------------------------------------
-- Receber uma parte
-- -----------------------------------------------------------------------------

create or replace function public.receber_parte(
  p_pedido uuid,
  p_forma payment_method,
  p_valor_cents bigint
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pedido orders;
  v_pagamento payments;
  v_recebido bigint;
  v_falta bigint;
  v_forma payment_method;
begin
  select * into v_pedido from orders where id = p_pedido;
  if v_pedido.id is null then
    raise exception 'Pedido nao encontrado.' using errcode = 'no_data_found';
  end if;

  if not (app.is_member(v_pedido.restaurant_id) or app.is_platform_admin()) then
    raise exception 'Somente o estabelecimento registra o recebimento.'
      using errcode = 'insufficient_privilege';
  end if;

  -- Pedido cancelado ou recusado nao entra no caixa: o dinheiro, se veio,
  -- volta para o cliente.
  if v_pedido.status in ('cancelled', 'rejected') then
    raise exception 'Este pedido foi cancelado.' using errcode = 'check_violation';
  end if;

  -- `for update`: duas pessoas recebendo a mesma mesa ao mesmo tempo esperam
  -- uma pela outra, e a segunda ve o que a primeira ja recebeu.
  select * into v_pagamento from payments where order_id = p_pedido limit 1 for update;
  if v_pagamento.id is null then
    raise exception 'Este pedido nao tem pagamento registrado.' using errcode = 'no_data_found';
  end if;

  -- Pagamento pelo site tem caminho proprio (`confirmar_pix`, ou o gateway).
  -- Dois caminhos para o mesmo dinheiro e como se conta a venda duas vezes.
  if v_pagamento.timing <> 'on_delivery' then
    raise exception 'Este pedido e pago pelo site.' using errcode = 'check_violation';
  end if;
  if v_pagamento.status = 'paid' then
    raise exception 'Este pedido ja foi recebido.' using errcode = 'check_violation';
  end if;

  v_recebido := app.recebido_do_pagamento(v_pagamento.id);
  v_falta := v_pagamento.amount_cents - v_recebido;

  if p_valor_cents is null or p_valor_cents <= 0 then
    raise exception 'Informe quanto foi recebido.' using errcode = 'check_violation';
  end if;
  -- Troco nao e parte da conta: quem da cem para pagar oitenta recebeu
  -- oitenta. Passar do que falta e erro de digitacao, nao gorjeta.
  if p_valor_cents > v_falta then
    raise exception 'Falta receber so % deste pedido.',
      to_char(v_falta / 100.0, 'FM999G999G990D00')
      using errcode = 'check_violation';
  end if;

  insert into payment_receipts (
    payment_id, order_id, restaurant_id, method, amount_cents, received_by
  )
  values (
    v_pagamento.id, p_pedido, v_pedido.restaurant_id, p_forma, p_valor_cents, auth.uid()
  );

  v_falta := v_falta - p_valor_cents;

  if v_falta = 0 then
    -- A forma do pagamento passa a ser a da maior parte: e o resumo que as
    -- telas antigas mostram. O caixa nao usa isto - soma parte por parte.
    select method into v_forma
    from payment_receipts
    where payment_id = v_pagamento.id
    order by amount_cents desc, received_at desc
    limit 1;

    update payments
       set status = 'paid',
           paid_at = now(),
           method = v_forma,
           -- Troco so existe em dinheiro (payments_change_only_for_cash).
           change_for_cents = case when v_forma = 'cash' then change_for_cents end
     where id = v_pagamento.id;
  end if;

  return v_falta;
end;
$$;

revoke all on function public.receber_parte(uuid, payment_method, bigint) from public;
grant execute on function public.receber_parte(uuid, payment_method, bigint) to authenticated;

comment on function public.receber_parte is
  'Registra uma parte do pagamento feito na entrega, na forma em que veio. Devolve quanto ainda falta; com zero, o pagamento fica pago.';

-- -----------------------------------------------------------------------------
-- Receber tudo de uma vez continua existindo
--
-- E o caso comum, e o que o aplicativo do celular chama. Agora quer dizer
-- "receber o que falta, nesta forma" - com nada recebido antes, e o total.
-- -----------------------------------------------------------------------------

create or replace function public.receber_pagamento(
  p_pedido uuid,
  p_forma payment_method
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pagamento payments;
begin
  select * into v_pagamento from payments where order_id = p_pedido limit 1;

  -- As conferencias (quem pode, cancelado, pago pelo site, ja pago) moram em
  -- `receber_parte`. Aqui so se descobre quanto falta.
  perform public.receber_parte(
    p_pedido,
    p_forma,
    case
      when v_pagamento.id is null or v_pagamento.status = 'paid' then 1
      else v_pagamento.amount_cents - app.recebido_do_pagamento(v_pagamento.id)
    end
  );
end;
$$;

comment on function public.receber_pagamento is
  'Recebe o que falta do pagamento feito na entrega, numa forma so. Para dividir a conta, use receber_parte.';

-- -----------------------------------------------------------------------------
-- O caixa soma as partes
--
-- Recebimentos de um dia: cada parte, mais o pagamento pago que nao tem parte
-- nenhuma (o pago pelo site e o quitado antes de existir parte).
-- -----------------------------------------------------------------------------

create or replace function app.recebimentos_do_dia(p_restaurante uuid, p_dia date)
returns table (
  id uuid,
  order_id uuid,
  method payment_method,
  timing payment_timing,
  amount_cents bigint,
  received_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select r.id, r.order_id, r.method, 'on_delivery'::payment_timing, r.amount_cents, r.received_at
  from payment_receipts r
  where r.restaurant_id = p_restaurante
    and app.business_date(p_restaurante, r.received_at) = p_dia

  union all

  select pay.id, pay.order_id, pay.method, pay.timing, pay.amount_cents, pay.paid_at
  from payments pay
  join orders o on o.id = pay.order_id
  where o.restaurant_id = p_restaurante
    and pay.status = 'paid'
    and app.business_date(p_restaurante, pay.paid_at) = p_dia
    and not exists (select 1 from payment_receipts r where r.payment_id = pay.id);
$$;

comment on function app.recebimentos_do_dia(uuid, date) is
  'Tudo o que entrou num dia da loja: cada parte recebida e cada pagamento pago sem partes (pelo site, ou anterior as partes).';

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
      select sum(amount_cents)
      from app.recebimentos_do_dia(p_restaurante, p_dia)
      where method = 'cash'
    ), 0)
    - coalesce((
      select sum(amount_cents) from cash_movements
      where restaurant_id = p_restaurante and business_date = p_dia
        and type = 'withdrawal' and cancelled_at is null
    ), 0);
$$;

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

    -- Uma linha por parte: a mesa que pagou em duas vezes aparece duas vezes,
    -- cada uma com a sua forma. `id` e o da parte (ou do pagamento sem partes).
    'recebimentos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id,
        'pedido_id', o.id,
        'numero', o.number,
        'cliente', o.customer_name,
        'tipo_de_entrega', o.fulfillment,
        'mesa', o.table_label,
        'forma', r.method,
        'momento', r.timing,
        'valor_cents', r.amount_cents,
        'pago_em', r.received_at
      ) order by r.received_at)
      from app.recebimentos_do_dia(p_restaurante, v_dia) r
      join orders o on o.id = r.order_id
    ), '[]'::jsonb),

    -- Pedido do dia, ainda valendo, pago na entrega e nao quitado.
    -- `valor_cents` e o que FALTA: e o que o balcao tem de cobrar. O total e o
    -- ja recebido vem ao lado, para a tela explicar a conta.
    'a_receber', coalesce((
      select jsonb_agg(jsonb_build_object(
        'pedido_id', o.id,
        'numero', o.number,
        'cliente', o.customer_name,
        'tipo_de_entrega', o.fulfillment,
        'mesa', o.table_label,
        'forma', pay.method,
        'valor_cents', pay.amount_cents - app.recebido_do_pagamento(pay.id),
        'total_cents', pay.amount_cents,
        'recebido_cents', app.recebido_do_pagamento(pay.id)
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

-- A parte recebida no celular aparece no caixa do painel sem recarregar.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'payment_receipts'
  ) then
    alter publication supabase_realtime add table public.payment_receipts;
  end if;
end;
$$;
