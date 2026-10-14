-- =============================================================================
-- Tronvix Facil - taxa de entrega por distancia
--
-- Ate aqui a taxa era uma so por loja, e o "raio de entrega" que o dono
-- configurava nao valia em lugar nenhum: qualquer endereco pedia de qualquer
-- loja, pela mesma taxa — do vizinho de porta ao outro lado da cidade.
--
-- Agora a loja monta faixas, como o dono pensa e como o cliente esta
-- acostumado a ver:
--
--   ate 2 km   R$ 4,00
--   ate 4 km   R$ 6,00
--   ate 6 km   R$ 9,00      acima da ultima faixa, nao entrega
--
-- A distancia e em linha reta (`app.haversine_km`), entre a loja e o endereco.
-- Nao e rota — nao conhece rio nem mao unica —, e por isso a loja desenha as
-- faixas com folga. Rota de verdade e servico pago, por chamada.
--
-- Loja sem faixas continua como antes: taxa unica. Mas o raio passa a valer.
--
-- Endereco sem localizacao (cadastrado antes, ou sem GPS) nao e recusado:
-- cobra a maior faixa. Recusar seria perder o pedido de quem nao tem culpa de
-- o endereco nao ter coordenada; cobrar a menor seria a loja pagar a corrida
-- longa. A maior e a conta honesta sem saber a distancia.
-- =============================================================================

create table delivery_fee_tiers (
  id uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references restaurants (id) on delete cascade,
  up_to_km numeric(5, 2) not null,
  fee_cents bigint not null,
  created_at timestamptz not null default now(),

  constraint delivery_fee_tiers_km_range check (up_to_km > 0 and up_to_km <= 50),
  constraint delivery_fee_tiers_fee_non_negative check (fee_cents >= 0),
  unique (restaurant_id, up_to_km)
);

alter table delivery_fee_tiers enable row level security;

-- A tabela de taxas e publica como o cardapio: quem escolhe a loja precisa
-- saber quanto a entrega custa antes de montar o carrinho.
create policy "faixas de entrega visiveis com a loja"
  on delivery_fee_tiers for select
  to anon, authenticated
  using (
    exists (
      select 1 from restaurants r
      where r.id = restaurant_id
        and ((r.status = 'approved' and r.deleted_at is null)
             or app.is_member(r.id) or app.is_platform_admin())
    )
  );

grant select on delivery_fee_tiers to anon, authenticated;

comment on table delivery_fee_tiers is
  'Taxa de entrega por faixa de distancia, por loja. Acima da maior faixa, a loja nao entrega.';

-- -----------------------------------------------------------------------------
-- A cotacao: entrega? a quantos km? por quanto?
-- -----------------------------------------------------------------------------

