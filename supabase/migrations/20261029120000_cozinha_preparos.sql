-- =============================================================================
-- Tronvix Facil - cozinha: o livro de preparos
--
-- O que a cozinha produz antes do pedido chegar: o molho do dia, a massa, o
-- recheio. Cada lancamento diz quando foi feito, o que foi feito, para qual
-- prato e com quais ingredientes - e e por esses mesmos campos que a loja
-- procura depois ("quando fizemos o molho com aquele lote de tomate?").
--
--   kitchen_preps              o preparo: numero da loja, data, nome, prato
--   kitchen_prep_ingredients   os ingredientes de cada preparo
--   lancar_preparo             grava o preparo e os ingredientes juntos
--   buscar_preparos            procura por data, numero, preparo, prato e
--                              ingrediente, sem ligar para acento
--
-- O prato guarda o nome, e o produto do cardapio so quando ha um. O livro e
-- historico: renomear ou apagar o produto amanha nao pode reescrever o que a
-- cozinha fez ontem.
--
-- Nao mexe no estoque. O saldo de `products` e de unidade vendavel (lata,
-- porcao), e ingrediente de preparo se mede em quilo e litro.
-- =============================================================================

create table if not exists kitchen_prep_counters (
  restaurant_id uuid primary key references restaurants (id) on delete cascade,
  last_number int not null default 0
);

alter table kitchen_prep_counters enable row level security;

create table if not exists kitchen_preps (
  id uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references restaurants (id) on delete cascade,
  number int not null,
  prep_date date not null,
  name text not null check (length(btrim(name)) between 1 and 120),
  product_id uuid references products (id) on delete set null,
  product_name text not null check (length(btrim(product_name)) between 1 and 120),
  notes text check (notes is null or length(notes) <= 500),
  created_by uuid references profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  unique (restaurant_id, number)
);

create index if not exists kitchen_preps_restaurant_date_idx
  on kitchen_preps (restaurant_id, prep_date desc, number desc);

comment on table kitchen_preps is
  'Livro de preparos da cozinha. Numero sequencial por loja; o nome do prato e guardado como foi lancado.';

create table if not exists kitchen_prep_ingredients (
  id uuid primary key default gen_random_uuid(),
  prep_id uuid not null references kitchen_preps (id) on delete cascade,
  name text not null check (length(btrim(name)) between 1 and 120),
  quantity numeric(12, 3) check (quantity is null or quantity > 0),
  unit text check (unit is null or length(unit) <= 20),
  position int not null default 0
);

create index if not exists kitchen_prep_ingredients_prep_idx
  on kitchen_prep_ingredients (prep_id, position);

alter table kitchen_preps enable row level security;
alter table kitchen_prep_ingredients enable row level security;

-- Toda a equipe le e lanca: quem faz o preparo e a cozinha, nao a gerencia.
-- Apagar e da gestao - o livro so vale se ninguem some com a linha do erro.
-- Nao ha politica de INSERT/UPDATE: o lancamento entra pela funcao.
drop policy if exists "equipe ve os preparos" on kitchen_preps;
create policy "equipe ve os preparos"
  on kitchen_preps for select
  to authenticated
  using (app.is_member(restaurant_id) or app.is_platform_admin());

drop policy if exists "gestao apaga preparo" on kitchen_preps;
create policy "gestao apaga preparo"
  on kitchen_preps for delete
  to authenticated
  using (app.can_manage(restaurant_id) or app.is_platform_admin());

drop policy if exists "equipe ve os ingredientes" on kitchen_prep_ingredients;
create policy "equipe ve os ingredientes"
  on kitchen_prep_ingredients for select
  to authenticated
  using (
    exists (
      select 1 from kitchen_preps p
       where p.id = prep_id
         and (app.is_member(p.restaurant_id) or app.is_platform_admin())
    )
  );

-- -----------------------------------------------------------------------------
-- O lancamento
-- -----------------------------------------------------------------------------

