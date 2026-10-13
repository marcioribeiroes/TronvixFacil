-- =============================================================================
-- Tronvix Facil - receber no caixa
--
-- O caixa so vale se bater com a gaveta: recebe quem e da loja, uma vez so, na
-- forma em que o dinheiro de fato veio, e nunca o que ja foi pago pelo site.
--
-- Como rodar:  npm run db:test
-- =============================================================================

\set ON_ERROR_STOP on

begin;

create or replace function pg_temp.conferir(p_condicao boolean, p_contexto text)
returns void language plpgsql as $$
begin
  if not p_condicao then
    raise exception 'FALHOU: %', p_contexto;
  end if;
  raise notice 'ok - %', p_contexto;
end;
$$;

create or replace function pg_temp.deve_falhar(p_sql text, p_contexto text)
returns void language plpgsql as $$
begin
  execute p_sql;
  raise exception 'FALHOU: % deveria ter sido rejeitado, mas passou.', p_contexto;
exception
  when check_violation or insufficient_privilege or no_data_found then
    raise notice 'ok - rejeitado como esperado: %', p_contexto;
end;
$$;

create or replace function pg_temp.virar(p_user uuid)
returns void language sql as $$
  select set_config('request.jwt.claim.sub', p_user::text, true);
$$;

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'dono@teste.test'),
  ('22222222-2222-2222-2222-222222222222', 'cliente@teste.test'),
  ('33333333-3333-3333-3333-333333333333', 'estranho@teste.test');

insert into restaurants (id, slug, name, status, is_open, min_order_cents)
values ('aaaaaaaa-0000-0000-0000-000000000001', 'loja', 'A Loja', 'approved', true, 0);

insert into restaurant_members (restaurant_id, user_id, role)
values ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'owner');

