-- =============================================================================
-- Tronvix Facil - editar o pedido e pedir mais
--
-- Ate aqui o pedido nascia pronto e morria igual. Na vida real, ele muda:
--
--   a loja      o cliente liga e troca o refrigerante, a cozinha avisa que o
--               item acabou, o garcom anota mais uma porcao na mesa.
--   o cliente   sentado na mesa, pede a sobremesa no mesmo pedido em vez de
--               abrir outro.
--
-- O que nao muda e a conta: preco, adicional, estoque, comissao e o valor a
-- receber continuam calculados pelo banco, do mesmo jeito que em
-- `fechar_pedido`. A tela manda O QUE quer; o banco diz QUANTO custa.
--
-- Os valores do pedido seguem trancados por `app.guard_order_money`. A unica
-- passagem e a destas funcoes, que abrem a trava para UM pedido, dentro da
-- propria transacao (`app.pedido_em_edicao`). Uma chamada da API nao consegue
-- abrir a mesma passagem: cada requisicao e uma transacao, e a configuracao
-- morre com ela.
-- =============================================================================

alter table orders
  add column if not exists customer_added_at timestamptz;

comment on column orders.customer_added_at is
  'Quando o cliente da mesa pediu mais itens neste pedido pela ultima vez. E o que faz o sino do balcao tocar de novo.';

-- -----------------------------------------------------------------------------
-- A trava dos valores, com a passagem para a edicao
-- -----------------------------------------------------------------------------

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

  -- Numero e loja nao mudam nunca, nem na edicao.
  if new.number is distinct from old.number
     or new.restaurant_id is distinct from old.restaurant_id then
    raise exception 'Valores e identificacao do pedido nao podem ser alterados apos o fechamento.'
      using errcode = 'insufficient_privilege';
  end if;

  -- O recalculo de `app.recalcular_pedido`, e so ele, mexe no dinheiro.
  if coalesce(current_setting('app.pedido_em_edicao', true), '') = old.id::text then
    return new;
  end if;

  if new.subtotal_cents is distinct from old.subtotal_cents
     or new.delivery_fee_cents is distinct from old.delivery_fee_cents
     or new.discount_cents is distinct from old.discount_cents
     or new.total_cents is distinct from old.total_cents
     or new.commission_cents is distinct from old.commission_cents then
    raise exception 'Valores e identificacao do pedido nao podem ser alterados apos o fechamento.'
      using errcode = 'insufficient_privilege';
  end if;

  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- Estoque: o mesmo livro de `fechar_pedido`
-- -----------------------------------------------------------------------------

