-- =============================================================================
-- Tronvix Facil - Fundacao
--
-- Convencoes que valem para todas as migracoes deste projeto:
--
--   * Identificadores (tabelas, colunas, tipos) em ingles. Comentarios,
--     mensagens e o codigo da aplicacao em portugues.
--   * Dinheiro sempre em BIGINT de centavos, com sufixo _cents. Nunca float:
--     0.1 + 0.2 nao pode virar uma divergencia de caixa no fim do mes.
--   * Toda tabela tem created_at e updated_at; updated_at e mantido por
--     gatilho, nunca pela aplicacao.
--   * Exclusao logica (deleted_at) em tudo que um pedido antigo possa
--     referenciar. Apagar um produto nao pode apagar o historico de vendas.
--   * RLS ligada em TODAS as tabelas. O isolamento entre estabelecimentos e
--     responsabilidade do banco, nao de um WHERE que alguem pode esquecer.
-- =============================================================================

create extension if not exists "pgcrypto";
create extension if not exists "citext";

-- Schema separado para as funcoes de apoio da RLS: mantem o public limpo e
-- deixa claro o que e infraestrutura de seguranca e o que e dado do produto.
create schema if not exists app;

-- -----------------------------------------------------------------------------
-- Tipos
-- -----------------------------------------------------------------------------

-- Papel do usuario na plataforma. O papel dentro de um restaurante e outra
-- coisa e mora em restaurant_members: a mesma pessoa pode ser cliente da
-- plataforma e gerente de um estabelecimento.
create type platform_role as enum ('customer', 'courier', 'platform_admin');

create type restaurant_role as enum ('owner', 'manager', 'staff');

create type restaurant_status as enum ('pending', 'approved', 'suspended', 'rejected');

create type courier_status as enum ('pending', 'approved', 'suspended');

create type courier_availability as enum ('offline', 'online', 'on_delivery');

create type fulfillment_type as enum ('delivery', 'pickup');

create type order_status as enum (
  'awaiting_payment',
  'received',
  'confirmed',
  'preparing',
  'ready',
  'out_for_delivery',
  'delivered',
  'cancelled',
  'rejected'
);

create type payment_status as enum ('pending', 'paid', 'failed', 'refunded', 'cancelled');

create type payment_method as enum ('pix', 'credit_card', 'debit_card', 'cash', 'meal_voucher');

-- Onde o dinheiro e cobrado: no app (gateway) ou na porta do cliente.
create type payment_timing as enum ('online', 'on_delivery');

create type delivery_status as enum (
  'pending',
  'searching_courier',
  'assigned',
  'heading_to_restaurant',
  'picked_up',
  'heading_to_customer',
  'delivered',
  'cancelled'
);

create type discount_type as enum ('percentage', 'fixed', 'free_shipping');

create type coupon_scope as enum ('platform', 'restaurant');

create type stock_movement_type as enum ('in', 'out', 'adjustment');

-- -----------------------------------------------------------------------------
-- Gatilho de auditoria
-- -----------------------------------------------------------------------------

create or replace function app.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

comment on function app.touch_updated_at() is
  'Mantem updated_at. Aplicado por gatilho em toda tabela do projeto.';

-- -----------------------------------------------------------------------------
-- profiles - espelho de auth.users com os dados do produto
-- -----------------------------------------------------------------------------

create table profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text not null default '',
  email citext,
  phone text,
  avatar_url text,
  platform_role platform_role not null default 'customer',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint profiles_phone_format check (
    phone is null or phone ~ '^[0-9]{10,13}$'
  )
);

comment on table profiles is
  'Dados de produto do usuario. A credencial vive em auth.users; aqui fica quem a pessoa e.';

create index profiles_platform_role_idx on profiles (platform_role) where is_active;
create index profiles_email_idx on profiles (email);

create trigger profiles_touch
  before update on profiles
  for each row execute function app.touch_updated_at();

-- Todo usuario criado no Auth ganha um perfil na mesma transacao. Sem isso,
-- existe uma janela em que a pessoa esta autenticada mas nao tem papel, e
-- toda politica de RLS quebraria de forma silenciosa.
create or replace function app.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, email, phone, platform_role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    new.email,
    nullif(new.raw_user_meta_data ->> 'phone', ''),
    coalesce(
      (new.raw_user_meta_data ->> 'platform_role')::platform_role,
      'customer'
    )
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function app.handle_new_user();

-- -----------------------------------------------------------------------------
-- restaurants
-- -----------------------------------------------------------------------------

