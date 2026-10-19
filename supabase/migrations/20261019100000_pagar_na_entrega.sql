-- =============================================================================
-- Tronvix Facil - pagar na entrega, e a comissao cobrada por mes
--
-- Nao ha operadora de pagamento integrada. O dinheiro vai direto do cliente
-- para a loja: na entrega (maquininha, dinheiro, Pix no QR da loja) ou na
-- mesa. Isto ja funcionava, com tres buracos:
--
--   Pix na entrega nao existia. O Pix era so "pelo app" (codigo da loja,
--   confirmado a mao no extrato). Quem queria pagar o Pix na maquininha, na
--   porta, nao tinha a opcao.
--
--   Cartao "pelo app" estava ligado em cinco lojas, sem operadora por tras. O
--   pedido nascia "aguardando pagamento" e nunca chegava ao balcao.
--
--   A comissao era calculada em cada pedido, mas ninguem a cobrava: com o
--   dinheiro indo direto para a loja, a plataforma precisa fechar o mes e
--   cobrar. `commission_statements` e esse fechamento.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- As formas das lojas
-- -----------------------------------------------------------------------------

-- Cartao pelo app sai de todas as lojas: nao ha como receber.
update restaurant_payment_methods
   set is_active = false
 where timing = 'online' and method <> 'pix' and is_active;

-- Quem aceitava Pix passa a aceitar tambem na entrega e na mesa.
insert into restaurant_payment_methods (restaurant_id, method, timing, is_active)
select restaurant_id, 'pix', 'on_delivery', true
  from restaurant_payment_methods
 where method = 'pix' and timing = 'online' and is_active
on conflict (restaurant_id, method, timing) do update set is_active = true;

