-- =============================================================================
-- Tronvix Facil - clientes cadastrados pela loja
--
-- Ate aqui a loja so conhecia o cliente pelos pedidos: quem pediu pelo
-- aplicativo tinha conta, e quem ligava ou passava no balcao virava um nome
-- solto em `orders.customer_name`. O dono do restaurante de bairro conhece o
-- freguês - o "seu Joao do 302", que pede toda sexta pelo telefone - e quer
-- deixar anotado: nome, telefone, endereco, o que costuma pedir.
--
-- Este e o caderno da LOJA, e nao a conta do cliente. Cada loja tem o seu, e
-- nenhuma ve o da outra. A conta do aplicativo (`profiles`) continua sendo do
-- proprio cliente; aqui nada a substitui nem a altera.
--
-- O telefone guarda so os digitos, como `lancar_pedido` ja grava em
-- `orders.customer_phone`: e por ele que o cliente cadastrado se encontra com
-- os pedidos que fez.
-- =============================================================================

create table restaurant_customers (
  id uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references restaurants (id) on delete cascade,
  name text not null,
  phone text,
  address_street text,
  address_number text,
  address_complement text,
  address_district text,
  address_city text,
  notes text,
  -- Quem cadastrou: o banco preenche com quem esta logado.
  created_by uuid default auth.uid() references profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,

  constraint restaurant_customers_name_size check (length(btrim(name)) between 1 and 120),
  constraint restaurant_customers_phone_digits check (phone is null or phone ~ '^\d{10,13}$'),
  constraint restaurant_customers_notes_size check (notes is null or length(notes) <= 500)
);

create index restaurant_customers_restaurant_idx
  on restaurant_customers (restaurant_id, name)
  where deleted_at is null;

-- O mesmo telefone duas vezes na mesma loja e o mesmo cliente cadastrado duas
-- vezes: as contas dele se dividiriam entre as duas fichas.
create unique index restaurant_customers_phone_idx
  on restaurant_customers (restaurant_id, phone)
  where phone is not null and deleted_at is null;

comment on table restaurant_customers is
  'O caderno de clientes de cada loja: quem ela atende pelo telefone e pelo balcao. Nao e a conta do cliente no aplicativo.';

create trigger restaurant_customers_updated_at
  before update on restaurant_customers
  for each row execute function app.touch_updated_at();

alter table restaurant_customers enable row level security;

-- Sem delete: tirar e marcar `deleted_at` (veja abaixo).
grant select, insert, update on restaurant_customers to authenticated;

-- A equipe inteira le: quem atende o telefone precisa achar o cliente. Quem
-- cadastra, corrige e tira e a gestao, como o resto do cadastro da loja.
create policy "equipe ve os clientes da loja"
  on restaurant_customers for select
  to authenticated
  using (app.is_member(restaurant_id) or app.is_platform_admin());

create policy "gestao cadastra clientes"
  on restaurant_customers for insert
  to authenticated
  with check (app.can_manage(restaurant_id) or app.is_platform_admin());

create policy "gestao corrige clientes"
  on restaurant_customers for update
  to authenticated
  using (app.can_manage(restaurant_id) or app.is_platform_admin())
  with check (app.can_manage(restaurant_id) or app.is_platform_admin());

-- Sem politica de delete: tirar o cliente e marcar `deleted_at`. A ficha some
-- da lista, e os pedidos que ele fez continuam inteiros.
