-- =============================================================================
-- Tronvix Facil - Carrinho, pedidos, pagamentos e entregas
--
-- Duas decisoes estruturais moram aqui:
--
-- 1. O pedido guarda SNAPSHOT. order_items copia nome e preco do produto no
--    instante da compra. O restaurante reajusta o cardapio amanha e o pedido
--    de ontem continua contando a historia certa - inclusive para conferencia
--    de caixa e para o financeiro da plataforma.
--
-- 2. O status do pedido e uma maquina de estados fechada, validada por
--    gatilho. Nao existe caminho - nem por bug de tela, nem por chamada
--    direta a API - que leve um pedido de "entregue" de volta para "em
--    preparo". O espelho em TypeScript fica em
--    src/modules/pedidos/maquina-de-estados.ts.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- carts - um carrinho aberto por cliente e por estabelecimento
-- -----------------------------------------------------------------------------

create table carts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles (id) on delete cascade,
  restaurant_id uuid not null references restaurants (id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table carts is
  'Carrinho nao guarda total: o valor e sempre recalculado no servidor a partir do cardapio atual, na hora de fechar o pedido.';

create unique index carts_open_per_restaurant_idx on carts (user_id, restaurant_id);

create trigger carts_touch
  before update on carts
  for each row execute function app.touch_updated_at();

create table cart_items (
  id uuid primary key default gen_random_uuid(),
  cart_id uuid not null references carts (id) on delete cascade,
  product_id uuid not null references products (id) on delete cascade,
  quantity int not null default 1,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint cart_items_quantity_positive check (quantity between 1 and 99)
);

create index cart_items_cart_idx on cart_items (cart_id);

create trigger cart_items_touch
  before update on cart_items
  for each row execute function app.touch_updated_at();

create table cart_item_addons (
  id uuid primary key default gen_random_uuid(),
  cart_item_id uuid not null references cart_items (id) on delete cascade,
  addon_id uuid not null references addons (id) on delete cascade,
  quantity int not null default 1,

  unique (cart_item_id, addon_id),
  constraint cart_item_addons_quantity_positive check (quantity between 1 and 99)
);

-- -----------------------------------------------------------------------------
-- orders
-- -----------------------------------------------------------------------------

create table orders (
  id uuid primary key default gen_random_uuid(),
  -- Numero visivel ao cliente e ao balcao, sequencial POR ESTABELECIMENTO.
  -- Cada loja tem o seu #1; ninguem quer explicar ao cliente por que o
  -- primeiro pedido do dia foi o numero 48.317.
  number int not null,

  restaurant_id uuid not null references restaurants (id) on delete restrict,
  customer_id uuid references profiles (id) on delete set null,

  -- Contato copiado no momento do pedido. O restaurante precisa falar com o
  -- cliente sem que isso signifique dar a ele acesso de leitura a tabela de
  -- perfis da plataforma inteira.
  customer_name text not null,
  customer_phone text,

  status order_status not null default 'awaiting_payment',
  fulfillment fulfillment_type not null default 'delivery',

  -- Endereco tambem e snapshot: o cliente pode editar ou apagar o endereco
  -- depois, e a entrega de ontem continua tendo destino.
  address_id uuid references addresses (id) on delete set null,
  address_summary text,
  address_district text,
  address_city text,
  address_postal_code text,
  address_latitude numeric(10, 7),
  address_longitude numeric(10, 7),

  subtotal_cents bigint not null default 0,
  delivery_fee_cents bigint not null default 0,
  discount_cents bigint not null default 0,
  total_cents bigint not null default 0,
  -- Quanto a plataforma retem. Congelado no fechamento: mudar a comissao
  -- amanha nao pode reescrever o que ja foi acertado.
  commission_cents bigint not null default 0,

  coupon_id uuid,
  coupon_code text,

  notes text,
  scheduled_for timestamptz,

  confirmed_at timestamptz,
  ready_at timestamptz,
  delivered_at timestamptz,
  cancelled_at timestamptz,
  cancellation_reason text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (restaurant_id, number),

  constraint orders_money_non_negative check (
    subtotal_cents >= 0
    and delivery_fee_cents >= 0
    and discount_cents >= 0
    and total_cents >= 0
    and commission_cents >= 0
  ),
  -- O total tem de fechar. Se uma escrita tentar gravar um total que nao
  -- corresponde as partes, a transacao morre aqui.
  constraint orders_total_matches check (
    total_cents = subtotal_cents + delivery_fee_cents - discount_cents
  ),
  constraint orders_discount_within_bounds check (
    discount_cents <= subtotal_cents + delivery_fee_cents
  ),
  -- Entrega exige destino; retirada nao.
  constraint orders_delivery_needs_address check (
    fulfillment <> 'delivery'
    or status in ('awaiting_payment', 'cancelled', 'rejected')
    or address_summary is not null
  )
);

create index orders_restaurant_status_idx
  on orders (restaurant_id, status, created_at desc);
create index orders_customer_idx on orders (customer_id, created_at desc);
create index orders_created_idx on orders (created_at desc);
create index orders_open_idx
  on orders (restaurant_id, created_at)
  where status in ('received', 'confirmed', 'preparing', 'ready', 'out_for_delivery');

create trigger orders_touch
  before update on orders
  for each row execute function app.touch_updated_at();

-- Contador por estabelecimento. Tabela separada em vez de max(number)+1:
-- o UPDATE ... RETURNING trava a linha do contador, entao dois pedidos
-- simultaneos nunca recebem o mesmo numero.
create table restaurant_order_counters (
  restaurant_id uuid primary key references restaurants (id) on delete cascade,
  last_number int not null default 0
);

alter table restaurant_order_counters enable row level security;

create or replace function app.assign_order_number()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_number int;
begin
  if new.number is not null and new.number > 0 then
    return new;
  end if;

  insert into restaurant_order_counters (restaurant_id, last_number)
  values (new.restaurant_id, 1)
  on conflict (restaurant_id)
    do update set last_number = restaurant_order_counters.last_number + 1
  returning last_number into v_number;

  new.number := v_number;
  return new;
end;
$$;

create trigger orders_assign_number
  before insert on orders
  for each row execute function app.assign_order_number();

-- -----------------------------------------------------------------------------
-- Maquina de estados do pedido
-- -----------------------------------------------------------------------------

create or replace function app.order_transition_allowed(
  p_from order_status,
  p_to order_status
)
returns boolean
language sql
immutable
as $$
  select case p_from
    when 'awaiting_payment' then p_to in ('received', 'cancelled')
    when 'received'         then p_to in ('confirmed', 'rejected', 'cancelled')
    when 'confirmed'        then p_to in ('preparing', 'cancelled')
    when 'preparing'        then p_to in ('ready', 'cancelled')
    -- De "pronto" o caminho depende do tipo: entrega sai para a rua,
    -- retirada e concluida no balcao.
    when 'ready'            then p_to in ('out_for_delivery', 'delivered', 'cancelled')
    when 'out_for_delivery' then p_to in ('delivered', 'cancelled')
    -- Estados terminais nao tem saida.
    when 'delivered'        then false
    when 'cancelled'        then false
    when 'rejected'         then false
  end;
$$;

comment on function app.order_transition_allowed(order_status, order_status) is
  'Unica fonte de verdade do fluxo de status no banco. O espelho em TypeScript fica em src/modules/pedidos/maquina-de-estados.ts e os dois sao verificados pelo mesmo conjunto de casos de teste.';

create or replace function app.guard_order_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = old.status then
    return new;
  end if;

  if not app.order_transition_allowed(old.status, new.status) then
    raise exception 'Transicao de status invalida: % -> %', old.status, new.status
      using errcode = 'check_violation';
  end if;

  -- Retirada nao passa por "saiu para entrega": nao ha rua no caminho.
  if new.status = 'out_for_delivery' and new.fulfillment <> 'delivery' then
    raise exception 'Pedido de retirada nao sai para entrega.'
      using errcode = 'check_violation';
  end if;

  -- Marcos de tempo sao consequencia da transicao, nunca campo que a tela
  -- preenche. Assim o relatorio de tempo medio mede o que aconteceu.
  new.confirmed_at := case when new.status = 'confirmed' then now() else new.confirmed_at end;
  new.ready_at     := case when new.status = 'ready' then now() else new.ready_at end;
  new.delivered_at := case when new.status = 'delivered' then now() else new.delivered_at end;
  new.cancelled_at := case
                        when new.status in ('cancelled', 'rejected') then now()
                        else new.cancelled_at
                      end;

  return new;
end;
$$;

create trigger orders_guard_status
  before update of status on orders
  for each row execute function app.guard_order_status();

-- -----------------------------------------------------------------------------
-- order_items - snapshot do que foi comprado
-- -----------------------------------------------------------------------------

create table order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references orders (id) on delete cascade,
  -- ON DELETE SET NULL, nao CASCADE: se o produto for removido do cardapio, o
  -- item do pedido antigo permanece com o nome e o preco copiados.
  product_id uuid references products (id) on delete set null,

  product_name text not null,
  product_image_url text,
  unit_price_cents bigint not null,
  quantity int not null,
  addons_total_cents bigint not null default 0,
  total_cents bigint not null,
  notes text,

  created_at timestamptz not null default now(),

  constraint order_items_quantity_positive check (quantity between 1 and 99),
  constraint order_items_price_positive check (unit_price_cents > 0),
  constraint order_items_total_matches check (
    total_cents = (unit_price_cents + addons_total_cents) * quantity
  )
);