-- -----------------------------------------------------------------------------
-- O fechamento recusa o que nao tem como ser pago
-- -----------------------------------------------------------------------------
create or replace function public.fechar_pedido(
  p_cart_id uuid,
  p_fulfillment fulfillment_type,
  p_payment_method payment_method,
  p_payment_timing payment_timing,
  p_address_id uuid default null,
  p_change_for_cents bigint default null,
  p_coupon_code text default null,
  p_notes text default null,
  p_scheduled_for timestamptz default null,
  p_mesa text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_cart carts;
  v_restaurant restaurants;
  v_profile profiles;
  v_address addresses;
  v_mesa restaurant_tables;
  v_order_id uuid;
  v_subtotal bigint := 0;
  v_delivery_fee bigint := 0;
  v_cotacao jsonb;
  v_discount bigint := 0;
  v_total bigint;
  v_commission bigint;
  v_coupon coupons;
  v_status order_status;
  v_itens jsonb := '[]'::jsonb;
  v_item record;
  v_linha jsonb;
  v_adicional jsonb;
  v_unit_price bigint;
  v_addons_total bigint;
  v_addons jsonb;
  v_item_id uuid;
  v_escolhidos int;
  v_grupo record;
  v_saldo int;
begin
  if v_user is null then
    raise exception 'Entre na sua conta para fazer o pedido.' using errcode = 'insufficient_privilege';
  end if;

  select * into v_cart from carts where id = p_cart_id;
  if v_cart.id is null or v_cart.user_id <> v_user then
    raise exception 'Carrinho nao encontrado.' using errcode = 'no_data_found';
  end if;

  select * into v_restaurant from restaurants where id = v_cart.restaurant_id;
  if v_restaurant.status <> 'approved' or v_restaurant.deleted_at is not null then
    raise exception 'Este estabelecimento nao esta disponivel.' using errcode = 'check_violation';
  end if;

  -- Agendamento e a unica forma de pedir com a loja fechada, e so onde o
  -- estabelecimento permitiu.
  --
  -- Duas coisas fecham a loja, e qualquer uma basta: a chave da mao (is_open) e
  -- o horario de funcionamento. Ate aqui so a chave contava, e quem cadastrava
  -- "abre as 18h" recebia pedido as seis da manha.
  if p_scheduled_for is null
     and not (v_restaurant.is_open and app.dentro_do_horario(v_restaurant.id)) then
    raise exception 'O estabelecimento esta fechado agora.' using errcode = 'check_violation';
  end if;
  if p_scheduled_for is not null and not v_restaurant.accepts_scheduled_orders then
    raise exception 'Este estabelecimento nao aceita pedido agendado.' using errcode = 'check_violation';
  end if;
  -- Quem esta sentado na mesa nao agenda para as oito da noite.
  if p_fulfillment = 'dine_in' and p_scheduled_for is not null then
    raise exception 'Pedido na mesa nao e agendado.' using errcode = 'check_violation';
  end if;

  select * into v_profile from profiles where id = v_user;

  -- Cartao pelo app: nao ha operadora integrada. O pedido nasceria esperando
  -- um pagamento impossivel e nunca chegaria ao balcao. Pelo app, so o Pix
  -- com a chave da loja; o resto se paga ao receber.
  if p_payment_timing = 'online' and p_payment_method <> 'pix' then
    raise exception 'Pagamento com cartao pelo aplicativo ainda nao esta disponivel. Escolha pagar ao receber.'
      using errcode = 'check_violation';
  end if;

  -- Pix pelo site sem chave cadastrada e a armadilha que existia: o pedido
  -- nascia esperando um pagamento que nao tinha como acontecer.
  if p_payment_method = 'pix' and p_payment_timing = 'online'
     and (v_restaurant.pix_key is null or v_restaurant.pix_key_type is null) then
    raise exception 'Este estabelecimento ainda nao recebe por Pix.'
      using errcode = 'check_violation';
  end if;

  if p_fulfillment = 'delivery' then
    select * into v_address from addresses
    where id = p_address_id and user_id = v_user and deleted_at is null;

    if v_address.id is null then
      raise exception 'Escolha um endereco de entrega.' using errcode = 'no_data_found';
    end if;
  end if;

  -- Mesa: o codigo vem do QR, e tem de ser de ESTE estabelecimento. Sem esta
  -- conferencia, o QR da mesa 3 de uma loja lancaria pedido na cozinha de
  -- outra - o codigo e unico, mas o carrinho e que diz de quem e a comida.
  if p_fulfillment = 'dine_in' then
    select * into v_mesa from restaurant_tables
    where code = lower(trim(coalesce(p_mesa, '')))
      and deleted_at is null;

    if v_mesa.id is null then
      raise exception 'Mesa nao encontrada. Leia o QR Code da mesa de novo.'
        using errcode = 'no_data_found';
    end if;
    if v_mesa.restaurant_id <> v_cart.restaurant_id then
      raise exception 'Esta mesa e de outro estabelecimento.' using errcode = 'check_violation';
    end if;
    if not v_mesa.is_active then
      raise exception 'Esta mesa nao esta em uso agora.' using errcode = 'check_violation';
    end if;
  end if;

  -- ---------------------------------------------------------------------------
  -- Primeira passagem: a conta, antes de existir pedido
  --
  -- O pedido so e inserido depois que o total fechou, e ja com os valores
  -- finais. Nao da para inserir vazio e corrigir depois: app.guard_order_money
  -- barra qualquer UPDATE de dinheiro em orders - inclusive o desta funcao, e
  -- inclusive quando ela roda como definer. A trava e boa e fica como esta;
  -- quem se adapta e o fechamento.
  -- ---------------------------------------------------------------------------
  for v_item in
    select ci.id as cart_item_id, ci.quantity, ci.notes as item_notes, p.*
    from cart_items ci
    join products p on p.id = ci.product_id
    where ci.cart_id = p_cart_id
    order by ci.created_at
  loop
    if v_item.restaurant_id <> v_cart.restaurant_id then
      raise exception 'O carrinho mistura produtos de estabelecimentos diferentes.'
        using errcode = 'check_violation';
    end if;
    if v_item.deleted_at is not null or not v_item.is_available then
      raise exception '% saiu do cardapio.', v_item.name using errcode = 'check_violation';
    end if;
    if v_item.track_stock and v_item.stock_quantity < v_item.quantity then
      raise exception '% esta esgotado.', v_item.name using errcode = 'check_violation';
    end if;

    -- A promocao so vale dentro da janela. Mesma conta do Produto.emPromocao
    -- no aplicativo; aqui e que ela obriga.
    v_unit_price := case
      when v_item.promo_price_cents is not null
       and (v_item.promo_starts_at is null or now() >= v_item.promo_starts_at)
       and (v_item.promo_ends_at is null or now() <= v_item.promo_ends_at)
      then v_item.promo_price_cents
      else v_item.price_cents
    end;

    -- Regras dos grupos de adicionais: obrigatorio exige, maximo limita.
    for v_grupo in
      select g.* from addon_groups g
      where g.product_id = v_item.id
        and g.is_active and g.deleted_at is null
    loop
      select coalesce(sum(cia.quantity), 0) into v_escolhidos
      from cart_item_addons cia
      join addons a on a.id = cia.addon_id
      where cia.cart_item_id = v_item.cart_item_id and a.group_id = v_grupo.id;

      if v_escolhidos < v_grupo.min_select then
        raise exception 'Em "%", escolha ao menos % opcao(oes).', v_grupo.name, v_grupo.min_select
          using errcode = 'check_violation';
      end if;
      if v_escolhidos > v_grupo.max_select then
        raise exception 'Em "%", o maximo e % opcao(oes).', v_grupo.name, v_grupo.max_select
          using errcode = 'check_violation';
      end if;
    end loop;

    select
      coalesce(sum(a.price_cents * cia.quantity), 0),
      coalesce(jsonb_agg(jsonb_build_object(
        'addon_id', a.id,
        'addon_name', a.name,
        'group_name', g.name,
        'unit_price_cents', a.price_cents,
        'quantity', cia.quantity
      )), '[]'::jsonb)
    into v_addons_total, v_addons
    from cart_item_addons cia
    join addons a on a.id = cia.addon_id
    join addon_groups g on g.id = a.group_id
    where cia.cart_item_id = v_item.cart_item_id
      and a.is_available and a.deleted_at is null;

    v_subtotal := v_subtotal + (v_unit_price + v_addons_total) * v_item.quantity;

    v_itens := v_itens || jsonb_build_object(
      'product_id', v_item.id,
      'product_name', v_item.name,
      'product_image_url', v_item.image_url,
      'unit_price_cents', v_unit_price,
      'quantity', v_item.quantity,
      'addons_total_cents', v_addons_total,
      'notes', v_item.item_notes,
      'track_stock', v_item.track_stock,
      'addons', v_addons
    );
  end loop;

  if v_subtotal = 0 then
    raise exception 'O carrinho esta vazio.' using errcode = 'no_data_found';
  end if;

  -- O pedido minimo existe para a entrega valer a pena. Na mesa, recusar uma
  -- agua de tres reais porque o minimo e vinte seria absurdo: o cliente ja esta
  -- sentado, e o garcom traria a agua de qualquer jeito.
  if p_fulfillment <> 'dine_in' and v_subtotal < v_restaurant.min_order_cents then
    raise exception 'O pedido minimo deste estabelecimento e R$ %.',
      replace(to_char(v_restaurant.min_order_cents / 100.0, 'FM999999990.00'), '.', ',')
      using errcode = 'check_violation';
  end if;

  -- ---------------------------------------------------------------------------
  -- Frete, cupom, comissao
  -- ---------------------------------------------------------------------------
  if p_fulfillment = 'delivery' then
    -- A mesma cotacao que o carrinho mostrou. Fora da area, o pedido nao
    -- nasce: a tela ja avisou, e o banco garante.
    v_cotacao := app.cotacao_de_entrega(
      v_cart.restaurant_id, v_address.latitude, v_address.longitude, v_subtotal);
    if not (v_cotacao ->> 'entrega')::boolean then
      raise exception 'Esta loja nao entrega neste endereco (% km; entrega ate % km).',
        replace((v_cotacao ->> 'km'), '.', ','), replace((v_cotacao ->> 'raio_km'), '.', ',')
        using errcode = 'check_violation';
    end if;
    v_delivery_fee := (v_cotacao ->> 'taxa_cents')::bigint;
  end if;

  if p_coupon_code is not null and length(trim(p_coupon_code)) > 0 then
    v_coupon := app.validate_coupon(
      trim(p_coupon_code), v_cart.restaurant_id, v_user, v_subtotal
    );
    v_discount := app.discount_for_coupon(v_coupon, v_subtotal, v_delivery_fee);
  end if;

  v_total := v_subtotal + v_delivery_fee - v_discount;
  -- A comissao incide sobre a mercadoria, nao sobre o frete.
  v_commission := (v_subtotal * v_restaurant.commission_bps) / 10000;

  -- Pagamento na entrega nao espera nada: o pedido ja vai para o balcao.
  v_status := case when p_payment_timing = 'on_delivery'
                   then 'received'::order_status
                   else 'awaiting_payment'::order_status end;

  -- ---------------------------------------------------------------------------
  -- Segunda passagem: grava
  -- ---------------------------------------------------------------------------
  insert into orders (
    number, restaurant_id, customer_id, customer_name, customer_phone,
    status, fulfillment, address_id, address_summary, address_district,
    address_city, address_postal_code, address_latitude, address_longitude,
    subtotal_cents, delivery_fee_cents, discount_cents, total_cents,
    commission_cents, coupon_id, coupon_code, notes, scheduled_for,
    table_id, table_label
  )
  values (
    0, v_cart.restaurant_id, v_user,
    coalesce(nullif(v_profile.full_name, ''), 'Cliente'),
    v_profile.phone,
    v_status, p_fulfillment,
    v_address.id,
    case when v_address.id is null then null else
      concat_ws(' - ', concat_ws(', ', v_address.street, v_address.number),
                nullif(v_address.complement, '')) end,
    v_address.district, v_address.city, v_address.postal_code,
    v_address.latitude, v_address.longitude,
    v_subtotal, v_delivery_fee, v_discount, v_total,
    v_commission, v_coupon.id, v_coupon.code,
    nullif(p_notes, ''), p_scheduled_for,
    v_mesa.id, v_mesa.label
  )
  returning id into v_order_id;

  for v_linha in select * from jsonb_array_elements(v_itens)
  loop
    insert into order_items (
      order_id, product_id, product_name, product_image_url,
      unit_price_cents, quantity, addons_total_cents, total_cents, notes
    )
    values (
      v_order_id,
      (v_linha ->> 'product_id')::uuid,
      v_linha ->> 'product_name',
      v_linha ->> 'product_image_url',
      (v_linha ->> 'unit_price_cents')::bigint,
      (v_linha ->> 'quantity')::int,
      (v_linha ->> 'addons_total_cents')::bigint,
      ((v_linha ->> 'unit_price_cents')::bigint + (v_linha ->> 'addons_total_cents')::bigint)
        * (v_linha ->> 'quantity')::int,
      nullif(v_linha ->> 'notes', '')
    )
    returning id into v_item_id;

    for v_adicional in select * from jsonb_array_elements(v_linha -> 'addons')
    loop
      insert into order_item_addons (
        order_item_id, addon_id, addon_name, group_name,
        unit_price_cents, quantity, total_cents
      )
      values (
        v_item_id,
        (v_adicional ->> 'addon_id')::uuid,
        v_adicional ->> 'addon_name',
        v_adicional ->> 'group_name',
        (v_adicional ->> 'unit_price_cents')::bigint,
        (v_adicional ->> 'quantity')::int,
        (v_adicional ->> 'unit_price_cents')::bigint * (v_adicional ->> 'quantity')::int
      );
    end loop;

    if (v_linha ->> 'track_stock')::boolean then
      update products
         set stock_quantity = stock_quantity - (v_linha ->> 'quantity')::int
       where id = (v_linha ->> 'product_id')::uuid
      returning stock_quantity into v_saldo;

      insert into stock_movements (
        restaurant_id, product_id, kind, quantity, balance_after, order_id, reason, created_by
      )
      values (
        v_cart.restaurant_id, (v_linha ->> 'product_id')::uuid, 'out',
        (v_linha ->> 'quantity')::int, v_saldo, v_order_id, 'Venda', v_user
      );
    end if;

    update products
       set sold_count = sold_count + (v_linha ->> 'quantity')::int
     where id = (v_linha ->> 'product_id')::uuid;
  end loop;

  insert into payments (
    order_id, method, timing, status, amount_cents, change_for_cents, provider, pix_qr_code
  )
  values (
    v_order_id, p_payment_method, p_payment_timing, 'pending', v_total,
    case when p_payment_method = 'cash' then p_change_for_cents else null end,
    case when p_payment_timing = 'online' then 'pix-direto' else null end,
    -- O codigo do Pix nasce junto com o pedido, com a chave da loja e o total
    -- que ESTA funcao calculou. Montar fora daqui foi tentado e nao funcionou:
    -- a RLS de payments nao deixa o cliente escrever, e o update passava em
    -- silencio sem pegar nenhuma linha. A politica estava certa — o codigo e
    -- que estava no lugar errado.
    case
      when p_payment_method = 'pix' and p_payment_timing = 'online'
      then app.brcode_pix(
        v_restaurant.pix_key,
        v_restaurant.pix_key_type,
        coalesce(v_restaurant.pix_recipient_name, v_restaurant.name),
        coalesce(v_restaurant.pix_city, v_restaurant.city, 'BRASIL'),
        v_total,
        'TF' || (select number from orders where id = v_order_id)
      )
      else null
    end
  );

  if p_fulfillment = 'delivery' then
    insert into deliveries (order_id, restaurant_id, status, courier_fee_cents)
    values (v_order_id, v_cart.restaurant_id, 'pending', v_delivery_fee);
  end if;

  if v_coupon.id is not null then
    insert into coupon_redemptions (coupon_id, order_id, user_id, discount_cents)
    values (v_coupon.id, v_order_id, v_user, v_discount);

    update coupons set used_count = used_count + 1 where id = v_coupon.id;
  end if;

  -- O carrinho morre com o pedido. Os itens caem por cascade.
  delete from carts where id = p_cart_id;

  return v_order_id;
end;
$$;


-- -----------------------------------------------------------------------------
-- O fechamento mensal da comissao
--
-- Um extrato por loja por mes: quantos pedidos entregues, quanto venderam,
-- quanto de comissao. Conta so pedido ENTREGUE: o que foi cancelado nao paga,
-- e o que ainda esta em andamento entra no mes em que terminar. Pedido lancado
-- pela propria loja nao tem comissao (placed_by_store) e soma zero.
--
-- O mes e o do fuso da loja. Gerar de novo atualiza os valores do que ainda
-- esta a pagar; o que ja foi pago fica como foi cobrado.
-- -----------------------------------------------------------------------------

create table if not exists commission_statements (
  id uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references restaurants (id) on delete cascade,
  month date not null,
  orders_count int not null default 0,
  sales_cents bigint not null default 0,
  commission_cents bigint not null default 0,
  status text not null default 'open',
  paid_at timestamptz,
  paid_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (restaurant_id, month),
  constraint commission_statements_first_day check (extract(day from month) = 1),
  constraint commission_statements_status check (status in ('open', 'paid')),
  constraint commission_statements_money check (sales_cents >= 0 and commission_cents >= 0)
);

drop trigger if exists commission_statements_touch on commission_statements;
create trigger commission_statements_touch
  before update on commission_statements
  for each row execute function app.touch_updated_at();

alter table commission_statements enable row level security;

-- A loja ve o que deve; a plataforma ve tudo. Escrita so pelas funcoes.
create policy "extrato de comissao visivel a gestao da loja e a plataforma"
  on commission_statements for select
  to authenticated
  using (app.is_platform_admin() or app.can_manage(restaurant_id));

grant select on commission_statements to authenticated;

create or replace function public.gerar_fechamento_de_comissoes(p_mes date)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_mes date := date_trunc('month', p_mes)::date;
  v_linhas int;
begin
  if not app.is_platform_admin() then
    raise exception 'Somente a plataforma fecha a comissao.'
      using errcode = 'insufficient_privilege';
  end if;

  insert into commission_statements (restaurant_id, month, orders_count, sales_cents, commission_cents)
  select o.restaurant_id, v_mes, count(*), sum(o.subtotal_cents), sum(o.commission_cents)
    from orders o
    join restaurants r on r.id = o.restaurant_id
   where o.status = 'delivered'
     and date_trunc('month', o.created_at at time zone coalesce(r.timezone, 'America/Sao_Paulo'))::date = v_mes
   group by o.restaurant_id
  on conflict (restaurant_id, month) do update
     set orders_count = excluded.orders_count,
         sales_cents = excluded.sales_cents,
         commission_cents = excluded.commission_cents
   where commission_statements.status = 'open';

  get diagnostics v_linhas = row_count;
  return v_linhas;
end;
$$;

create or replace function public.marcar_comissao_paga(p_extrato uuid, p_observacao text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not app.is_platform_admin() then
    raise exception 'Somente a plataforma da baixa na comissao.'
      using errcode = 'insufficient_privilege';
  end if;

  update commission_statements
     set status = 'paid', paid_at = now(),
         paid_note = nullif(left(trim(coalesce(p_observacao, '')), 200), '')
   where id = p_extrato and status = 'open';

  if not found then
    raise exception 'Extrato nao encontrado ou ja pago.' using errcode = 'no_data_found';
  end if;
end;
$$;

revoke all on function public.gerar_fechamento_de_comissoes(date) from public;
revoke all on function public.marcar_comissao_paga(uuid, text) from public;
grant execute on function public.gerar_fechamento_de_comissoes(date) to authenticated;
grant execute on function public.marcar_comissao_paga(uuid, text) to authenticated;
