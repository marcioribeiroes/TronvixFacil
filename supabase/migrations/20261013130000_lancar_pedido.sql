-- =============================================================================
-- Tronvix Facil - a loja lanca o pedido
--
-- Nem todo pedido chega pelo aplicativo. O cliente pede no balcao, liga, ou o
-- garcom anota na mesa. Sem um jeito de lancar, essa venda ficava fora do
-- sistema: fora da fila da cozinha, fora do caixa, fora do estoque.
--
-- `lancar_pedido` monta o pedido com as mesmas regras de preco do aplicativo
-- (via `app.inserir_item_no_pedido`), mas com o que muda quando quem lanca e
-- a loja:
--
--   nasce aceito      a loja nao precisa aceitar o proprio pedido; ele entra
--                     direto em "confirmado", sem sino e sem aviso.
--   sem comissao      a venda e da loja, nao veio pelo aplicativo — a
--                     plataforma nao retem nada. Marcado em `placed_by_store`
--                     para que a edicao, depois, nao volte a cobrar.
--   sem minimo        pedido minimo existe para a entrega do aplicativo valer
--                     a pena; no balcao, uma agua e uma venda.
--   sem cliente       quem pede no balcao nao tem conta. `customer_id` fica
--                     nulo, e o nome e o que a loja digitar.
--   endereco digitado na entrega por telefone, o endereco e o que o cliente
--                     disse, e nao um cadastro.
-- =============================================================================

alter table orders
  add column if not exists placed_by_store boolean not null default false;

comment on column orders.placed_by_store is
  'Lancado pela propria loja (balcao, telefone, garcom), e nao pelo aplicativo. Nao paga comissao.';

-- -----------------------------------------------------------------------------
-- O recalculo da edicao passa a respeitar o pedido da loja
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

  -- Pedido da loja nao paga comissao, nem depois de editado.
  select case when v_pedido.placed_by_store then 0 else commission_bps end
    into v_bps
    from restaurants where id = v_pedido.restaurant_id;

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

  update payments
     set amount_cents = v_total,
         change_for_cents = case when change_for_cents >= v_total then change_for_cents end
   where order_id = p_pedido and status = 'pending';
end;
$$;

-- -----------------------------------------------------------------------------
-- Lancar
--
-- p_dados:
--   {"tipo": "pickup" | "dine_in" | "delivery",
--    "cliente": text, "telefone": text,
--    "mesa_id": uuid,                    mesa cadastrada, ou
--    "mesa": text,                       o que o garcom escreveu
--    "endereco": {"rua", "numero", "complemento", "bairro", "cidade", "cep"},
--    "forma": payment_method,
--    "troco_para_cents": bigint,
--    "receber_agora": boolean,           ja pagou no balcao
--    "observacao": text,
--    "itens": [ ...mesmo formato de editar_pedido... ]}
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

    v_frete := case
      when v_restaurante.free_delivery_above_cents is not null
       and v_subtotal >= v_restaurante.free_delivery_above_cents then 0
      else v_restaurante.delivery_fee_cents
    end;

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

revoke all on function public.lancar_pedido(uuid, jsonb) from public;
grant execute on function public.lancar_pedido(uuid, jsonb) to authenticated;

comment on function public.lancar_pedido is
  'A loja lanca um pedido de balcao, mesa ou entrega por telefone. Mesmas regras de preco do aplicativo, sem comissao, ja aceito.';
