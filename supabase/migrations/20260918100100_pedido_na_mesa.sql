-- =============================================================================
-- Mesas, QR, e o pedido que nasce sentado.
--
-- O que muda em relacao aos outros dois tipos:
--
--   entrega   exige endereco, cobra frete, cria corrida, termina na porta
--   retirada  nao exige nada, nao cobra frete, termina no balcao
--   mesa      exige MESA, nao cobra frete, nao cria corrida, termina servido
--
-- O QR nao leva o numero da mesa: leva um codigo sorteado. Numero de mesa e
-- adivinhavel, e "pedido para a mesa 7" feito de casa, as duas da manha, e uma
-- brincadeira que o restaurante paga. O codigo tambem permite reimprimir a
-- etiqueta de uma mesa sem invalidar as outras.
--
-- O que NAO foi feito aqui, e por que: nao ha entidade "comanda". Uma mesa
-- acumula varios pedidos - entrada, bebida, sobremesa - e o balcao os agrupa
-- pela mesa na hora de fechar a conta. Criar uma tabela de comanda com
-- abertura, fechamento e transferencia e outro produto; agrupar por mesa
-- resolve o caso real com o que ja existe.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- As mesas
-- -----------------------------------------------------------------------------
create table if not exists restaurant_tables (
  id uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references restaurants (id) on delete cascade,

  -- O que esta escrito na etiqueta: "Mesa 7", "Varanda 2", "Balcao".
  label text not null,

  -- O que vai na URL do QR. Sorteado, nunca o numero da mesa.
  code text not null,

  seats int,
  is_active boolean not null default true,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,

  constraint restaurant_tables_label_not_empty check (length(trim(label)) > 0),
  constraint restaurant_tables_code_format check (code ~ '^[a-z0-9]{6,16}$'),
  constraint restaurant_tables_seats_positive check (seats is null or seats > 0)
);

-- O codigo e unico no sistema inteiro, nao so no estabelecimento: a URL do QR
-- nao diz de qual loja e, e dois codigos iguais em lojas diferentes tornariam
-- a leitura ambigua.
create unique index if not exists restaurant_tables_code_idx
  on restaurant_tables (code) where deleted_at is null;

create unique index if not exists restaurant_tables_label_idx
  on restaurant_tables (restaurant_id, lower(label)) where deleted_at is null;

create index if not exists restaurant_tables_restaurant_idx
  on restaurant_tables (restaurant_id) where deleted_at is null;

create trigger restaurant_tables_touch
  before update on restaurant_tables
  for each row execute function app.touch_updated_at();

alter table restaurant_tables enable row level security;

-- Quem cuida das mesas e a gestao da loja.
create policy "gestao cuida das mesas"
  on restaurant_tables for all
  to authenticated
  using (app.can_manage(restaurant_id) or app.is_platform_admin())
  with check (app.can_manage(restaurant_id) or app.is_platform_admin());

-- E o cliente sentado precisa ler a mesa que escaneou - so as ativas, e so os
-- campos que a tela usa. Sem isto, ler o QR nao levaria a lugar nenhum.
create policy "quem escaneia ve a mesa"
  on restaurant_tables for select
  to authenticated, anon
  using (is_active and deleted_at is null);

-- -----------------------------------------------------------------------------
-- O pedido guarda a mesa
-- -----------------------------------------------------------------------------
alter table orders
  add column if not exists table_id uuid references restaurant_tables (id) on delete set null,
  -- Rotulo copiado, como o endereco. A mesa pode ser renomeada ou removida
  -- amanha; o pedido de hoje precisa continuar dizendo onde foi servido.
  add column if not exists table_label text;

create index if not exists orders_table_idx
  on orders (table_id, created_at desc) where table_id is not null;

-- Mesa exige mesa, como entrega exige endereco.
alter table orders drop constraint if exists orders_dine_in_needs_table;
alter table orders add constraint orders_dine_in_needs_table check (
  fulfillment <> 'dine_in'
  or status in ('awaiting_payment', 'cancelled', 'rejected')
  or table_label is not null
);

-- Frete e coisa de rua. Cobrar entrega de quem esta sentado na mesa e um erro
-- que o banco deve recusar, nao um que a tela deve lembrar de evitar.
alter table orders drop constraint if exists orders_no_fee_off_street;
alter table orders add constraint orders_no_fee_off_street check (
  fulfillment = 'delivery' or delivery_fee_cents = 0
);

-- -----------------------------------------------------------------------------
-- Sortear o codigo do QR
-- -----------------------------------------------------------------------------
create or replace function app.codigo_de_mesa()
returns text
language plpgsql
as $$
declare
  -- Sem i, l, o, 0 e 1: o codigo aparece impresso embaixo do QR, e alguem vai
  -- acabar digitando a mao quando a camera nao ler.
  v_alfabeto text := 'abcdefghjkmnpqrstuvwxyz23456789';
  v_codigo text;
  v_tentativa int := 0;
begin
  loop
    v_codigo := '';
    for _ in 1..8 loop
      v_codigo := v_codigo || substr(v_alfabeto, 1 + floor(random() * length(v_alfabeto))::int, 1);
    end loop;

    exit when not exists (
      select 1 from restaurant_tables t where t.code = v_codigo and t.deleted_at is null
    );

    v_tentativa := v_tentativa + 1;
    if v_tentativa > 50 then
      raise exception 'Nao consegui sortear um codigo de mesa.' using errcode = 'internal_error';
    end if;
  end loop;

  return v_codigo;
end;
$$;

-- -----------------------------------------------------------------------------
-- Criar mesas em lote
-- -----------------------------------------------------------------------------
-- Ninguem cadastra vinte mesas uma a uma. O caso real e "tenho 20 mesas":
-- cria-se de 1 a 20 de uma vez, e depois se renomeia as poucas que tem nome.
create or replace function public.criar_mesas(
  p_restaurante uuid,
  p_quantidade int,
  p_prefixo text default 'Mesa'
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_criadas int := 0;
  v_proxima int;
  v_rotulo text;
begin
  if not (app.can_manage(p_restaurante) or app.is_platform_admin()) then
    raise exception 'Somente a gestao do estabelecimento cria mesas.'
      using errcode = 'insufficient_privilege';
  end if;

  if p_quantidade is null or p_quantidade < 1 or p_quantidade > 200 then
    raise exception 'A quantidade vai de 1 a 200.' using errcode = 'check_violation';
  end if;

  -- Continua de onde parou: quem ja tem "Mesa 8" e pede mais 4 recebe da 9 a 12.
  select coalesce(max(substring(label from '\d+$')::int), 0) + 1
    into v_proxima
    from restaurant_tables
   where restaurant_id = p_restaurante
     and deleted_at is null
     and label ~ ('^' || p_prefixo || ' \d+$');

  for _ in 1..p_quantidade loop
    v_rotulo := p_prefixo || ' ' || v_proxima;

    insert into restaurant_tables (restaurant_id, label, code)
    values (p_restaurante, v_rotulo, app.codigo_de_mesa())
    on conflict do nothing;

    if found then v_criadas := v_criadas + 1; end if;
    v_proxima := v_proxima + 1;
  end loop;

  return v_criadas;
end;
$$;

revoke all on function public.criar_mesas(uuid, int, text) from public;
grant execute on function public.criar_mesas(uuid, int, text) to authenticated;

comment on function public.criar_mesas is
  'Cria mesas numeradas em lote, continuando da ultima. O codigo do QR e sorteado.';