create or replace function app.cotacao_de_entrega(
  p_restaurante uuid,
  p_latitude numeric,
  p_longitude numeric,
  p_subtotal_cents bigint default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_loja restaurants;
  v_km numeric;
  v_tem_faixas boolean;
  v_taxa bigint;
  v_maior_km numeric;
begin
  select * into v_loja from restaurants where id = p_restaurante;
  if v_loja.id is null then
    raise exception 'Estabelecimento nao encontrado.' using errcode = 'no_data_found';
  end if;

  v_km := app.haversine_km(v_loja.latitude, v_loja.longitude, p_latitude, p_longitude);

  select exists (select 1 from delivery_fee_tiers where restaurant_id = p_restaurante),
         (select max(up_to_km) from delivery_fee_tiers where restaurant_id = p_restaurante)
    into v_tem_faixas, v_maior_km;

  if v_tem_faixas then
    if v_km is null then
      -- Sem saber a distancia: a maior faixa (ver cabecalho).
      select fee_cents into v_taxa from delivery_fee_tiers
       where restaurant_id = p_restaurante order by up_to_km desc limit 1;
    else
      select fee_cents into v_taxa from delivery_fee_tiers
       where restaurant_id = p_restaurante and up_to_km >= v_km
       order by up_to_km limit 1;

      if v_taxa is null then
        return jsonb_build_object(
          'entrega', false, 'km', v_km, 'taxa_cents', null,
          'motivo', 'fora_da_area', 'raio_km', v_maior_km);
      end if;
    end if;
  else
    -- Loja sem faixas: a taxa unica de sempre, agora com o raio valendo.
    if v_km is not null and v_km > v_loja.delivery_radius_km then
      return jsonb_build_object(
        'entrega', false, 'km', v_km, 'taxa_cents', null,
        'motivo', 'fora_da_area', 'raio_km', v_loja.delivery_radius_km);
    end if;
    v_taxa := v_loja.delivery_fee_cents;
  end if;

  if v_loja.free_delivery_above_cents is not null
     and coalesce(p_subtotal_cents, 0) >= v_loja.free_delivery_above_cents then
    v_taxa := 0;
  end if;

  return jsonb_build_object(
    'entrega', true, 'km', v_km, 'taxa_cents', v_taxa,
    'motivo', case when v_km is null then 'sem_localizacao' end,
    'raio_km', coalesce(v_maior_km, v_loja.delivery_radius_km));
end;
$$;

comment on function app.cotacao_de_entrega(uuid, numeric, numeric, bigint) is
  'Se a loja entrega num ponto, a quantos km e por quanto. Fonte unica da taxa: carrinho, vitrine, fechamento e lancamento pela loja.';

-- Para o carrinho: a cotacao para um endereco do proprio cliente.
create or replace function public.cotar_entrega(
  p_restaurante uuid,
  p_endereco uuid,
  p_subtotal_cents bigint default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_endereco addresses;
begin
  select * into v_endereco from addresses
   where id = p_endereco and user_id = auth.uid() and deleted_at is null;
  if v_endereco.id is null then
    raise exception 'Endereco nao encontrado.' using errcode = 'no_data_found';
  end if;

  return app.cotacao_de_entrega(
    p_restaurante, v_endereco.latitude, v_endereco.longitude, p_subtotal_cents);
end;
$$;

-- Para a vitrine: todas as lojas abertas ao publico, para um endereco.
create or replace function public.lojas_para_o_endereco(p_endereco uuid)
returns table (restaurant_id uuid, entrega boolean, km numeric, taxa_cents bigint)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_endereco addresses;
begin
  select * into v_endereco from addresses
   where id = p_endereco and user_id = auth.uid() and deleted_at is null;
  if v_endereco.id is null then
    raise exception 'Endereco nao encontrado.' using errcode = 'no_data_found';
  end if;

  return query
    select r.id,
           (c ->> 'entrega')::boolean,
           (c ->> 'km')::numeric,
           (c ->> 'taxa_cents')::bigint
      from restaurants r
      cross join lateral app.cotacao_de_entrega(
        r.id, v_endereco.latitude, v_endereco.longitude, 0) c
     where r.status = 'approved' and r.deleted_at is null;
end;
$$;

-- -----------------------------------------------------------------------------
-- O dono salva as faixas
--
-- Troca a tabela inteira de uma vez: faixas sao uma lista que se edita junta,
-- e gravar uma por uma deixaria a loja, no meio, com metade das faixas novas.
--
-- p_faixas: [{"ate_km": 2, "taxa_cents": 400}, ...]   [] volta a taxa unica.
-- -----------------------------------------------------------------------------

create or replace function public.salvar_faixas_de_entrega(p_restaurante uuid, p_faixas jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_qtd int;
begin
  if not (app.can_manage(p_restaurante) or app.is_platform_admin()) then
    raise exception 'Somente proprietario ou gerente muda a taxa de entrega.'
      using errcode = 'insufficient_privilege';
  end if;

  v_qtd := jsonb_array_length(coalesce(p_faixas, '[]'::jsonb));
  if v_qtd > 10 then
    raise exception 'No maximo 10 faixas.' using errcode = 'check_violation';
  end if;

  delete from delivery_fee_tiers where restaurant_id = p_restaurante;

  begin
    insert into delivery_fee_tiers (restaurant_id, up_to_km, fee_cents)
    select p_restaurante, (f ->> 'ate_km')::numeric, (f ->> 'taxa_cents')::bigint
      from jsonb_array_elements(coalesce(p_faixas, '[]'::jsonb)) f;
  exception
    when unique_violation then
      raise exception 'Duas faixas com a mesma distancia.' using errcode = 'check_violation';
    when check_violation or invalid_text_representation or not_null_violation then
      raise exception 'Cada faixa precisa de distancia entre 0 e 50 km e taxa de zero para cima.'
        using errcode = 'check_violation';
  end;

  -- O raio que a vitrine e o painel mostram passa a ser o da maior faixa.
  if v_qtd > 0 then
    update restaurants
       set delivery_radius_km = (select max(up_to_km) from delivery_fee_tiers
                                  where restaurant_id = p_restaurante)
     where id = p_restaurante;
  end if;
end;
$$;

revoke all on function public.cotar_entrega(uuid, uuid, bigint) from public;
revoke all on function public.lojas_para_o_endereco(uuid) from public;
revoke all on function public.salvar_faixas_de_entrega(uuid, jsonb) from public;
grant execute on function public.cotar_entrega(uuid, uuid, bigint) to authenticated;
grant execute on function public.lojas_para_o_endereco(uuid) to authenticated;
grant execute on function public.salvar_faixas_de_entrega(uuid, jsonb) to authenticated;

-- -----------------------------------------------------------------------------
-- O fechamento passa a cobrar pela distancia, e recusa fora da area
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
-- O pedido lancado pela loja tambem
--
-- Endereco digitado pelo telefone nao tem coordenada: cai na maior faixa (ou
-- na taxa unica), pela mesma cotacao. A loja ve o valor antes de lancar.
-- -----------------------------------------------------------------------------
create or replace function public.lancar_pedido(p_restaurante uuid, p_dados jsonb)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_restaurante restaurants;
  v_tipo fulfillment_type;
  v_forma payment_method;
  v_cliente text;
  v_telefone text;
  v_mesa restaurant_tables;
  v_rotulo_da_mesa text;
  v_endereco jsonb;
  v_resumo text;
  v_pedido orders;
  v_item jsonb;
  v_subtotal bigint;
  v_frete bigint := 0;
  v_troco bigint;
begin
  if not (app.is_member(p_restaurante) or app.is_platform_admin()) then
    raise exception 'Somente a equipe da loja lanca pedido.'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_restaurante from restaurants where id = p_restaurante;
  if v_restaurante.id is null or v_restaurante.deleted_at is not null then
    raise exception 'Estabelecimento nao encontrado.' using errcode = 'no_data_found';
  end if;

  begin
    v_tipo := (p_dados ->> 'tipo')::fulfillment_type;
    v_forma := coalesce(p_dados ->> 'forma', 'cash')::payment_method;
    v_troco := (p_dados ->> 'troco_para_cents')::bigint;
  exception when others then
    raise exception 'Tipo de pedido ou forma de pagamento invalidos.' using errcode = 'check_violation';
  end;

  if v_tipo is null then
    raise exception 'Diga se o pedido e de balcao, mesa ou entrega.' using errcode = 'check_violation';
  end if;

  if jsonb_array_length(coalesce(p_dados -> 'itens', '[]'::jsonb)) = 0 then
    raise exception 'Escolha ao menos um item.' using errcode = 'check_violation';
  end if;

  v_telefone := nullif(regexp_replace(coalesce(p_dados ->> 'telefone', ''), '\D', '', 'g'), '');
  if v_telefone is not null and length(v_telefone) not between 10 and 13 then
    raise exception 'Telefone com DDD, so numeros.' using errcode = 'check_violation';
  end if;

  v_cliente := nullif(left(trim(coalesce(p_dados ->> 'cliente', '')), 80), '');

  -- Mesa: a cadastrada, desta loja; ou o rotulo que o garcom escreveu, para a
  -- loja que ainda nao cadastrou as mesas.
  if v_tipo = 'dine_in' then
    if p_dados ? 'mesa_id' and p_dados ->> 'mesa_id' is not null then
      select * into v_mesa from restaurant_tables
      where id = (p_dados ->> 'mesa_id')::uuid
        and restaurant_id = p_restaurante
        and deleted_at is null;
      if v_mesa.id is null then
        raise exception 'Mesa nao encontrada.' using errcode = 'no_data_found';
      end if;
      v_rotulo_da_mesa := v_mesa.label;
    else
      v_rotulo_da_mesa := nullif(left(trim(coalesce(p_dados ->> 'mesa', '')), 40), '');
    end if;

    if v_rotulo_da_mesa is null then
      raise exception 'Diga qual e a mesa.' using errcode = 'check_violation';
    end if;
  end if;

  -- Entrega por telefone: endereco e telefone sao o minimo para o entregador
  -- chegar e, se nao achar, ligar.
  if v_tipo = 'delivery' then
    v_endereco := coalesce(p_dados -> 'endereco', '{}'::jsonb);
    if length(trim(coalesce(v_endereco ->> 'rua', ''))) < 2
       or length(trim(coalesce(v_endereco ->> 'numero', ''))) < 1
       or length(trim(coalesce(v_endereco ->> 'bairro', ''))) < 2 then
      raise exception 'Entrega precisa de rua, numero e bairro.' using errcode = 'check_violation';
    end if;
    if v_telefone is null then
      raise exception 'Entrega precisa do telefone do cliente.' using errcode = 'check_violation';
    end if;

    v_resumo := concat_ws(' - ',
      concat_ws(', ', trim(v_endereco ->> 'rua'), trim(v_endereco ->> 'numero')),
      nullif(trim(coalesce(v_endereco ->> 'complemento', '')), ''));
  end if;

  if v_troco is not null and v_forma <> 'cash' then
    v_troco := null;
  end if;

  -- O pedido nasce sem valor; os itens entram e a conta e feita no fim, pelo
  -- mesmo recalculo da edicao.
  insert into orders (
    number, restaurant_id, customer_id, customer_name, customer_phone,
    status, confirmed_at, fulfillment,
    address_summary, address_district, address_city, address_postal_code,
    notes, table_id, table_label, placed_by_store
  )
  values (
    0, p_restaurante, null,
    coalesce(v_cliente, case v_tipo
      when 'dine_in' then v_rotulo_da_mesa
      when 'delivery' then 'Cliente'
      else 'Balcao' end),
    v_telefone,
    'confirmed', now(), v_tipo,
    v_resumo,
    case when v_tipo = 'delivery' then trim(v_endereco ->> 'bairro') end,
    case when v_tipo = 'delivery' then nullif(trim(coalesce(v_endereco ->> 'cidade', '')), '') end,
    case when v_tipo = 'delivery'
      then nullif(regexp_replace(coalesce(v_endereco ->> 'cep', ''), '\D', '', 'g'), '') end,
    nullif(left(trim(coalesce(p_dados ->> 'observacao', '')), 500), ''),
    v_mesa.id, v_rotulo_da_mesa, true
  )
  returning * into v_pedido;

  for v_item in select * from jsonb_array_elements(p_dados -> 'itens')
  loop
    perform app.inserir_item_no_pedido(v_pedido, v_item);
  end loop;

  -- Frete com a regra da loja, agora que o subtotal existe.
  if v_tipo = 'delivery' then
    select coalesce(sum(total_cents), 0) into v_subtotal
    from order_items where order_id = v_pedido.id;

    v_frete := coalesce(
      (app.cotacao_de_entrega(p_restaurante, null, null, v_subtotal) ->> 'taxa_cents')::bigint,
      0);

    perform set_config('app.pedido_em_edicao', v_pedido.id::text, true);
    -- O total acompanha na mesma linha: a constraint confere as partes a cada
    -- escrita, e o recalculo logo abaixo poe o subtotal no lugar.
    update orders
       set delivery_fee_cents = v_frete,
           total_cents = subtotal_cents + v_frete - discount_cents
     where id = v_pedido.id;
    perform set_config('app.pedido_em_edicao', '', true);
  end if;

  perform app.recalcular_pedido(v_pedido.id);
  select * into v_pedido from orders where id = v_pedido.id;

  insert into payments (order_id, method, timing, status, amount_cents, change_for_cents, paid_at)
  values (
    v_pedido.id, v_forma, 'on_delivery',
    case when (p_dados ->> 'receber_agora')::boolean then 'paid' else 'pending' end::payment_status,
    v_pedido.total_cents,
    case when v_troco >= v_pedido.total_cents then v_troco end,
    case when (p_dados ->> 'receber_agora')::boolean then now() end
  );

  if v_tipo = 'delivery' then
    insert into deliveries (order_id, restaurant_id, status, courier_fee_cents)
    values (v_pedido.id, p_restaurante, 'pending', v_frete);
  end if;

  return v_pedido.id;
end;
$$;

