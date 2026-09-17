-- =============================================================================
-- Tronvix Facil - Catalogo
-- Horario de funcionamento, formas de pagamento aceitas, categorias, produtos
-- e grupos de adicionais.
-- =============================================================================

-- Busca por nome de produto no app do cliente usa similaridade de trigramas.
create extension if not exists "pg_trgm";

-- -----------------------------------------------------------------------------
-- restaurant_hours - faixas de funcionamento por dia da semana
-- -----------------------------------------------------------------------------

create table restaurant_hours (
  id uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references restaurants (id) on delete cascade,
  -- 0 = domingo, 6 = sabado (mesma convencao de Date.getDay()).
  weekday smallint not null,
  opens_at time not null,
  closes_at time not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint restaurant_hours_weekday_range check (weekday between 0 and 6),
  -- closes_at menor que opens_at e valido de proposito: representa a
  -- madrugada, o caso de quem fecha as 03:00.
  constraint restaurant_hours_not_empty check (opens_at <> closes_at)
);

create index restaurant_hours_restaurant_idx on restaurant_hours (restaurant_id, weekday);

-- A mesma faixa nao entra duas vezes no mesmo dia. Sem isto, um clique duplo
-- na tela de configuracao criaria dois "11:00 as 23:00" na segunda-feira.
create unique index restaurant_hours_unique_idx
  on restaurant_hours (restaurant_id, weekday, opens_at, closes_at);

create trigger restaurant_hours_touch
  before update on restaurant_hours
  for each row execute function app.touch_updated_at();

-- -----------------------------------------------------------------------------
-- restaurant_payment_methods
-- -----------------------------------------------------------------------------

create table restaurant_payment_methods (
  restaurant_id uuid not null references restaurants (id) on delete cascade,
  method payment_method not null,
  timing payment_timing not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  primary key (restaurant_id, method, timing)
);

comment on table restaurant_payment_methods is
  'A mesma forma de pagamento pode valer online e na entrega com regras diferentes; por isso timing entra na chave.';

create trigger restaurant_payment_methods_touch
  before update on restaurant_payment_methods
  for each row execute function app.touch_updated_at();

-- -----------------------------------------------------------------------------
-- platform_categories - as categorias da home (Lanches, Pizzas, Acai...)
-- -----------------------------------------------------------------------------