create index order_items_order_idx on order_items (order_id);

create table order_item_addons (
  id uuid primary key default gen_random_uuid(),
  order_item_id uuid not null references order_items (id) on delete cascade,
  addon_id uuid references addons (id) on delete set null,
  addon_name text not null,
  group_name text,
  unit_price_cents bigint not null default 0,
  quantity int not null default 1,
  total_cents bigint not null,

  constraint order_item_addons_total_matches check (
    total_cents = unit_price_cents * quantity
  )
);

create index order_item_addons_item_idx on order_item_addons (order_item_id);

-- -----------------------------------------------------------------------------
-- order_status_history - quem mudou o que, e quando
-- -----------------------------------------------------------------------------

create table order_status_history (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references orders (id) on delete cascade,
  from_status order_status,
  to_status order_status not null,
  changed_by uuid references profiles (id) on delete set null,
  note text,
  created_at timestamptz not null default now()
);

create index order_status_history_order_idx on order_status_history (order_id, created_at);

-- O historico e escrito pelo banco. Se dependesse de a aplicacao lembrar de
-- registrar, faltaria justamente a linha do dia em que algo deu errado.
create or replace function app.log_order_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    insert into order_status_history (order_id, from_status, to_status, changed_by)
    values (new.id, null, new.status, auth.uid());
  elsif new.status is distinct from old.status then
    insert into order_status_history (order_id, from_status, to_status, changed_by, note)
    values (new.id, old.status, new.status, auth.uid(), new.cancellation_reason);
  end if;

  return new;