create table restaurants (
  id uuid primary key default gen_random_uuid(),
  slug citext not null unique,
  name text not null,
  legal_name text,
  document text,                              -- CNPJ, so digitos
  description text,
  logo_url text,
  cover_url text,
  phone text,
  email citext,

  status restaurant_status not null default 'pending',
  -- Chave manual de aberto/fechado. O horario de funcionamento
  -- (restaurant_hours) decide o resto: o estabelecimento so aceita pedido se
  -- as duas coisas concordarem.
  is_open boolean not null default false,
  accepts_scheduled_orders boolean not null default false,

  street text,
  number text,
  complement text,
  district text,
  city text,
  state char(2),
  postal_code text,
  latitude numeric(10, 7),
  longitude numeric(10, 7),

  delivery_fee_cents bigint not null default 0,
  free_delivery_above_cents bigint,
  min_order_cents bigint not null default 0,
  delivery_radius_km numeric(5, 2) not null default 5,
  avg_prep_minutes int not null default 30,
  avg_delivery_minutes int not null default 20,

  -- Comissao da plataforma em pontos base (1000 = 10,00%). Inteiro para nao
  -- arrastar imprecisao de ponto flutuante para o financeiro.
  commission_bps int not null default 1000,

  rating_avg numeric(3, 2) not null default 0,
  rating_count int not null default 0,

  approved_at timestamptz,
  approved_by uuid references profiles (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,

  constraint restaurants_money_non_negative check (
    delivery_fee_cents >= 0
    and min_order_cents >= 0
    and (free_delivery_above_cents is null or free_delivery_above_cents >= 0)
  ),
  constraint restaurants_commission_range check (commission_bps between 0 and 10000),
  constraint restaurants_prep_positive check (avg_prep_minutes > 0),
  constraint restaurants_document_digits check (document is null or document ~ '^[0-9]{14}$')
);

comment on column restaurants.commission_bps is
  'Comissao da plataforma em pontos base: 1000 = 10,00%. Inteiro de proposito.';

create index restaurants_status_idx on restaurants (status) where deleted_at is null;
create index restaurants_city_idx on restaurants (city, state) where deleted_at is null;
create index restaurants_open_idx on restaurants (status, is_open) where deleted_at is null;

create trigger restaurants_touch
  before update on restaurants
  for each row execute function app.touch_updated_at();

-- -----------------------------------------------------------------------------
-- restaurant_members - quem trabalha em qual estabelecimento
-- -----------------------------------------------------------------------------

create table restaurant_members (
  id uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references restaurants (id) on delete cascade,
  user_id uuid not null references profiles (id) on delete cascade,
  role restaurant_role not null default 'staff',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,

  unique (restaurant_id, user_id)
);

comment on table restaurant_members is
  'Tabela que sustenta o multi-tenant: e por ela que toda politica de RLS decide se a pessoa enxerga os dados de um estabelecimento.';

create index restaurant_members_user_idx on restaurant_members (user_id) where is_active;
create index restaurant_members_restaurant_idx on restaurant_members (restaurant_id) where is_active;

create trigger restaurant_members_touch
  before update on restaurant_members
  for each row execute function app.touch_updated_at();

-- -----------------------------------------------------------------------------
-- couriers
-- -----------------------------------------------------------------------------

create table couriers (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references profiles (id) on delete cascade,
  status courier_status not null default 'pending',
  availability courier_availability not null default 'offline',

  vehicle_type text not null default 'motorcycle',
  vehicle_plate text,
  document text,

  current_latitude numeric(10, 7),
  current_longitude numeric(10, 7),
  location_updated_at timestamptz,

  rating_avg numeric(3, 2) not null default 0,
  rating_count int not null default 0,
  deliveries_count int not null default 0,

  approved_at timestamptz,
  approved_by uuid references profiles (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index couriers_available_idx on couriers (status, availability) where deleted_at is null;

create trigger couriers_touch
  before update on couriers
  for each row execute function app.touch_updated_at();

-- -----------------------------------------------------------------------------
-- addresses - enderecos de entrega do cliente
-- -----------------------------------------------------------------------------

create table addresses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles (id) on delete cascade,
  label text not null default 'Casa',
  recipient text,
  street text not null,
  number text not null,
  complement text,
  district text not null,
  city text not null,
  state char(2) not null,
  postal_code text not null,
  reference_point text,
  latitude numeric(10, 7),
  longitude numeric(10, 7),
  is_default boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,

  constraint addresses_postal_code_digits check (postal_code ~ '^[0-9]{8}$')
);

create index addresses_user_idx on addresses (user_id) where deleted_at is null;

-- No maximo um endereco padrao por cliente. Garantido por indice, nao por
-- codigo: duas abas abertas nao conseguem criar dois padroes.
create unique index addresses_single_default_idx
  on addresses (user_id)
  where is_default and deleted_at is null;

create trigger addresses_touch
  before update on addresses
  for each row execute function app.touch_updated_at();

-- =============================================================================
-- Funcoes de apoio da RLS
--
-- Todas SECURITY DEFINER: precisam ler restaurant_members e profiles sem
-- disparar a propria RLS dessas tabelas, o que causaria recursao infinita.
-- Todas STABLE: o planejador pode avaliar uma vez por consulta em vez de uma
-- vez por linha - a diferenca aparece em listagens grandes de pedidos.
-- =============================================================================

create or replace function app.is_platform_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from profiles p
    where p.id = auth.uid()
      and p.platform_role = 'platform_admin'
      and p.is_active
  );
$$;

create or replace function app.is_member(p_restaurant uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from restaurant_members m
    where m.restaurant_id = p_restaurant
      and m.user_id = auth.uid()
      and m.is_active
      and m.deleted_at is null
  );
$$;

comment on function app.is_member(uuid) is
  'A pessoa trabalha neste estabelecimento? Base de toda leitura do painel do restaurante.';

create or replace function app.can_manage(p_restaurant uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from restaurant_members m
    where m.restaurant_id = p_restaurant
      and m.user_id = auth.uid()
      and m.role in ('owner', 'manager')
      and m.is_active
      and m.deleted_at is null
  );
$$;

comment on function app.can_manage(uuid) is
  'Cargo de gestao (proprietario ou gerente). Atendente ve pedidos, mas nao mexe em cardapio, financeiro ou equipe.';

create or replace function app.my_courier_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select c.id
  from couriers c
  where c.user_id = auth.uid()
    and c.deleted_at is null;
$$;

create or replace function app.is_approved_courier()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from couriers c
    where c.user_id = auth.uid()
      and c.status = 'approved'
      and c.deleted_at is null
  );
