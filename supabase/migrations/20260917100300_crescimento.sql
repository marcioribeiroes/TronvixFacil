-- =============================================================================
-- Tronvix Facil - Cupons, avaliacoes, notificacoes, banners, estoque e
-- configuracoes da plataforma.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- coupons
-- -----------------------------------------------------------------------------

create table coupons (
  id uuid primary key default gen_random_uuid(),
  scope coupon_scope not null default 'restaurant',
  -- Nulo quando o cupom e da plataforma e vale em qualquer estabelecimento.
  restaurant_id uuid references restaurants (id) on delete cascade,

  code citext not null,
  description text,
  discount discount_type not null,
  -- Percentual em pontos base (1500 = 15,00%) quando discount = 'percentage';
  -- centavos quando 'fixed'; ignorado quando 'free_shipping'.
  value int not null default 0,
  max_discount_cents bigint,
  min_order_cents bigint not null default 0,

  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  max_uses int,
  max_uses_per_customer int not null default 1,
  used_count int not null default 0,
  first_order_only boolean not null default false,

  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,

  constraint coupons_scope_consistent check (
    (scope = 'platform' and restaurant_id is null)
    or (scope = 'restaurant' and restaurant_id is not null)
  ),
  constraint coupons_value_range check (
    case discount
      when 'percentage' then value between 1 and 10000
      when 'fixed' then value > 0
      when 'free_shipping' then true
    end
  ),
  constraint coupons_window check (ends_at is null or ends_at > starts_at),
  constraint coupons_uses check (max_uses is null or max_uses > 0)
);

comment on column coupons.value is
  'Pontos base quando percentual (1500 = 15,00%), centavos quando valor fixo. Inteiro nos dois casos.';

-- O mesmo codigo pode existir na plataforma e em um restaurante; o que nao
-- pode e repetir dentro do mesmo escopo.
create unique index coupons_code_platform_idx
  on coupons (code)
  where scope = 'platform' and deleted_at is null;

create unique index coupons_code_restaurant_idx
  on coupons (restaurant_id, code)
  where scope = 'restaurant' and deleted_at is null;

create index coupons_active_idx on coupons (is_active, starts_at, ends_at)
  where deleted_at is null;

create trigger coupons_touch
  before update on coupons
  for each row execute function app.touch_updated_at();

alter table orders
  add constraint orders_coupon_fkey
  foreign key (coupon_id) references coupons (id) on delete set null;

create table coupon_redemptions (
  id uuid primary key default gen_random_uuid(),
  coupon_id uuid not null references coupons (id) on delete cascade,
  order_id uuid not null references orders (id) on delete cascade,
  user_id uuid not null references profiles (id) on delete cascade,
  discount_cents bigint not null,
  created_at timestamptz not null default now(),

  -- Um cupom conta uma vez por pedido. O limite por cliente e verificado
  -- contra esta tabela na hora de fechar.
  unique (coupon_id, order_id),
  constraint coupon_redemptions_discount_positive check (discount_cents >= 0)
);

create index coupon_redemptions_user_idx on coupon_redemptions (user_id, coupon_id);

-- -----------------------------------------------------------------------------
-- reviews
-- -----------------------------------------------------------------------------

create table reviews (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null unique references orders (id) on delete cascade,
  restaurant_id uuid not null references restaurants (id) on delete cascade,
  customer_id uuid not null references profiles (id) on delete cascade,
  courier_id uuid references couriers (id) on delete set null,

  restaurant_rating smallint not null,
  courier_rating smallint,
  comment text,
  reply text,
  replied_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint reviews_restaurant_rating_range check (restaurant_rating between 1 and 5),
  constraint reviews_courier_rating_range check (
    courier_rating is null or courier_rating between 1 and 5
  )
);

create index reviews_restaurant_idx on reviews (restaurant_id, created_at desc);
create index reviews_courier_idx on reviews (courier_id, created_at desc);

create trigger reviews_touch
  before update on reviews
  for each row execute function app.touch_updated_at();

-- A media e recalculada pelo banco a cada avaliacao. Manter o agregado na
-- linha do restaurante evita um AVG sobre a tabela inteira a cada carga da
-- home, que e a tela mais acessada do produto.
create or replace function app.refresh_ratings()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_restaurant uuid := coalesce(new.restaurant_id, old.restaurant_id);
  v_courier uuid := coalesce(new.courier_id, old.courier_id);
begin
  update restaurants r
  set rating_avg = coalesce(agg.media, 0),
      rating_count = coalesce(agg.total, 0)
  from (
    select avg(restaurant_rating)::numeric(3, 2) as media, count(*) as total
    from reviews
    where restaurant_id = v_restaurant
  ) agg
  where r.id = v_restaurant;

  if v_courier is not null then
    update couriers c
    set rating_avg = coalesce(agg.media, 0),
        rating_count = coalesce(agg.total, 0)
    from (
      select avg(courier_rating)::numeric(3, 2) as media, count(*) as total
      from reviews
      where courier_id = v_courier and courier_rating is not null
    ) agg
    where c.id = v_courier;
  end if;

  return coalesce(new, old);
end;
$$;

create trigger reviews_refresh_ratings
  after insert or update or delete on reviews
  for each row execute function app.refresh_ratings();

-- -----------------------------------------------------------------------------
-- notifications
-- -----------------------------------------------------------------------------

create table notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles (id) on delete cascade,
  title text not null,
  body text not null,
  kind text not null default 'order',
  order_id uuid references orders (id) on delete cascade,
  url text,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index notifications_user_idx on notifications (user_id, created_at desc);
create index notifications_unread_idx on notifications (user_id) where read_at is null;