create table platform_categories (
  id uuid primary key default gen_random_uuid(),
  slug citext not null unique,
  name text not null,
  icon text,
  image_url text,
  position int not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger platform_categories_touch
  before update on platform_categories
  for each row execute function app.touch_updated_at();

create table restaurant_platform_categories (
  restaurant_id uuid not null references restaurants (id) on delete cascade,
  category_id uuid not null references platform_categories (id) on delete cascade,
  primary key (restaurant_id, category_id)
);

-- -----------------------------------------------------------------------------
-- categories - as secoes do cardapio de cada estabelecimento
-- -----------------------------------------------------------------------------

create table categories (
  id uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references restaurants (id) on delete cascade,
  name text not null,
  description text,
  position int not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index categories_restaurant_idx
  on categories (restaurant_id, position)
  where deleted_at is null;

-- Dois "Lanches" no mesmo cardapio confundem o cliente e o operador.
create unique index categories_unique_name_idx
  on categories (restaurant_id, lower(name))
  where deleted_at is null;

create trigger categories_touch
  before update on categories
  for each row execute function app.touch_updated_at();

-- -----------------------------------------------------------------------------
-- products
-- -----------------------------------------------------------------------------

create table products (
  id uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references restaurants (id) on delete cascade,
  category_id uuid not null references categories (id) on delete restrict,

  name text not null,
  description text,
  image_url text,

  price_cents bigint not null,
  -- Preco promocional. Quando preenchido e valido, e ele que vale.
  promo_price_cents bigint,
  promo_starts_at timestamptz,
  promo_ends_at timestamptz,

  is_available boolean not null default true,
  is_featured boolean not null default false,
  position int not null default 0,

  serves_people int,
  prep_minutes int,

  -- Estoque simplificado: quando track_stock e falso, stock_quantity e
  -- ignorado e o produto nunca esgota sozinho.
  track_stock boolean not null default false,
  stock_quantity int not null default 0,

  sold_count int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,

  constraint products_price_positive check (price_cents > 0),
  constraint products_promo_valid check (
    promo_price_cents is null
    or (promo_price_cents > 0 and promo_price_cents < price_cents)
  ),
  constraint products_promo_window check (
    promo_starts_at is null
    or promo_ends_at is null
    or promo_ends_at > promo_starts_at
  ),
  constraint products_stock_non_negative check (stock_quantity >= 0)
);

comment on constraint products_promo_valid on products is
  'Promocao precisa ser menor que o preco cheio. "Promocao" mais cara que o normal e erro de cadastro, nao regra de negocio.';

create index products_restaurant_idx
  on products (restaurant_id, category_id, position)
  where deleted_at is null;

create index products_available_idx
  on products (restaurant_id)
  where is_available and deleted_at is null;

create index products_featured_idx
  on products (restaurant_id)
  where is_featured and is_available and deleted_at is null;

-- Busca por nome no app do cliente.
create index products_name_trgm_idx on products using gin (name gin_trgm_ops);

create trigger products_touch
  before update on products
  for each row execute function app.touch_updated_at();

-- A categoria tem de pertencer ao mesmo estabelecimento do produto. Sem esta
-- checagem, um cardapio poderia referenciar a secao de outra loja.
create or replace function app.guard_product_category()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid;
begin
  select restaurant_id into v_owner from categories where id = new.category_id;

  if v_owner is distinct from new.restaurant_id then
    raise exception 'A categoria pertence a outro estabelecimento.'
      using errcode = 'foreign_key_violation';
  end if;

  return new;
end;
$$;

create trigger products_guard_category
  before insert or update of category_id, restaurant_id on products
  for each row execute function app.guard_product_category();

-- -----------------------------------------------------------------------------
-- addon_groups / addons
-- -----------------------------------------------------------------------------

create table addon_groups (
  id uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references restaurants (id) on delete cascade,
  product_id uuid not null references products (id) on delete cascade,

  name text not null,
  description text,
  is_required boolean not null default false,
  min_select int not null default 0,
  max_select int not null default 1,
  position int not null default 0,
  is_active boolean not null default true,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,

  constraint addon_groups_select_range check (
    min_select >= 0
    and max_select >= 1
    and min_select <= max_select
  ),
  -- Obrigatorio significa exigir ao menos uma escolha. Um grupo "obrigatorio"
  -- com minimo zero nao obriga nada e so engana a tela.
  constraint addon_groups_required_consistent check (
    not is_required or min_select >= 1
  )
);

create index addon_groups_product_idx
  on addon_groups (product_id, position)
  where deleted_at is null;

create trigger addon_groups_touch
  before update on addon_groups
  for each row execute function app.touch_updated_at();

create table addons (
  id uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references restaurants (id) on delete cascade,
  group_id uuid not null references addon_groups (id) on delete cascade,

  name text not null,
  description text,
  price_cents bigint not null default 0,
  is_available boolean not null default true,
  position int not null default 0,
  max_quantity int not null default 1,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,

  constraint addons_price_non_negative check (price_cents >= 0),
  constraint addons_max_quantity_positive check (max_quantity >= 1)
);

create index addons_group_idx
  on addons (group_id, position)
  where deleted_at is null;

-- Dois adicionais com o mesmo nome no mesmo grupo confundem quem monta o
-- pedido: a tela mostraria duas linhas identicas com precos possivelmente
-- diferentes.
create unique index addons_unique_name_idx
  on addons (group_id, lower(name))
  where deleted_at is null;

create trigger addons_touch
  before update on addons
  for each row execute function app.touch_updated_at();

-- =============================================================================
-- RLS - catalogo
--
-- Padrao que se repete em todas as tabelas de cardapio:
--   leitura publica  -> so do que esta ativo, em estabelecimento aprovado
--   escrita          -> so cargo de gestao do proprio estabelecimento
-- =============================================================================

alter table restaurant_hours enable row level security;
alter table restaurant_payment_methods enable row level security;
alter table platform_categories enable row level security;
alter table restaurant_platform_categories enable row level security;
alter table categories enable row level security;
alter table products enable row level security;
alter table addon_groups enable row level security;
alter table addons enable row level security;

-- Restaurante aprovado e visivel? Repetido em varias politicas; virou funcao
-- para nao existirem duas versoes da mesma regra.
create or replace function app.restaurant_is_public(p_restaurant uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from restaurants r
    where r.id = p_restaurant
      and r.status = 'approved'
      and r.deleted_at is null
  );
$$;

-- restaurant_hours
create policy "horarios publicos"
  on restaurant_hours for select
  to anon, authenticated
  using (app.restaurant_is_public(restaurant_id));

create policy "equipe le horarios"
  on restaurant_hours for select
  to authenticated
  using (app.is_member(restaurant_id) or app.is_platform_admin());

create policy "gestao edita horarios"
  on restaurant_hours for all
  to authenticated
  using (app.can_manage(restaurant_id) or app.is_platform_admin())
  with check (app.can_manage(restaurant_id) or app.is_platform_admin());

-- restaurant_payment_methods
create policy "formas de pagamento publicas"
  on restaurant_payment_methods for select
  to anon, authenticated
  using (app.restaurant_is_public(restaurant_id) and is_active);

create policy "equipe le formas de pagamento"
  on restaurant_payment_methods for select
  to authenticated
  using (app.is_member(restaurant_id) or app.is_platform_admin());

create policy "gestao edita formas de pagamento"
  on restaurant_payment_methods for all
  to authenticated
  using (app.can_manage(restaurant_id) or app.is_platform_admin())
  with check (app.can_manage(restaurant_id) or app.is_platform_admin());

-- platform_categories
create policy "categorias da plataforma sao publicas"
  on platform_categories for select
  to anon, authenticated
  using (is_active or app.is_platform_admin());

create policy "administrador edita categorias da plataforma"
  on platform_categories for all
  to authenticated
  using (app.is_platform_admin())
  with check (app.is_platform_admin());

create policy "vinculo de categoria e publico"
  on restaurant_platform_categories for select
  to anon, authenticated
  using (true);

create policy "gestao vincula categorias"
  on restaurant_platform_categories for all
  to authenticated
  using (app.can_manage(restaurant_id) or app.is_platform_admin())
  with check (app.can_manage(restaurant_id) or app.is_platform_admin());

-- categories
create policy "cardapio publico"
  on categories for select
  to anon, authenticated
  using (is_active and deleted_at is null and app.restaurant_is_public(restaurant_id));

create policy "equipe le o proprio cardapio"
  on categories for select
  to authenticated
  using (app.is_member(restaurant_id) or app.is_platform_admin());

create policy "gestao edita o proprio cardapio"
  on categories for all
  to authenticated
  using (app.can_manage(restaurant_id) or app.is_platform_admin())
  with check (app.can_manage(restaurant_id) or app.is_platform_admin());

-- products
create policy "produtos publicos"
  on products for select
  to anon, authenticated
  using (deleted_at is null and app.restaurant_is_public(restaurant_id));

create policy "equipe le os proprios produtos"
  on products for select
  to authenticated
  using (app.is_member(restaurant_id) or app.is_platform_admin());

create policy "gestao edita os proprios produtos"
  on products for all
  to authenticated
  using (app.can_manage(restaurant_id) or app.is_platform_admin())
  with check (app.can_manage(restaurant_id) or app.is_platform_admin());

-- addon_groups
create policy "grupos de adicionais publicos"
  on addon_groups for select
  to anon, authenticated
  using (is_active and deleted_at is null and app.restaurant_is_public(restaurant_id));

create policy "equipe le os proprios grupos"
  on addon_groups for select
  to authenticated
  using (app.is_member(restaurant_id) or app.is_platform_admin());

create policy "gestao edita os proprios grupos"
  on addon_groups for all
  to authenticated
  using (app.can_manage(restaurant_id) or app.is_platform_admin())
  with check (app.can_manage(restaurant_id) or app.is_platform_admin());

-- addons
create policy "adicionais publicos"
  on addons for select
  to anon, authenticated
  using (deleted_at is null and app.restaurant_is_public(restaurant_id));

create policy "equipe le os proprios adicionais"
  on addons for select
  to authenticated
  using (app.is_member(restaurant_id) or app.is_platform_admin());

create policy "gestao edita os proprios adicionais"
  on addons for all
  to authenticated
  using (app.can_manage(restaurant_id) or app.is_platform_admin())
  with check (app.can_manage(restaurant_id) or app.is_platform_admin());