create or replace function app.movimentar_estoque_do_pedido(
  p_pedido orders,
  p_produto uuid,
  p_quantidade int,  -- positivo sai do estoque; negativo volta
  p_motivo text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_produto products;
  v_saldo int;
begin
  if p_produto is null or p_quantidade = 0 then
    return;
  end if;

  select * into v_produto from products where id = p_produto for update;
  if v_produto.id is null then
    return; -- produto apagado do cardapio: o item fica, o estoque nao existe mais
  end if;

  update products
     set sold_count = greatest(0, sold_count + p_quantidade)
   where id = p_produto;

  if not v_produto.track_stock then
    return;
  end if;

  if p_quantidade > 0 and v_produto.stock_quantity < p_quantidade then
    raise exception '% esta esgotado.', v_produto.name using errcode = 'check_violation';
  end if;

  update products
     set stock_quantity = stock_quantity - p_quantidade
   where id = p_produto
  returning stock_quantity into v_saldo;

  insert into stock_movements (
    restaurant_id, product_id, kind, quantity, balance_after, order_id, reason, created_by
  )
  values (
    p_pedido.restaurant_id, p_produto,
    case when p_quantidade > 0 then 'out' else 'in' end::stock_movement_type,
    abs(p_quantidade), v_saldo, p_pedido.id, p_motivo, auth.uid()
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- Um item novo no pedido
--
-- As mesmas regras de `fechar_pedido`: produto desta loja e no ar, preco de
-- promocao so dentro da janela, grupo obrigatorio exige, maximo limita,
-- adicional tem de ser do produto, estar disponivel e respeitar a quantidade
-- maxima dele.
--
-- p_item: {"produto_id": uuid, "quantidade": int, "observacao": text,
--          "adicionais": [uuid | {"id": uuid, "quantidade": int}, ...]}
--
-- O adicional vem como id solto (uma unidade, como o site escolhe) ou com
-- quantidade (o aplicativo deixa pedir 2x bacon).
-- -----------------------------------------------------------------------------

create or replace function app.inserir_item_no_pedido(p_pedido orders, p_item jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_produto products;
  v_quantidade int;
  v_ids uuid[];
  v_qtds int[];
  v_unit_price bigint;
  v_addons_total bigint;
  v_validos int;
  v_escolhidos int;
  v_grupo record;
  v_item_id uuid;
begin
  begin
    v_quantidade := (p_item ->> 'quantidade')::int;
    select coalesce(array_agg(x.id), '{}'), coalesce(array_agg(x.qtd), '{}')
      into v_ids, v_qtds
      from (
        select
          case when jsonb_typeof(e) = 'string' then (e #>> '{}')::uuid
               else (e ->> 'id')::uuid end as id,
          case when jsonb_typeof(e) = 'string' then 1
               else coalesce((e ->> 'quantidade')::int, 1) end as qtd
        from jsonb_array_elements(coalesce(p_item -> 'adicionais', '[]'::jsonb)) e
      ) x;
  exception when others then
    raise exception 'Item invalido.' using errcode = 'check_violation';
  end;

  if v_quantidade is null or v_quantidade not between 1 and 99 then
    raise exception 'A quantidade vai de 1 a 99.' using errcode = 'check_violation';
  end if;
  if (select count(distinct i) from unnest(v_ids) i) <> coalesce(array_length(v_ids, 1), 0)
     or exists (select 1 from unnest(v_qtds) q where q is null or q < 1) then
    raise exception 'Item invalido.' using errcode = 'check_violation';
  end if;

  select * into v_produto from products where id = (p_item ->> 'produto_id')::uuid;
  if v_produto.id is null or v_produto.restaurant_id <> p_pedido.restaurant_id then
    raise exception 'Produto nao encontrado neste cardapio.' using errcode = 'no_data_found';
  end if;
  if v_produto.deleted_at is not null or not v_produto.is_available then
    raise exception '% saiu do cardapio.', v_produto.name using errcode = 'check_violation';
  end if;

  v_unit_price := case
    when v_produto.promo_price_cents is not null
     and (v_produto.promo_starts_at is null or now() >= v_produto.promo_starts_at)
     and (v_produto.promo_ends_at is null or now() <= v_produto.promo_ends_at)
    then v_produto.promo_price_cents
    else v_produto.price_cents
  end;

  -- Todo adicional pedido tem de ser deste produto, ativo, disponivel e
  -- dentro da quantidade dele. Um id de outro produto ou fora do ar e
  -- recusado, e nao ignorado: ignorar seria cobrar sem o que foi escolhido.
  select count(*) into v_validos
  from unnest(v_ids, v_qtds) as x(id, qtd)
  join addons a on a.id = x.id
  join addon_groups g on g.id = a.group_id
  where g.product_id = v_produto.id
    and g.is_active and g.deleted_at is null
    and a.is_available and a.deleted_at is null
    and x.qtd <= a.max_quantity;

  if v_validos <> coalesce(array_length(v_ids, 1), 0) then
    raise exception 'Algum adicional escolhido nao esta mais disponivel para %.', v_produto.name
      using errcode = 'check_violation';
  end if;

  -- Mesma conta de `fechar_pedido`: o grupo soma as quantidades.
  for v_grupo in
    select g.* from addon_groups g
    where g.product_id = v_produto.id and g.is_active and g.deleted_at is null
  loop
    select coalesce(sum(x.qtd), 0) into v_escolhidos
    from unnest(v_ids, v_qtds) as x(id, qtd)
    join addons a on a.id = x.id
    where a.group_id = v_grupo.id;

    if v_escolhidos < v_grupo.min_select then
      raise exception 'Em "%", escolha ao menos % opcao(oes).', v_grupo.name, v_grupo.min_select
        using errcode = 'check_violation';
    end if;
    if v_escolhidos > v_grupo.max_select then
      raise exception 'Em "%", o maximo e % opcao(oes).', v_grupo.name, v_grupo.max_select
        using errcode = 'check_violation';
    end if;
  end loop;

  select coalesce(sum(a.price_cents * x.qtd), 0) into v_addons_total
  from unnest(v_ids, v_qtds) as x(id, qtd)
  join addons a on a.id = x.id;

  insert into order_items (
    order_id, product_id, product_name, product_image_url,
    unit_price_cents, quantity, addons_total_cents, total_cents, notes
  )
  values (
    p_pedido.id, v_produto.id, v_produto.name, v_produto.image_url,
    v_unit_price, v_quantidade, v_addons_total,
    (v_unit_price + v_addons_total) * v_quantidade,
    nullif(left(trim(coalesce(p_item ->> 'observacao', '')), 200), '')
  )
  returning id into v_item_id;

  insert into order_item_addons (
    order_item_id, addon_id, addon_name, group_name, unit_price_cents, quantity, total_cents
  )
  select v_item_id, a.id, a.name, g.name, a.price_cents, x.qtd, a.price_cents * x.qtd
  from unnest(v_ids, v_qtds) as x(id, qtd)
  join addons a on a.id = x.id
  join addon_groups g on g.id = a.group_id;

  perform app.movimentar_estoque_do_pedido(p_pedido, v_produto.id, v_quantidade, 'Venda');
end;
$$;

-- -----------------------------------------------------------------------------
-- A conta de novo, depois de mexer nos itens
--
-- Frete nao muda: a corrida e a mesma. O desconto ja dado fica, mas nunca
-- passa do que ha para descontar. A comissao volta a incidir sobre a
-- mercadoria. E o valor a receber acompanha o total — senao o caixa cobraria
-- o pedido antigo.
-- -----------------------------------------------------------------------------

create or replace function app.recalcular_pedido(p_pedido uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pedido orders;
  v_subtotal bigint;
  v_desconto bigint;
  v_total bigint;
  v_bps int;
begin
  select * into v_pedido from orders where id = p_pedido;

  select coalesce(sum(total_cents), 0) into v_subtotal
  from order_items where order_id = p_pedido;

  if v_subtotal = 0 then
    raise exception 'O pedido precisa de ao menos um item. Para desistir de tudo, cancele o pedido.'
      using errcode = 'check_violation';
  end if;

  v_desconto := least(v_pedido.discount_cents, v_subtotal + v_pedido.delivery_fee_cents);
  v_total := v_subtotal + v_pedido.delivery_fee_cents - v_desconto;

  if v_total <= 0 then
    raise exception 'O pedido nao pode ficar de graca.' using errcode = 'check_violation';
  end if;

  select commission_bps into v_bps from restaurants where id = v_pedido.restaurant_id;

  perform set_config('app.pedido_em_edicao', p_pedido::text, true);

  update orders
     set subtotal_cents = v_subtotal,
         discount_cents = v_desconto,
         total_cents = v_total,
         commission_cents = (v_subtotal * v_bps) / 10000
   where id = p_pedido;

  perform set_config('app.pedido_em_edicao', '', true);

  if v_desconto <> v_pedido.discount_cents then
    update coupon_redemptions set discount_cents = v_desconto where order_id = p_pedido;
  end if;

  -- Troco para menos do que o novo total nao serve mais: o entregador sairia
  -- com o troco errado.
  update payments
     set amount_cents = v_total,
         change_for_cents = case when change_for_cents >= v_total then change_for_cents end
   where order_id = p_pedido and status = 'pending';
end;
$$;

-- -----------------------------------------------------------------------------
-- Quando um pedido ainda pode mudar
-- -----------------------------------------------------------------------------

create or replace function app.conferir_pedido_editavel(p_pedido orders)
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_pagamento payments;
begin
  -- Depois de sair para a rua ou de ser entregue, o pedido e historia.
  if p_pedido.status not in ('received', 'confirmed', 'preparing', 'ready') then
    raise exception 'Este pedido nao pode mais ser alterado.' using errcode = 'check_violation';
  end if;

  -- Pago, ou pago pelo site: o valor ja foi acertado com o cliente. Mudar o
  -- total agora e cobrar o que ninguem autorizou, ou devolver o que ninguem
  -- vai devolver.
  select * into v_pagamento from payments where order_id = p_pedido.id limit 1;
  if v_pagamento.timing = 'online' then
    raise exception 'Pedido pago pelo site nao pode ser alterado. Faca um pedido novo.'
      using errcode = 'check_violation';
  end if;
  if v_pagamento.status = 'paid' then
    raise exception 'Este pedido ja foi recebido no caixa e nao pode ser alterado.'
      using errcode = 'check_violation';
  end if;
end;
$$;

-- -----------------------------------------------------------------------------
-- A loja edita
--
-- p_alteracoes:
--   {"itens":  [{"id": uuid, "quantidade": int}, ...],   0 remove o item
--    "novos":  [{"produto_id", "quantidade", "observacao", "adicionais"}, ...]}
--
-- Item que nao aparece em "itens" fica como esta. Tudo numa transacao so: a
-- cozinha nunca ve o pedido pela metade.
-- -----------------------------------------------------------------------------

create or replace function public.editar_pedido(p_pedido uuid, p_alteracoes jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pedido orders;
  v_mudanca jsonb;
  v_item order_items;
  v_quantidade int;
  v_novo jsonb;
begin
  select * into v_pedido from orders where id = p_pedido for update;
  if v_pedido.id is null then
    raise exception 'Pedido nao encontrado.' using errcode = 'no_data_found';
  end if;
  if not (app.is_member(v_pedido.restaurant_id) or app.is_platform_admin()) then
    raise exception 'Somente a equipe da loja edita o pedido.'
      using errcode = 'insufficient_privilege';
  end if;

  perform app.conferir_pedido_editavel(v_pedido);

  for v_mudanca in
    select * from jsonb_array_elements(coalesce(p_alteracoes -> 'itens', '[]'::jsonb))
  loop
    select * into v_item from order_items
    where id = (v_mudanca ->> 'id')::uuid and order_id = p_pedido
    for update;

    if v_item.id is null then
      raise exception 'Item nao encontrado neste pedido.' using errcode = 'no_data_found';
    end if;

    v_quantidade := (v_mudanca ->> 'quantidade')::int;
    if v_quantidade is null or v_quantidade not between 0 and 99 then
      raise exception 'A quantidade vai de 0 a 99.' using errcode = 'check_violation';
    end if;

    continue when v_quantidade = v_item.quantity;

    -- Mais unidades saem do estoque; menos voltam.
    perform app.movimentar_estoque_do_pedido(
      v_pedido, v_item.product_id, v_quantidade - v_item.quantity,
      case when v_quantidade > v_item.quantity then 'Venda' else 'Pedido editado' end
    );

    if v_quantidade = 0 then
      delete from order_items where id = v_item.id;
    else
      -- O preco do item e o do momento em que entrou no pedido: mudar a
      -- quantidade nao reajusta o que ja foi combinado.
      update order_items
         set quantity = v_quantidade,
             total_cents = (unit_price_cents + addons_total_cents) * v_quantidade
       where id = v_item.id;
    end if;
  end loop;

  for v_novo in
    select * from jsonb_array_elements(coalesce(p_alteracoes -> 'novos', '[]'::jsonb))
  loop
    perform app.inserir_item_no_pedido(v_pedido, v_novo);
  end loop;

  perform app.recalcular_pedido(p_pedido);
end;
$$;

-- -----------------------------------------------------------------------------
-- O cliente da mesa pede mais
--
-- So acrescenta: tirar o que a cozinha talvez ja esteja fazendo e com o
-- garcom. E so na mesa — na entrega, o pedido ja esta a caminho de ser
-- embalado, e mais um item e outro pedido.
-- -----------------------------------------------------------------------------

create or replace function public.pedir_mais_na_mesa(p_pedido uuid, p_itens jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pedido orders;
  v_novo jsonb;
begin
  select * into v_pedido from orders where id = p_pedido for update;
  if v_pedido.id is null or v_pedido.customer_id is distinct from auth.uid() then
    raise exception 'Pedido nao encontrado.' using errcode = 'no_data_found';
  end if;
  if v_pedido.fulfillment <> 'dine_in' then
    raise exception 'So da para pedir mais no pedido da mesa.' using errcode = 'check_violation';
  end if;

  perform app.conferir_pedido_editavel(v_pedido);

  if not exists (
    select 1 from restaurants where id = v_pedido.restaurant_id and is_open
  ) then
    raise exception 'A cozinha esta fechada agora.' using errcode = 'check_violation';
  end if;

  if jsonb_array_length(coalesce(p_itens, '[]'::jsonb)) = 0 then
    raise exception 'Escolha ao menos um item.' using errcode = 'check_violation';
  end if;

  for v_novo in select * from jsonb_array_elements(p_itens)
  loop
    perform app.inserir_item_no_pedido(v_pedido, v_novo);
  end loop;

  perform app.recalcular_pedido(p_pedido);

  update orders set customer_added_at = now() where id = p_pedido;
end;
$$;

revoke all on function public.editar_pedido(uuid, jsonb) from public;
revoke all on function public.pedir_mais_na_mesa(uuid, jsonb) from public;
grant execute on function public.editar_pedido(uuid, jsonb) to authenticated;
grant execute on function public.pedir_mais_na_mesa(uuid, jsonb) to authenticated;

comment on function public.editar_pedido is
  'A loja muda quantidades, remove e acrescenta itens num pedido ainda aberto e nao pago. O banco refaz a conta, o estoque e o valor a receber.';
comment on function public.pedir_mais_na_mesa is
  'O cliente da mesa acrescenta itens ao proprio pedido ainda aberto. So acrescenta; mexer no que ja foi pedido e com a loja.';

-- Item de pedido so nasce pelas funcoes do banco (`fechar_pedido`,
-- `editar_pedido`, `pedir_mais_na_mesa`), que rodam como definer. A politica
-- de insert que existia deixava o cliente gravar item direto no proprio pedido,
-- sem preco conferido e sem passar pela conta — e com o pedido agora vivo, esse
-- item apareceria na cozinha.
drop policy if exists "itens criados com o pedido" on order_items;
drop policy if exists "adicionais criados com o item" on order_item_addons;
