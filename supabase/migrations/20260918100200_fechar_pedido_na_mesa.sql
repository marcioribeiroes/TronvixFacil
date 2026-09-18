-- =============================================================================
-- fechar_pedido aprende a mesa.
--
-- O que mudou, e so isto: um parametro p_mesa com o codigo lido do QR, a
-- conferencia de que a mesa e deste estabelecimento, e o rotulo copiado para o
-- pedido. O resto do corpo e o mesmo - preco recalculado do cardapio, cupom,
-- comissao, estoque - porque essas regras nao dependem de onde a pessoa esta.
--
-- Duas regras deixam de valer na mesa:
--
--   pedido minimo  existe para a entrega valer a pena. Quem ja esta sentado e
--                  pede uma agua nao deve ouvir "o minimo e vinte reais".
--   agendamento    ninguem agenda da propria mesa para dali a duas horas.
--
-- E uma nao muda: o frete. A constraint orders_no_fee_off_street garante zero
-- fora da entrega, entao nem e preciso confiar neste codigo.
-- =============================================================================

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
  if not v_restaurant.is_open and p_scheduled_for is null then
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
    v_delivery_fee := case
      when v_restaurant.free_delivery_above_cents is not null
       and v_subtotal >= v_restaurant.free_delivery_above_cents then 0
      else v_restaurant.delivery_fee_cents
    end;
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

  insert into payments (order_id, method, timing, status, amount_cents, change_for_cents, provider)
  values (
    v_order_id, p_payment_method, p_payment_timing, 'pending', v_total,
    case when p_payment_method = 'cash' then p_change_for_cents else null end,
    case when p_payment_timing = 'online' then 'simulado' else null end
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


grant execute on function public.fechar_pedido(
  uuid, fulfillment_type, payment_method, payment_timing, uuid, bigint, text, text, timestamptz, text
) to authenticated;

-- A assinatura antiga, de nove parametros, sai de circulacao: deixa-la para
-- tras faria o PostgREST ter duas candidatas e escolher a errada conforme o
-- corpo do pedido.
drop function if exists public.fechar_pedido(
  uuid, fulfillment_type, payment_method, payment_timing, uuid, bigint, text, text, timestamptz
);

comment on function public.fechar_pedido(
  uuid, fulfillment_type, payment_method, payment_timing, uuid, bigint, text, text, timestamptz, text
) is
  'Unico caminho pelo qual um cliente cria pedido - entrega, retirada ou mesa. Le o carrinho, recalcula todo preco a partir do cardapio atual e grava pedido, itens, pagamento e entrega numa transacao so. Nenhum valor vem do aplicativo.';