insert into categories (id, restaurant_id, name)
values ('cccccccc-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'Pratos');

insert into products (id, restaurant_id, category_id, name, price_cents)
values ('dddddddd-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000001', 'Prato', 3000);

-- Um pedido de retirada, a pagar em dinheiro no balcao.
create or replace function pg_temp.pedido()
returns uuid language plpgsql as $$
declare v_cart uuid;
begin
  perform pg_temp.virar('22222222-2222-2222-2222-222222222222');
  delete from carts where user_id = '22222222-2222-2222-2222-222222222222';
  insert into carts (user_id, restaurant_id)
  values ('22222222-2222-2222-2222-222222222222', 'aaaaaaaa-0000-0000-0000-000000000001')
  returning id into v_cart;
  insert into cart_items (cart_id, product_id, quantity)
  values (v_cart, 'dddddddd-0000-0000-0000-000000000001', 1);
  return fechar_pedido(v_cart, 'pickup', 'cash', 'on_delivery');
end;
$$;

-- -----------------------------------------------------------------------------
-- A loja recebe, e o caixa registra
-- -----------------------------------------------------------------------------
do $$
declare v_id uuid; v_p payments;
begin
  v_id := pg_temp.pedido();

  perform pg_temp.virar('11111111-1111-1111-1111-111111111111');
  perform receber_pagamento(v_id, 'cash');

  select * into v_p from payments where order_id = v_id;
  perform pg_temp.conferir(v_p.status = 'paid', 'o pagamento fica pago');
  perform pg_temp.conferir(v_p.paid_at is not null,
    'e a hora do recebimento e carimbada pelo banco');
  perform pg_temp.conferir(
    (select status from orders where id = v_id) = 'received',
    'receber nao mexe na fila da cozinha');

  perform pg_temp.deve_falhar(
    format($q$select receber_pagamento('%s', 'cash')$q$, v_id),
    'receber duas vezes o mesmo pedido');
end;
$$;

-- -----------------------------------------------------------------------------
-- Pediu em dinheiro, pagou no cartao
-- -----------------------------------------------------------------------------
do $$
declare v_id uuid; v_p payments;
begin
  v_id := pg_temp.pedido();
  update payments set change_for_cents = 5000 where order_id = v_id;

  perform pg_temp.virar('11111111-1111-1111-1111-111111111111');
  perform receber_pagamento(v_id, 'debit_card');

  select * into v_p from payments where order_id = v_id;
  perform pg_temp.conferir(v_p.method = 'debit_card',
    'o caixa guarda a forma em que o dinheiro veio, nao a que foi pedida');
  perform pg_temp.conferir(v_p.change_for_cents is null,
    'e o troco some, porque cartao nao tem troco');
end;
$$;

-- -----------------------------------------------------------------------------
-- O que nao se recebe
-- -----------------------------------------------------------------------------
do $$
declare v_id uuid;
begin
  v_id := pg_temp.pedido();

  perform pg_temp.virar('22222222-2222-2222-2222-222222222222');
  perform pg_temp.deve_falhar(
    format($q$select receber_pagamento('%s', 'cash')$q$, v_id),
    'o cliente marcando o proprio pedido como pago');

  perform pg_temp.virar('33333333-3333-3333-3333-333333333333');
  perform pg_temp.deve_falhar(
    format($q$select receber_pagamento('%s', 'cash')$q$, v_id),
    'um estranho recebendo por uma loja que nao e dele');

  perform pg_temp.virar('22222222-2222-2222-2222-222222222222');
  perform cancelar_pedido(v_id);

  perform pg_temp.virar('11111111-1111-1111-1111-111111111111');
  perform pg_temp.deve_falhar(
    format($q$select receber_pagamento('%s', 'cash')$q$, v_id),
    'receber um pedido cancelado');
end;
$$;

do $$
declare v_id uuid;
begin
  v_id := pg_temp.pedido();
  -- Como se tivesse sido pago pelo site: esse dinheiro tem outro caminho.
  update payments set timing = 'online', method = 'pix' where order_id = v_id;

  perform pg_temp.virar('11111111-1111-1111-1111-111111111111');
  perform pg_temp.deve_falhar(
    format($q$select receber_pagamento('%s', 'cash')$q$, v_id),
    'receber no caixa o que foi pago pelo site');
end;
$$;

-- =============================================================================
-- Fundo de caixa e sangria
-- =============================================================================

insert into auth.users (id, email) values
  ('44444444-4444-4444-4444-444444444444', 'atendente@teste.test');
insert into restaurant_members (restaurant_id, user_id, role)
values ('aaaaaaaa-0000-0000-0000-000000000001', '44444444-4444-4444-4444-444444444444', 'staff');

-- Os testes acima receberam pedidos em dinheiro. Para o saldo partir do zero,
-- os recebimentos ficam num dia que nao e hoje.
update payments set paid_at = now() - interval '3 days' where status = 'paid';

do $$
declare
  v_loja constant uuid := 'aaaaaaaa-0000-0000-0000-000000000001';
  v_fundo uuid; v_sangria uuid; v_pedido uuid; v_mov jsonb;
begin
  perform pg_temp.virar('44444444-4444-4444-4444-444444444444');

  perform pg_temp.conferir(app.cash_in_drawer(v_loja, app.business_date(v_loja, now())) = 0,
    'sem fundo e sem venda, a gaveta comeca vazia');

  perform pg_temp.deve_falhar(
    format($q$select registrar_sangria('%s', 100, 'Cofre')$q$, v_loja),
    'sangria de gaveta vazia');

  v_fundo := registrar_fundo_de_caixa(v_loja, 10000);
  perform pg_temp.conferir(v_fundo is not null, 'o atendente registra o fundo de caixa');

  perform pg_temp.deve_falhar(
    format($q$select registrar_fundo_de_caixa('%s', 5000)$q$, v_loja),
    'segundo fundo de caixa no mesmo dia');

  -- Uma venda em dinheiro entra na gaveta.
  v_pedido := pg_temp.pedido();
  perform pg_temp.virar('44444444-4444-4444-4444-444444444444');
  perform receber_pagamento(v_pedido, 'cash');

  perform pg_temp.conferir(app.cash_in_drawer(v_loja, app.business_date(v_loja, now())) = 13000,
    'gaveta = fundo + recebido em dinheiro');

  perform pg_temp.deve_falhar(
    format($q$select registrar_sangria('%s', 5000, '')$q$, v_loja),
    'sangria sem motivo');
  perform pg_temp.deve_falhar(
    format($q$select registrar_sangria('%s', 13001, 'Cofre')$q$, v_loja),
    'sangria maior que o dinheiro na gaveta');

  v_sangria := registrar_sangria(v_loja, 8000, 'Deposito no banco');
  perform pg_temp.conferir(app.cash_in_drawer(v_loja, app.business_date(v_loja, now())) = 5000,
    'a sangria sai da gaveta');

  perform pg_temp.deve_falhar(
    format($q$select cancelar_movimento_de_caixa('%s')$q$, v_sangria),
    'atendente cancelando lancamento do caixa');

  perform pg_temp.virar('11111111-1111-1111-1111-111111111111');
  perform cancelar_movimento_de_caixa(v_sangria);
  perform pg_temp.conferir(app.cash_in_drawer(v_loja, app.business_date(v_loja, now())) = 13000,
    'sangria cancelada volta para a gaveta');
  perform pg_temp.conferir(
    (select cancelled_by from cash_movements where id = v_sangria) = '11111111-1111-1111-1111-111111111111',
    'e fica registrado quem cancelou — a linha nao some');

  perform cancelar_movimento_de_caixa(v_fundo);
  perform registrar_fundo_de_caixa(v_loja, 12000);
  perform pg_temp.conferir(true, 'fundo cancelado pode ser registrado de novo');

  v_mov := movimento_do_caixa(v_loja);
  perform pg_temp.conferir((v_mov ->> 'dinheiro_na_gaveta_cents')::bigint = 15000,
    'o movimento do dia traz o saldo da gaveta');
  perform pg_temp.conferir(jsonb_array_length(v_mov -> 'lancamentos') = 3,
    'e os lancamentos, inclusive os cancelados');
  perform pg_temp.conferir(jsonb_array_length(v_mov -> 'recebimentos') = 1,
    'e so os recebimentos do dia');
  perform pg_temp.conferir((v_mov ->> 'hoje')::boolean, 'sem dia informado, e o de hoje');

  -- Direto na tabela nao entra: pularia o saldo e o fundo unico.
  perform pg_temp.deve_falhar(
    format($q$set local role authenticated; insert into cash_movements
      (restaurant_id, type, amount_cents, note, business_date)
      values ('%s', 'withdrawal', 999999, 'Sumiu', current_date)$q$, v_loja),
    'sangria inserida direto na tabela');
  reset role;

  perform pg_temp.virar('33333333-3333-3333-3333-333333333333');
  perform pg_temp.deve_falhar(
    format($q$select movimento_do_caixa('%s')$q$, v_loja),
    'um estranho olhando o caixa da loja');
end;
$$;

rollback;