end;
$$;

create trigger orders_log_status
  after insert or update of status on orders
  for each row execute function app.log_order_status();

-- -----------------------------------------------------------------------------
-- payments
-- -----------------------------------------------------------------------------

create table payments (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references orders (id) on delete cascade,
  method payment_method not null,
  timing payment_timing not null,
  status payment_status not null default 'pending',
  amount_cents bigint not null,

  -- Troco para: so faz sentido em dinheiro e tem de cobrir o total.
  change_for_cents bigint,

  -- Campos do gateway. Enquanto a integracao real nao entra, o adaptador
  -- simulado preenche os mesmos campos - trocar de provedor nao mexe no schema.
  provider text,
  provider_ref text,
  provider_payload jsonb,
  pix_qr_code text,
  pix_expires_at timestamptz,

  paid_at timestamptz,
  refunded_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint payments_amount_positive check (amount_cents > 0),
  constraint payments_change_only_for_cash check (
    change_for_cents is null or method = 'cash'
  ),
  constraint payments_change_covers_total check (
    change_for_cents is null or change_for_cents >= amount_cents
  )
);

create index payments_order_idx on payments (order_id);
create index payments_status_idx on payments (status, created_at desc);
create unique index payments_provider_ref_idx
  on payments (provider, provider_ref)
  where provider_ref is not null;

comment on index payments_provider_ref_idx is
  'Idempotencia de webhook: o mesmo evento do provedor chegando duas vezes nao cria dois pagamentos.';

create trigger payments_touch
  before update on payments
  for each row execute function app.touch_updated_at();

-- -----------------------------------------------------------------------------
-- deliveries
-- -----------------------------------------------------------------------------

create table deliveries (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null unique references orders (id) on delete cascade,
  restaurant_id uuid not null references restaurants (id) on delete cascade,
  courier_id uuid references couriers (id) on delete set null,

  status delivery_status not null default 'pending',
  -- Quanto o entregador recebe. Pode divergir da taxa cobrada do cliente:
  -- sao dois lados diferentes da mesma corrida.
  courier_fee_cents bigint not null default 0,
  distance_km numeric(6, 2),

  assigned_at timestamptz,
  picked_up_at timestamptz,
  delivered_at timestamptz,
  cancelled_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint deliveries_fee_non_negative check (courier_fee_cents >= 0),
  -- Fora de "pendente" e "procurando entregador", tem de haver entregador.
  constraint deliveries_courier_when_assigned check (
    status in ('pending', 'searching_courier', 'cancelled')
    or courier_id is not null
  )
);

create index deliveries_courier_idx on deliveries (courier_id, status);
create index deliveries_restaurant_idx on deliveries (restaurant_id, status);
create index deliveries_open_idx
  on deliveries (created_at)
  where status = 'searching_courier';