$$;

-- As funcoes de apoio nao sao API publica: quem chama e a RLS.
revoke all on schema app from public, anon, authenticated;
grant usage on schema app to authenticated, anon, service_role;

-- =============================================================================
-- RLS - fundacao
-- =============================================================================

alter table profiles enable row level security;
alter table restaurants enable row level security;
alter table restaurant_members enable row level security;
alter table couriers enable row level security;
alter table addresses enable row level security;

-- profiles ---------------------------------------------------------------
create policy "perfil proprio visivel"
  on profiles for select
  using (id = auth.uid() or app.is_platform_admin());

create policy "perfil proprio editavel"
  on profiles for update
  using (id = auth.uid() or app.is_platform_admin())
  with check (id = auth.uid() or app.is_platform_admin());

-- O papel na plataforma nao se auto-promove. Trocar platform_role e
-- privilegio de administrador; o cliente nao vira admin editando o proprio
-- perfil.
create or replace function app.guard_platform_role()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.platform_role is distinct from old.platform_role
     and not app.is_platform_admin() then
    raise exception 'Alterar o papel na plataforma e exclusivo do administrador.'
      using errcode = 'insufficient_privilege';
  end if;
  return new;
end;
$$;

create trigger profiles_guard_role
  before update on profiles
  for each row execute function app.guard_platform_role();

-- restaurants ------------------------------------------------------------
-- A vitrine e publica: o app do cliente lista estabelecimentos aprovados sem
-- exigir login. O que nao esta aprovado so aparece para quem trabalha nele.
create policy "vitrine publica de restaurantes aprovados"
  on restaurants for select
  to anon, authenticated
  using (status = 'approved' and deleted_at is null);

create policy "equipe ve o proprio restaurante"
  on restaurants for select
  to authenticated
  using (app.is_member(id) or app.is_platform_admin());

create policy "gestao edita o proprio restaurante"
  on restaurants for update
  to authenticated
  using (app.can_manage(id) or app.is_platform_admin())
  with check (app.can_manage(id) or app.is_platform_admin());

create policy "administrador cadastra restaurante"
  on restaurants for insert
  to authenticated
  with check (app.is_platform_admin());

create policy "administrador remove restaurante"
  on restaurants for delete
  to authenticated
  using (app.is_platform_admin());