-- -----------------------------------------------------------------------------
-- banners
-- -----------------------------------------------------------------------------

create table banners (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  image_url text not null,
  target_url text,
  restaurant_id uuid references restaurants (id) on delete cascade,
  position int not null default 0,
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint banners_window check (ends_at is null or ends_at > starts_at)
);

create index banners_active_idx on banners (is_active, position);

create trigger banners_touch
  before update on banners
  for each row execute function app.touch_updated_at();

-- -----------------------------------------------------------------------------
-- stock_movements - controle de estoque simplificado
-- -----------------------------------------------------------------------------

create table stock_movements (
  id uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references restaurants (id) on delete cascade,
  product_id uuid not null references products (id) on delete cascade,
  kind stock_movement_type not null,
  quantity int not null,
  balance_after int not null,
  order_id uuid references orders (id) on delete set null,
  reason text,
  created_by uuid references profiles (id) on delete set null,
  created_at timestamptz not null default now(),

  constraint stock_movements_quantity_positive check (quantity > 0)
);

create index stock_movements_product_idx on stock_movements (product_id, created_at desc);
create index stock_movements_restaurant_idx on stock_movements (restaurant_id, created_at desc);

-- -----------------------------------------------------------------------------
-- platform_settings - linha unica de configuracao global
-- -----------------------------------------------------------------------------

create table platform_settings (
  id boolean primary key default true,
  brand_name text not null default 'Tronvix Facil',
  support_email citext,
  support_phone text,
  default_commission_bps int not null default 1000,
  default_courier_fee_cents bigint not null default 700,
  min_order_cents bigint not null default 0,
  allow_new_signups boolean not null default true,
  maintenance_mode boolean not null default false,
  updated_at timestamptz not null default now(),

  -- Chave booleana com default true: a tabela nunca tem uma segunda linha.
  constraint platform_settings_single_row check (id)
);

create trigger platform_settings_touch
  before update on platform_settings
  for each row execute function app.touch_updated_at();

insert into platform_settings (id) values (true) on conflict do nothing;

-- =============================================================================
-- RLS - crescimento
-- =============================================================================

alter table coupons enable row level security;
alter table coupon_redemptions enable row level security;
alter table reviews enable row level security;
alter table notifications enable row level security;
alter table banners enable row level security;
alter table stock_movements enable row level security;
alter table platform_settings enable row level security;

-- coupons: o cliente precisa validar o codigo que digitou, entao le os cupons
-- vigentes. Cupom nao e segredo - o limite de uso e que e regra.
create policy "cupons vigentes sao consultaveis"
  on coupons for select
  to anon, authenticated
  using (
    is_active
    and deleted_at is null
    and starts_at <= now()
    and (ends_at is null or ends_at > now())
  );

create policy "gestao le os proprios cupons"
  on coupons for select
  to authenticated
  using (
    (restaurant_id is not null and app.is_member(restaurant_id))
    or app.is_platform_admin()
  );

create policy "gestao edita os proprios cupons"
  on coupons for all
  to authenticated
  using (
    (scope = 'restaurant' and app.can_manage(restaurant_id))
    or app.is_platform_admin()
  )
  with check (
    (scope = 'restaurant' and app.can_manage(restaurant_id))
    or app.is_platform_admin()
  );

create policy "resgate visivel a quem participa"
  on coupon_redemptions for select
  to authenticated
  using (user_id = auth.uid() or app.can_see_order(order_id));

create policy "resgate criado com o pedido"
  on coupon_redemptions for insert
  to authenticated
  with check (user_id = auth.uid());

-- reviews: publicas na pagina do restaurante.
create policy "avaliacoes sao publicas"
  on reviews for select
  to anon, authenticated
  using (app.restaurant_is_public(restaurant_id));

create policy "cliente avalia o proprio pedido"
  on reviews for insert
  to authenticated
  with check (
    customer_id = auth.uid()
    and exists (
      select 1 from orders o
      where o.id = order_id
        and o.customer_id = auth.uid()
        -- So avalia quem recebeu. Avaliacao de pedido nao entregue nao existe.
        and o.status = 'delivered'
    )
  );

create policy "cliente edita a propria avaliacao"
  on reviews for update
  to authenticated
  using (customer_id = auth.uid() or app.can_manage(restaurant_id) or app.is_platform_admin())
  with check (customer_id = auth.uid() or app.can_manage(restaurant_id) or app.is_platform_admin());

-- notifications
create policy "cliente le as proprias notificacoes"
  on notifications for select
  to authenticated
  using (user_id = auth.uid());

create policy "cliente marca as proprias notificacoes"
  on notifications for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- banners
create policy "banners vigentes sao publicos"
  on banners for select
  to anon, authenticated
  using (
    is_active
    and starts_at <= now()
    and (ends_at is null or ends_at > now())
  );

create policy "administrador edita banners"
  on banners for all
  to authenticated
  using (app.is_platform_admin() or (restaurant_id is not null and app.can_manage(restaurant_id)))
  with check (app.is_platform_admin() or (restaurant_id is not null and app.can_manage(restaurant_id)));

-- stock_movements
create policy "equipe le o proprio estoque"
  on stock_movements for select
  to authenticated
  using (app.is_member(restaurant_id) or app.is_platform_admin());

create policy "equipe movimenta o proprio estoque"
  on stock_movements for insert
  to authenticated
  with check (app.is_member(restaurant_id) or app.is_platform_admin());

-- platform_settings
create policy "configuracoes da plataforma sao legiveis"
  on platform_settings for select
  to anon, authenticated
  using (true);

create policy "administrador edita as configuracoes"
  on platform_settings for update
  to authenticated
  using (app.is_platform_admin())
  with check (app.is_platform_admin());