create trigger deliveries_touch
  before update on deliveries
  for each row execute function app.touch_updated_at();

create or replace function app.delivery_transition_allowed(
  p_from delivery_status,
  p_to delivery_status
)
returns boolean
language sql
immutable
as $$
  select case p_from
    when 'pending'               then p_to in ('searching_courier', 'cancelled')
    when 'searching_courier'     then p_to in ('assigned', 'cancelled')
    when 'assigned'              then p_to in ('heading_to_restaurant', 'searching_courier', 'cancelled')
    when 'heading_to_restaurant' then p_to in ('picked_up', 'searching_courier', 'cancelled')
    when 'picked_up'             then p_to in ('heading_to_customer', 'cancelled')
    when 'heading_to_customer'   then p_to in ('delivered', 'cancelled')
    when 'delivered'             then false
    when 'cancelled'             then false
  end;
$$;

comment on function app.delivery_transition_allowed(delivery_status, delivery_status) is
  'De "aceita" e "a caminho do restaurante" ha volta para "procurando entregador": e a desistencia do entregador, que devolve a corrida a fila em vez de travar o pedido.';

create or replace function app.guard_delivery_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = old.status then
    return new;
  end if;

  if not app.delivery_transition_allowed(old.status, new.status) then
    raise exception 'Transicao de entrega invalida: % -> %', old.status, new.status
      using errcode = 'check_violation';
  end if;

  -- Devolver a corrida a fila limpa o entregador anterior.
  if new.status = 'searching_courier' then
    new.courier_id := null;
    new.assigned_at := null;
  end if;

  new.assigned_at   := case when new.status = 'assigned' then now() else new.assigned_at end;
  new.picked_up_at  := case when new.status = 'picked_up' then now() else new.picked_up_at end;
  new.delivered_at  := case when new.status = 'delivered' then now() else new.delivered_at end;
  new.cancelled_at  := case when new.status = 'cancelled' then now() else new.cancelled_at end;

  return new;
end;
$$;

create trigger deliveries_guard_status
  before update of status on deliveries
  for each row execute function app.guard_delivery_status();

-- =============================================================================
-- RLS - carrinho, pedidos, pagamentos e entregas
-- =============================================================================

alter table carts enable row level security;
alter table cart_items enable row level security;
alter table cart_item_addons enable row level security;
alter table orders enable row level security;
alter table order_items enable row level security;
alter table order_item_addons enable row level security;
alter table order_status_history enable row level security;
alter table payments enable row level security;
alter table deliveries enable row level security;

create or replace function app.owns_cart(p_cart uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from carts c where c.id = p_cart and c.user_id = auth.uid()
  );
$$;

-- Quem enxerga este pedido: o cliente dele, a equipe do estabelecimento, o
-- entregador designado ou a plataforma. Mais ninguem.
create or replace function app.can_see_order(p_order uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from orders o
    left join deliveries d on d.order_id = o.id
    where o.id = p_order
      and (
        o.customer_id = auth.uid()
        or app.is_member(o.restaurant_id)
        or (d.courier_id is not null and d.courier_id = app.my_courier_id())
        or app.is_platform_admin()
      )
  );
$$;

-- carrinho
create policy "cliente gerencia o proprio carrinho"
  on carts for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy "cliente gerencia os itens do proprio carrinho"
  on cart_items for all
  to authenticated
  using (app.owns_cart(cart_id))
  with check (app.owns_cart(cart_id));

create policy "cliente gerencia os adicionais do proprio carrinho"
  on cart_item_addons for all
  to authenticated
  using (
    exists (
      select 1 from cart_items i
      where i.id = cart_item_id and app.owns_cart(i.cart_id)
    )
  )
  with check (
    exists (
      select 1 from cart_items i
      where i.id = cart_item_id and app.owns_cart(i.cart_id)
    )
  );

-- pedidos
create policy "pedido visivel a quem participa dele"
  on orders for select
  to authenticated
  using (
    customer_id = auth.uid()
    or app.is_member(restaurant_id)
    or app.is_platform_admin()
    or exists (
      select 1 from deliveries d
      where d.order_id = orders.id and d.courier_id = app.my_courier_id()
    )
  );

create policy "cliente cria o proprio pedido"
  on orders for insert
  to authenticated
  with check (customer_id = auth.uid() or app.is_member(restaurant_id));