-- Aprovacao, suspensao e comissao sao decisoes da plataforma. Um dono de
-- restaurante nao aprova o proprio cadastro nem baixa a propria comissao.
create or replace function app.guard_restaurant_platform_fields()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Atualizacao vinda de outro gatilho (a media de avaliacoes, por exemplo)
  -- e do proprio banco, nao de um cliente. pg_trigger_depth() > 1 identifica
  -- esse caso e nao e falsificavel pela API: uma chamada direta do cliente
  -- sempre entra com profundidade 1.
  if pg_trigger_depth() > 1 then
    return new;
  end if;

  if not app.is_platform_admin() then
    if new.status is distinct from old.status then
      raise exception 'Somente a plataforma altera a situacao do estabelecimento.'
        using errcode = 'insufficient_privilege';
    end if;
    if new.commission_bps is distinct from old.commission_bps then
      raise exception 'Somente a plataforma altera a comissao.'
        using errcode = 'insufficient_privilege';
    end if;
    -- Reputacao e consequencia das avaliacoes, nunca campo editavel.
    new.rating_avg := old.rating_avg;
    new.rating_count := old.rating_count;
  end if;
  return new;
end;
$$;

create trigger restaurants_guard_platform_fields
  before update on restaurants
  for each row execute function app.guard_restaurant_platform_fields();

-- restaurant_members -----------------------------------------------------
create policy "equipe se enxerga"
  on restaurant_members for select
  to authenticated
  using (
    user_id = auth.uid()
    or app.is_member(restaurant_id)
    or app.is_platform_admin()
  );

create policy "gestao cadastra equipe"
  on restaurant_members for insert
  to authenticated
  with check (app.can_manage(restaurant_id) or app.is_platform_admin());

create policy "gestao edita equipe"
  on restaurant_members for update
  to authenticated
  using (app.can_manage(restaurant_id) or app.is_platform_admin())
  with check (app.can_manage(restaurant_id) or app.is_platform_admin());

create policy "gestao remove equipe"
  on restaurant_members for delete
  to authenticated
  using (app.can_manage(restaurant_id) or app.is_platform_admin());

-- O ultimo proprietario nao pode ser removido nem rebaixado: um
-- estabelecimento sem dono fica inacessivel para sempre.
create or replace function app.guard_last_owner()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_restaurant uuid := coalesce(old.restaurant_id, new.restaurant_id);
  v_owners int;
  v_was_owner boolean := old.role = 'owner' and old.is_active and old.deleted_at is null;
  v_still_owner boolean := tg_op = 'UPDATE'
    and new.role = 'owner' and new.is_active and new.deleted_at is null;
begin
  if not v_was_owner or v_still_owner then
    return coalesce(new, old);
  end if;

  select count(*) into v_owners
  from restaurant_members m
  where m.restaurant_id = v_restaurant
    and m.role = 'owner'
    and m.is_active
    and m.deleted_at is null;

  if v_owners <= 1 then
    raise exception 'O estabelecimento precisa de ao menos um proprietario ativo.'
      using errcode = 'check_violation';
  end if;

  return coalesce(new, old);
end;
$$;

create trigger restaurant_members_guard_last_owner
  before update or delete on restaurant_members
  for each row execute function app.guard_last_owner();

-- couriers ---------------------------------------------------------------
create policy "entregador ve o proprio cadastro"
  on couriers for select
  to authenticated
  using (user_id = auth.uid() or app.is_platform_admin());

create policy "entregador se cadastra"
  on couriers for insert
  to authenticated
  with check (user_id = auth.uid() or app.is_platform_admin());

create policy "entregador edita o proprio cadastro"
  on couriers for update
  to authenticated
  using (user_id = auth.uid() or app.is_platform_admin())
  with check (user_id = auth.uid() or app.is_platform_admin());

-- Aprovacao e reputacao do entregador tambem sao da plataforma.
create or replace function app.guard_courier_platform_fields()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Mesma razao do guarda de restaurants: o recalculo de reputacao chega por
  -- gatilho, nao por chamada de cliente.
  if pg_trigger_depth() > 1 then
    return new;
  end if;

  if not app.is_platform_admin() then
    if new.status is distinct from old.status then
      raise exception 'Somente a plataforma aprova ou suspende um entregador.'
        using errcode = 'insufficient_privilege';
    end if;
    new.rating_avg := old.rating_avg;
    new.rating_count := old.rating_count;
    new.deliveries_count := old.deliveries_count;
  end if;

  -- Ficar online exige cadastro aprovado.
  if new.availability <> 'offline' and new.status <> 'approved' then
    raise exception 'Entregador ainda nao aprovado nao pode ficar disponivel.'
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

create trigger couriers_guard_platform_fields
  before update on couriers
  for each row execute function app.guard_courier_platform_fields();

-- addresses --------------------------------------------------------------
create policy "cliente gerencia os proprios enderecos"
  on addresses for all
  to authenticated
  using (user_id = auth.uid() or app.is_platform_admin())
  with check (user_id = auth.uid() or app.is_platform_admin());
