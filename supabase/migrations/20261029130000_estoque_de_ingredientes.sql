-- =============================================================================
-- Tronvix Facil - estoque de ingredientes
--
-- O estoque de `products` conta unidade vendavel (a lata, a porcao). A cozinha
-- gasta outra coisa: quilo de tomate, litro de leite. Este e o livro dela.
--
--   ingredients               o cadastro: nome, unidade e saldo
--   ingredient_movements      o livro: cada entrada e cada saida, com origem
--   product_ingredients       a ficha tecnica: quanto de cada ingrediente um
--                             produto do cardapio gasta por unidade vendida
--
-- O saldo so anda pelo livro, e o livro so e escrito por funcao do banco:
--
--   manual    entrada (mercadoria que chegou) e saida (perda, uso avulso)
--   prep      o preparo lancado na cozinha gasta os ingredientes dele
--   order     o pedido que fica pronto gasta a ficha tecnica de cada item
--
-- Saldo negativo e permitido de proposito. A cozinha nao pode parar porque a
-- contagem esta errada: a saida entra, o ingrediente fica vermelho na tela, e
-- a gestao corrige com uma entrada.
-- =============================================================================

create table if not exists ingredients (
  id uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references restaurants (id) on delete cascade,
  name text not null check (length(btrim(name)) between 1 and 120),
  unit text not null check (unit in ('kg', 'g', 'L', 'ml', 'un')),
  stock_quantity numeric(14, 3) not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

-- "Tomate" e "tomate" sao o mesmo ingrediente. Dois cadastros dividiriam o
-- saldo em dois, e nenhum dos dois estaria certo.
create unique index if not exists ingredients_name_unique
  on ingredients (restaurant_id, app.sem_acento(name))
  where deleted_at is null;

drop trigger if exists ingredients_touch on ingredients;
create trigger ingredients_touch
  before update on ingredients
  for each row execute function app.touch_updated_at();

comment on table ingredients is
  'Ingredientes da cozinha, com unidade e saldo. O saldo so muda pelas funcoes que escrevem em ingredient_movements.';

create table if not exists ingredient_movements (
  id uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references restaurants (id) on delete cascade,
  ingredient_id uuid not null references ingredients (id) on delete cascade,
  kind text not null check (kind in ('in', 'out')),
  source text not null check (source in ('manual', 'prep', 'order')),
  quantity numeric(14, 3) not null check (quantity > 0),
  balance_after numeric(14, 3) not null,
  prep_id uuid references kitchen_preps (id) on delete set null,
  order_id uuid references orders (id) on delete set null,
  reason text check (reason is null or length(reason) <= 200),
  created_by uuid references profiles (id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists ingredient_movements_restaurant_idx
  on ingredient_movements (restaurant_id, created_at desc);
create index if not exists ingredient_movements_ingredient_idx
  on ingredient_movements (ingredient_id, created_at desc);
create index if not exists ingredient_movements_order_idx
  on ingredient_movements (order_id) where order_id is not null;

create table if not exists product_ingredients (
  product_id uuid not null references products (id) on delete cascade,
  ingredient_id uuid not null references ingredients (id) on delete cascade,
  quantity numeric(14, 3) not null check (quantity > 0),
  primary key (product_id, ingredient_id)
);

comment on table product_ingredients is
  'Ficha tecnica: quanto de cada ingrediente uma unidade do produto gasta. Vira saida quando o pedido fica pronto.';

-- O preparo passa a apontar para o ingrediente do estoque. Os lancados antes
-- desta migracao ficam com o nome que tinham e sem ligacao.
alter table kitchen_prep_ingredients
  add column if not exists ingredient_id uuid references ingredients (id) on delete set null;

alter table ingredients enable row level security;
alter table ingredient_movements enable row level security;
alter table product_ingredients enable row level security;

-- A equipe le (a cozinha precisa ver o que tem). Escrita, so pelas funcoes.
drop policy if exists "equipe ve os ingredientes do estoque" on ingredients;
create policy "equipe ve os ingredientes do estoque"
  on ingredients for select
  to authenticated
  using (app.is_member(restaurant_id) or app.is_platform_admin());

drop policy if exists "equipe ve o livro de ingredientes" on ingredient_movements;
create policy "equipe ve o livro de ingredientes"
  on ingredient_movements for select
  to authenticated
  using (app.is_member(restaurant_id) or app.is_platform_admin());

drop policy if exists "equipe ve a ficha tecnica" on product_ingredients;
create policy "equipe ve a ficha tecnica"
  on product_ingredients for select
  to authenticated
  using (
    exists (
      select 1 from products p
       where p.id = product_id
         and (app.is_member(p.restaurant_id) or app.is_platform_admin())
    )
  );

-- -----------------------------------------------------------------------------
-- O livro: a unica porta do saldo
-- -----------------------------------------------------------------------------

create or replace function app.movimentar_ingrediente(
  p_ingrediente uuid,
  p_tipo text,
  p_origem text,
  p_quantidade numeric,
  p_preparo uuid default null,
  p_pedido uuid default null,
  p_motivo text default null
)
returns numeric
language plpgsql
security definer
set search_path = public
as $$
declare
  v_restaurante uuid;
  v_saldo numeric;
begin
  update ingredients
     set stock_quantity = stock_quantity
                          + case when p_tipo = 'in' then p_quantidade else -p_quantidade end
   where id = p_ingrediente
  returning restaurant_id, stock_quantity into v_restaurante, v_saldo;

  insert into ingredient_movements (
    restaurant_id, ingredient_id, kind, source, quantity, balance_after,
    prep_id, order_id, reason, created_by
  )
  values (
    v_restaurante, p_ingrediente, p_tipo, p_origem, p_quantidade, v_saldo,
    p_preparo, p_pedido, nullif(left(btrim(coalesce(p_motivo, '')), 200), ''), auth.uid()
  );

  return v_saldo;
end;
$$;

revoke all on function app.movimentar_ingrediente(uuid, text, text, numeric, uuid, uuid, text) from public;

-- Quantidade de ingrediente: positiva, com ate tres casas, e sem exagero.
create or replace function app.quantidade_de_ingrediente(p_valor text, p_contexto text)
returns numeric
language plpgsql
immutable
as $$
declare
  v numeric;
begin
  begin
    v := nullif(btrim(coalesce(p_valor, '')), '')::numeric;
  exception when others then
    v := null;
  end;
  if v is null or v <= 0 or v > 1000000 then
    raise exception 'Quantidade invalida em %.', p_contexto using errcode = 'check_violation';
  end if;
  return round(v, 3);
end;
$$;

-- -----------------------------------------------------------------------------
-- O cadastro
-- -----------------------------------------------------------------------------

create or replace function public.salvar_ingrediente(
  p_restaurante uuid,
  p_nome text,
  p_unidade text,
  p_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nome text := btrim(coalesce(p_nome, ''));
  v_id uuid;
  v_atual ingredients;
begin
  if not (app.can_manage(p_restaurante) or app.is_platform_admin()) then
    raise exception 'Somente a gestao da loja cadastra ingrediente.'
      using errcode = 'insufficient_privilege';
  end if;

  if length(v_nome) not between 1 and 120 then
    raise exception 'Informe o nome do ingrediente.' using errcode = 'check_violation';
  end if;

  if p_unidade is null or p_unidade not in ('kg', 'g', 'L', 'ml', 'un') then
    raise exception 'Unidade invalida: use kg, g, L, ml ou un.' using errcode = 'check_violation';
  end if;

  begin
    if p_id is null then
      insert into ingredients (restaurant_id, name, unit)
      values (p_restaurante, v_nome, p_unidade)
      returning id into v_id;
    else
      select * into v_atual
        from ingredients
       where id = p_id and restaurant_id = p_restaurante and deleted_at is null
         for update;
      if v_atual.id is null then
        raise exception 'Ingrediente nao encontrado.' using errcode = 'no_data_found';
      end if;

      -- Trocar a unidade de quem ja tem livro faria "3" virar 3 kg onde antes
      -- era 3 g. Com movimento, a unidade fica.
      if v_atual.unit <> p_unidade
         and exists (select 1 from ingredient_movements where ingredient_id = p_id) then
        raise exception 'A unidade de % nao muda depois do primeiro lancamento.', v_atual.name
          using errcode = 'check_violation';
      end if;

      update ingredients set name = v_nome, unit = p_unidade where id = p_id
      returning id into v_id;
    end if;
  exception when unique_violation then
    raise exception 'Ja existe um ingrediente chamado %.', v_nome using errcode = 'unique_violation';
  end;

  return v_id;
end;
$$;

create or replace function public.arquivar_ingrediente(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_restaurante uuid;
begin
  select restaurant_id into v_restaurante
    from ingredients where id = p_id and deleted_at is null;

  if v_restaurante is null then
    raise exception 'Ingrediente nao encontrado.' using errcode = 'no_data_found';
  end if;

  if not (app.can_manage(v_restaurante) or app.is_platform_admin()) then
    raise exception 'Somente a gestao da loja arquiva ingrediente.'
      using errcode = 'insufficient_privilege';
  end if;

  -- Arquivar, e nao apagar: o livro e os preparos antigos continuam apontando
  -- para ele. Sai das fichas tecnicas, para nenhum pedido gastar o que nao ha.
  update ingredients set deleted_at = now() where id = p_id;
  delete from product_ingredients where ingredient_id = p_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- Entrada e saida manuais
-- -----------------------------------------------------------------------------

create or replace function public.movimentar_ingredientes(
  p_restaurante uuid,
  p_tipo text,                -- 'in' ou 'out'
  p_itens jsonb,              -- [{"ingrediente": uuid, "quantidade": numeric}, ...]
  p_motivo text default null
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item jsonb;
  v_ingrediente ingredients;
  v_total int := 0;
begin
  if not (app.can_manage(p_restaurante) or app.is_platform_admin()) then
    raise exception 'Somente a gestao da loja lanca entrada e saida de ingrediente.'
      using errcode = 'insufficient_privilege';
  end if;

  if p_tipo is null or p_tipo not in ('in', 'out') then
    raise exception 'Tipo de lancamento invalido.' using errcode = 'check_violation';
  end if;

  if jsonb_typeof(p_itens) is distinct from 'array' or jsonb_array_length(p_itens) = 0 then
    raise exception 'O lancamento precisa de ao menos um ingrediente.'
      using errcode = 'check_violation';
  end if;

  if jsonb_array_length(p_itens) > 200 then
    raise exception 'No maximo 200 itens por lancamento.' using errcode = 'check_violation';
  end if;

  for v_item in select * from jsonb_array_elements(p_itens)
  loop
    select * into v_ingrediente
      from ingredients
     where id = (v_item ->> 'ingrediente')::uuid
       and restaurant_id = p_restaurante
       and deleted_at is null
       for update;

    if v_ingrediente.id is null then
      raise exception 'Ingrediente nao encontrado nesta loja.' using errcode = 'no_data_found';
    end if;

    perform app.movimentar_ingrediente(
      v_ingrediente.id, p_tipo, 'manual',
      app.quantidade_de_ingrediente(v_item ->> 'quantidade', v_ingrediente.name),
      null, null,
      coalesce(p_motivo, case when p_tipo = 'in' then 'Entrada de mercadoria' else 'Saida avulsa' end)
    );
    v_total := v_total + 1;
  end loop;

  return v_total;
end;
$$;

-- -----------------------------------------------------------------------------
-- A ficha tecnica
-- -----------------------------------------------------------------------------

create or replace function public.salvar_ficha_tecnica(
  p_produto uuid,
  p_itens jsonb               -- [{"ingrediente": uuid, "quantidade": numeric}, ...]; [] limpa
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_restaurante uuid;
  v_item jsonb;
  v_ingrediente ingredients;
  v_total int := 0;
begin
  select restaurant_id into v_restaurante
    from products where id = p_produto and deleted_at is null;

  if v_restaurante is null then
    raise exception 'Produto nao encontrado.' using errcode = 'no_data_found';
  end if;

  if not (app.can_manage(v_restaurante) or app.is_platform_admin()) then
    raise exception 'Somente a gestao da loja mexe na ficha tecnica.'
      using errcode = 'insufficient_privilege';
  end if;

  if jsonb_typeof(p_itens) is distinct from 'array' then
    raise exception 'Ficha tecnica invalida.' using errcode = 'check_violation';
  end if;

  delete from product_ingredients where product_id = p_produto;

  for v_item in select * from jsonb_array_elements(p_itens)
  loop
    select * into v_ingrediente
      from ingredients
     where id = (v_item ->> 'ingrediente')::uuid
       and restaurant_id = v_restaurante
       and deleted_at is null;

    if v_ingrediente.id is null then
      raise exception 'Ingrediente nao encontrado nesta loja.' using errcode = 'no_data_found';
    end if;

    begin
      insert into product_ingredients (product_id, ingredient_id, quantity)
      values (p_produto, v_ingrediente.id,
              app.quantidade_de_ingrediente(v_item ->> 'quantidade', v_ingrediente.name));
    exception when unique_violation then
      raise exception '% aparece duas vezes na ficha.', v_ingrediente.name
        using errcode = 'unique_violation';
    end;
    v_total := v_total + 1;
  end loop;

  return v_total;
end;
$$;

-- -----------------------------------------------------------------------------
-- O pedido pronto gasta a ficha tecnica
-- -----------------------------------------------------------------------------

-- Na passagem para "pronto", e uma vez so: a comida saiu da cozinha, os
-- ingredientes foram usados. Cancelar depois nao devolve - o prato foi feito.
-- Produto sem ficha tecnica nao gasta nada, e isso nao e erro.
create or replace function app.baixar_ingredientes_do_pedido()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_linha record;
begin
  if new.status <> 'ready' or old.status = 'ready' then
    return new;
  end if;

  if exists (
    select 1 from ingredient_movements
     where order_id = new.id and source = 'order'
  ) then
    return new;
  end if;

  for v_linha in
    select pi.ingredient_id, sum(oi.quantity * pi.quantity) as quantidade
      from order_items oi
      join product_ingredients pi on pi.product_id = oi.product_id
      join ingredients i on i.id = pi.ingredient_id and i.deleted_at is null
     where oi.order_id = new.id
     group by pi.ingredient_id
     order by pi.ingredient_id
  loop
    perform app.movimentar_ingrediente(
      v_linha.ingredient_id, 'out', 'order', v_linha.quantidade,
      null, new.id, 'Pedido nº ' || new.number
    );
  end loop;

  return new;
end;
$$;

drop trigger if exists orders_baixar_ingredientes on orders;
create trigger orders_baixar_ingredientes
  after update of status on orders
  for each row execute function app.baixar_ingredientes_do_pedido();

-- -----------------------------------------------------------------------------
-- O preparo gasta os ingredientes dele
-- -----------------------------------------------------------------------------

-- Mesma assinatura de antes. O que muda: cada ingrediente precisa existir no
-- estoque (pelo nome, sem acento) e ter quantidade, a unidade e a do cadastro,
-- e o preparo deixa a saida no livro na mesma transacao.
create or replace function public.lancar_preparo(
  p_restaurante uuid,
  p_data date,
  p_nome text,
  p_prato text,
  p_ingredientes jsonb,       -- [{"nome": text, "quantidade": numeric}, ...]
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
  v_texto text;
  v_ingrediente ingredients;
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

  select id into v_produto
    from products
   where restaurant_id = p_restaurante
     and deleted_at is null
     and app.sem_acento(name) = app.sem_acento(v_prato)
   limit 1;

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
    v_texto := btrim(coalesce(v_item ->> 'nome', ''));
    if length(v_texto) not between 1 and 120 then
      raise exception 'Todo ingrediente precisa de nome.' using errcode = 'check_violation';
    end if;

    select * into v_ingrediente
      from ingredients
     where restaurant_id = p_restaurante
       and deleted_at is null
       and app.sem_acento(name) = app.sem_acento(v_texto)
       for update;

    if v_ingrediente.id is null then
      raise exception '% nao esta cadastrado no estoque. Cadastre em Estoque > Ingredientes.', v_texto
        using errcode = 'no_data_found';
    end if;

    v_quantidade := app.quantidade_de_ingrediente(v_item ->> 'quantidade', v_ingrediente.name);

    insert into kitchen_prep_ingredients (prep_id, ingredient_id, name, quantity, unit, position)
    values (v_preparo, v_ingrediente.id, v_ingrediente.name, v_quantidade, v_ingrediente.unit, v_posicao);

    perform app.movimentar_ingrediente(
      v_ingrediente.id, 'out', 'prep', v_quantidade, v_preparo, null,
      'Preparo nº ' || v_numero || ' - ' || v_nome
    );
    v_posicao := v_posicao + 1;
  end loop;

  return v_numero;
end;
$$;

-- Apagar um preparo e corrigir um lancamento errado: o que ele tirou do
-- estoque volta, com uma linha de entrada no livro dizendo por que.
create or replace function app.devolver_ingredientes_do_preparo()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_saida record;
begin
  for v_saida in
    select ingredient_id, quantity
      from ingredient_movements
     where prep_id = old.id and kind = 'out'
     order by ingredient_id
  loop
    perform app.movimentar_ingrediente(
      v_saida.ingredient_id, 'in', 'prep', v_saida.quantity, null, null,
      'Preparo nº ' || old.number || ' apagado'
    );
  end loop;
  return old;
end;
$$;

drop trigger if exists kitchen_preps_devolver_ingredientes on kitchen_preps;
create trigger kitchen_preps_devolver_ingredientes
  before delete on kitchen_preps
  for each row execute function app.devolver_ingredientes_do_preparo();

revoke all on function public.salvar_ingrediente(uuid, text, text, uuid) from public;
revoke all on function public.arquivar_ingrediente(uuid) from public;
revoke all on function public.movimentar_ingredientes(uuid, text, jsonb, text) from public;
revoke all on function public.salvar_ficha_tecnica(uuid, jsonb) from public;
grant execute on function public.salvar_ingrediente(uuid, text, text, uuid) to authenticated;
grant execute on function public.arquivar_ingrediente(uuid) to authenticated;
grant execute on function public.movimentar_ingredientes(uuid, text, jsonb, text) to authenticated;
grant execute on function public.salvar_ficha_tecnica(uuid, jsonb) to authenticated;