-- Nao ha politica de DELETE em orders, de proposito: pedido nao se apaga.
-- Cancelar e uma transicao de status, e ela fica registrada.
create policy "equipe e cliente atualizam o pedido"
  on orders for update
  to authenticated
  using (
    app.is_member(restaurant_id)
    or app.is_platform_admin()
    or customer_id = auth.uid()
    or exists (
      select 1 from deliveries d
      where d.order_id = orders.id and d.courier_id = app.my_courier_id()
    )
  )
  with check (
    app.is_member(restaurant_id)
    or app.is_platform_admin()
    or customer_id = auth.uid()
    or exists (
      select 1 from deliveries d
      where d.order_id = orders.id and d.courier_id = app.my_courier_id()
    )
  );

-- Valores de pedido fechado sao imutaveis pela API. Quem recalcula preco e a
-- funcao de fechamento, que roda em contexto elevado. Sem esta trava, um
-- cliente com o token dele poderia zerar o proprio total via PATCH.
create or replace function app.guard_order_money()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if app.is_platform_admin() then
    return new;
  end if;

  if new.subtotal_cents is distinct from old.subtotal_cents
     or new.delivery_fee_cents is distinct from old.delivery_fee_cents
     or new.discount_cents is distinct from old.discount_cents
     or new.total_cents is distinct from old.total_cents
     or new.commission_cents is distinct from old.commission_cents
     or new.number is distinct from old.number
     or new.restaurant_id is distinct from old.restaurant_id then
    raise exception 'Valores e identificacao do pedido nao podem ser alterados apos o fechamento.'
      using errcode = 'insufficient_privilege';
  end if;

  return new;
end;
$$;

create trigger orders_guard_money
  before update on orders
  for each row execute function app.guard_order_money();

-- itens
create policy "itens seguem a visibilidade do pedido"
  on order_items for select
  to authenticated
  using (app.can_see_order(order_id));

create policy "itens criados com o pedido"
  on order_items for insert
  to authenticated
  with check (app.can_see_order(order_id));

create policy "adicionais seguem a visibilidade do item"
  on order_item_addons for select
  to authenticated
  using (
    exists (
      select 1 from order_items i
      where i.id = order_item_id and app.can_see_order(i.order_id)
    )
  );

create policy "adicionais criados com o item"
  on order_item_addons for insert
  to authenticated
  with check (
    exists (
      select 1 from order_items i
      where i.id = order_item_id and app.can_see_order(i.order_id)
    )
  );

-- historico: leitura para quem ve o pedido; escrita so pelo gatilho.
create policy "historico segue a visibilidade do pedido"
  on order_status_history for select
  to authenticated
  using (app.can_see_order(order_id));

-- pagamentos
create policy "pagamento segue a visibilidade do pedido"
  on payments for select
  to authenticated
  using (app.can_see_order(order_id));

create policy "pagamento criado com o pedido"
  on payments for insert
  to authenticated
  with check (app.can_see_order(order_id));

-- Confirmar pagamento e do servidor (webhook do gateway, com service_role) ou
-- da equipe, no caso de dinheiro e maquininha na entrega.
create policy "equipe confirma pagamento"
  on payments for update
  to authenticated
  using (
    exists (
      select 1 from orders o
      where o.id = payments.order_id
        and (app.is_member(o.restaurant_id) or app.is_platform_admin())
    )
  )
  with check (
    exists (
      select 1 from orders o
      where o.id = payments.order_id
        and (app.is_member(o.restaurant_id) or app.is_platform_admin())
    )
  );

-- entregas
create policy "entrega visivel a quem participa"
  on deliveries for select
  to authenticated
  using (
    app.is_member(restaurant_id)
    or app.is_platform_admin()
    or courier_id = app.my_courier_id()
    -- A fila aberta e visivel a qualquer entregador aprovado: e dela que sai
    -- o aceite.
    or (status = 'searching_courier' and app.is_approved_courier())
    or exists (
      select 1 from orders o
      where o.id = deliveries.order_id and o.customer_id = auth.uid()
    )
  );

create policy "equipe cria a entrega"
  on deliveries for insert
  to authenticated
  with check (app.is_member(restaurant_id) or app.is_platform_admin());

create policy "entregador e equipe atualizam a entrega"
  on deliveries for update
  to authenticated
  using (
    app.is_member(restaurant_id)
    or app.is_platform_admin()
    or courier_id = app.my_courier_id()
    or (status = 'searching_courier' and app.is_approved_courier())
  )
  with check (
    app.is_member(restaurant_id)
    or app.is_platform_admin()
    or courier_id = app.my_courier_id()
  );

-- contador de numeracao: ninguem le nem escreve pela API.
create policy "contador so pela plataforma"
  on restaurant_order_counters for select
  to authenticated
  using (app.is_platform_admin());
