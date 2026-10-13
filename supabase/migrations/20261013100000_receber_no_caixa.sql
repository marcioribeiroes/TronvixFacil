-- =============================================================================
-- Tronvix Facil - receber o pagamento no caixa
--
-- Pagamento "na entrega" (dinheiro, maquininha, vale, Pix na hora) nascia
-- pendente e morria pendente: nada na loja registrava que o dinheiro tinha
-- entrado. Sem isso nao existe caixa — so a soma do que foi pedido, que nao e
-- a soma do que foi recebido.
--
-- `receber_pagamento` e o ato de quem esta no balcao: o cliente pagou, e
-- pagou DESTA forma. A forma pode mudar na hora — pediu em dinheiro, pagou no
-- cartao —, e o caixa tem de bater com a gaveta e com a maquininha, nao com o
-- que foi escolhido no aplicativo.
-- =============================================================================

create or replace function public.receber_pagamento(
  p_pedido uuid,
  p_forma payment_method
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pedido orders;
  v_pagamento payments;
begin
  select * into v_pedido from orders where id = p_pedido;
  if v_pedido.id is null then
    raise exception 'Pedido nao encontrado.' using errcode = 'no_data_found';
  end if;

  if not (app.is_member(v_pedido.restaurant_id) or app.is_platform_admin()) then
    raise exception 'Somente o estabelecimento registra o recebimento.'
      using errcode = 'insufficient_privilege';
  end if;

  -- Pedido cancelado ou recusado nao entra no caixa: o dinheiro, se veio,
  -- volta para o cliente.
  if v_pedido.status in ('cancelled', 'rejected') then
    raise exception 'Este pedido foi cancelado.' using errcode = 'check_violation';
  end if;

  select * into v_pagamento from payments where order_id = p_pedido limit 1;
  if v_pagamento.id is null then
    raise exception 'Este pedido nao tem pagamento registrado.' using errcode = 'no_data_found';
  end if;

  -- Pagamento pelo site tem caminho proprio (`confirmar_pix`, ou o gateway).
  -- Dois caminhos para o mesmo dinheiro e como se conta a venda duas vezes.
  if v_pagamento.timing <> 'on_delivery' then
    raise exception 'Este pedido e pago pelo site.' using errcode = 'check_violation';
  end if;
  if v_pagamento.status = 'paid' then
    raise exception 'Este pedido ja foi recebido.' using errcode = 'check_violation';
  end if;

  update payments
     set status = 'paid',
         paid_at = now(),
         method = p_forma,
         -- Troco so existe em dinheiro (payments_change_only_for_cash). Quem
         -- pediu troco e pagou no cartao nao precisa mais dele.
         change_for_cents = case when p_forma = 'cash' then change_for_cents end
   where id = v_pagamento.id;
end;
$$;

revoke all on function public.receber_pagamento(uuid, payment_method) from public;
grant execute on function public.receber_pagamento(uuid, payment_method) to authenticated;

comment on function public.receber_pagamento is
  'O balcao registra que recebeu o pagamento feito na entrega, na forma em que ele de fato veio. E o que alimenta o caixa.';

-- O caixa se atualiza sozinho. Receber muda so `payments`, e sem a tabela na
-- publicacao o recebimento feito no celular nao aparecia no caixa do painel.
-- A linha de pagamento ja e visivel a quem ve o pedido; nada novo viaja.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'payments'
  ) then
    alter publication supabase_realtime add table public.payments;
  end if;
end;
$$;