create or replace function public.lancar_preparo(
  p_restaurante uuid,
  p_data date,
  p_nome text,
  p_prato text,
  p_ingredientes jsonb,       -- [{"nome": text, "quantidade": numeric|null, "unidade": text|null}, ...]
  p_observacao text default null
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item jsonb;
  v_numero int;
  v_preparo uuid;
  v_produto uuid;
  v_nome text := btrim(coalesce(p_nome, ''));
  v_prato text := btrim(coalesce(p_prato, ''));
  v_ingrediente text;
  v_quantidade numeric;
  v_posicao int := 0;
begin
  if not (app.is_member(p_restaurante) or app.is_platform_admin()) then
    raise exception 'Somente a equipe da loja lanca preparo.'
      using errcode = 'insufficient_privilege';
  end if;

  if p_data is null or p_data > current_date + 1 or p_data < current_date - 366 then
    raise exception 'Data invalida: use uma data do ultimo ano ate amanha.'
      using errcode = 'check_violation';
  end if;

  if length(v_nome) not between 1 and 120 then
    raise exception 'Informe o nome do preparo.' using errcode = 'check_violation';
  end if;

  if length(v_prato) not between 1 and 120 then
    raise exception 'Informe o nome do prato.' using errcode = 'check_violation';
  end if;

  if jsonb_typeof(p_ingredientes) is distinct from 'array'
     or jsonb_array_length(p_ingredientes) = 0 then
    raise exception 'O preparo precisa de ao menos um ingrediente.'
      using errcode = 'check_violation';
  end if;

  if jsonb_array_length(p_ingredientes) > 100 then
    raise exception 'No maximo 100 ingredientes por preparo.' using errcode = 'check_violation';
  end if;

  -- O produto do cardapio, quando o nome bate. Sem acento e sem caixa: quem
  -- digita "file a parmegiana" quer o "Filé à Parmegiana".
  select id into v_produto
    from products
   where restaurant_id = p_restaurante
     and deleted_at is null
     and app.sem_acento(name) = app.sem_acento(v_prato)
   limit 1;

  -- Mesmo contador de pedidos: UPSERT trava a linha, numero nunca repete.
  insert into kitchen_prep_counters (restaurant_id, last_number)
  values (p_restaurante, 1)
  on conflict (restaurant_id)
    do update set last_number = kitchen_prep_counters.last_number + 1
  returning last_number into v_numero;

  insert into kitchen_preps (
    restaurant_id, number, prep_date, name, product_id, product_name, notes, created_by
  )
  values (
    p_restaurante, v_numero, p_data, v_nome, v_produto,
    coalesce((select name from products where id = v_produto), v_prato),
    nullif(left(btrim(coalesce(p_observacao, '')), 500), ''),
    auth.uid()
  )
  returning id into v_preparo;

  for v_item in select * from jsonb_array_elements(p_ingredientes)
  loop
    v_ingrediente := btrim(coalesce(v_item ->> 'nome', ''));
    if length(v_ingrediente) not between 1 and 120 then
      raise exception 'Todo ingrediente precisa de nome.' using errcode = 'check_violation';
    end if;

    begin
      v_quantidade := nullif(v_item ->> 'quantidade', '')::numeric;
    exception when others then
      raise exception 'Quantidade invalida em %.', v_ingrediente using errcode = 'check_violation';
    end;

    if v_quantidade is not null and (v_quantidade <= 0 or v_quantidade > 1000000) then
      raise exception 'Quantidade invalida em %.', v_ingrediente using errcode = 'check_violation';
    end if;

    insert into kitchen_prep_ingredients (prep_id, name, quantity, unit, position)
    values (
      v_preparo, v_ingrediente, v_quantidade,
      nullif(left(btrim(coalesce(v_item ->> 'unidade', '')), 20), ''),
      v_posicao
    );
    v_posicao := v_posicao + 1;
  end loop;

  return v_numero;
end;
$$;

revoke all on function public.lancar_preparo(uuid, date, text, text, jsonb, text) from public;
grant execute on function public.lancar_preparo(uuid, date, text, text, jsonb, text) to authenticated;

comment on function public.lancar_preparo is
  'A equipe lanca um preparo da cozinha com seus ingredientes. Tudo ou nada; devolve o numero do preparo na loja.';

-- -----------------------------------------------------------------------------
-- A busca
-- -----------------------------------------------------------------------------

-- Security invoker de proposito: quem filtra e a RLS de kitchen_preps, e esta
-- funcao so junta os criterios. Sem acento e sem caixa, como a busca da
-- vitrine: "pure de batata" acha o "Purê de Batata".
create or replace function public.buscar_preparos(
  p_restaurante uuid,
  p_de date default null,
  p_ate date default null,
  p_numero int default null,
  p_preparo text default null,
  p_prato text default null,
  p_ingrediente text default null
)
returns setof kitchen_preps
language sql
stable
set search_path = public
as $$
  select p.*
    from kitchen_preps p
   where p.restaurant_id = p_restaurante
     and (p_de is null or p.prep_date >= p_de)
     and (p_ate is null or p.prep_date <= p_ate)
     and (p_numero is null or p.number = p_numero)
     and (coalesce(btrim(p_preparo), '') = ''
          or app.sem_acento(p.name) like '%' || app.sem_acento(btrim(p_preparo)) || '%')
     and (coalesce(btrim(p_prato), '') = ''
          or app.sem_acento(p.product_name) like '%' || app.sem_acento(btrim(p_prato)) || '%')
     and (coalesce(btrim(p_ingrediente), '') = ''
          or exists (
            select 1 from kitchen_prep_ingredients i
             where i.prep_id = p.id
               and app.sem_acento(i.name) like '%' || app.sem_acento(btrim(p_ingrediente)) || '%'
          ))
   order by p.prep_date desc, p.number desc
   limit 200;
$$;

grant execute on function public.buscar_preparos(uuid, date, date, int, text, text, text) to authenticated;
