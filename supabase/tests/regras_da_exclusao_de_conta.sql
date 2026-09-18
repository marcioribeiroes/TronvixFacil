-- =============================================================================
-- Tronvix Facil - apagar a propria conta
--
-- A conta sai; a venda fica. Essas duas frases brigam entre si, e e por isso
-- que esta regra existe: apagar demais tira o faturamento de ontem de um
-- restaurante que nao fez nada; apagar de menos deixa nome e telefone de quem
-- pediu para sair.
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
  ('33333333-3333-3333-3333-333333333333', 'motoboy@teste.test');

insert into restaurants (id, slug, name, status, is_open, min_order_cents)
values ('aaaaaaaa-0000-0000-0000-000000000001', 'loja', 'A Loja', 'approved', true, 0);

insert into restaurant_members (restaurant_id, user_id, role)
values ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'owner');

insert into couriers (user_id, status)
values ('33333333-3333-3333-3333-333333333333', 'approved');

insert into categories (id, restaurant_id, name)
values ('cccccccc-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'Pratos');

insert into products (id, restaurant_id, category_id, name, price_cents)
values ('dddddddd-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000001', 'Prato', 3000);

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
-- Sem sessao, ninguem apaga nada
-- -----------------------------------------------------------------------------
do $$
begin
  perform set_config('request.jwt.claim.sub', '', true);
  perform pg_temp.deve_falhar('select apagar_minha_conta()',
    'apagar conta sem estar autenticado');
end;
$$;

-- -----------------------------------------------------------------------------
-- Pedido em andamento segura a exclusao
-- -----------------------------------------------------------------------------
do $$
declare v_id uuid; v_passo text;
begin
  v_id := pg_temp.pedido();

  perform pg_temp.virar('22222222-2222-2222-2222-222222222222');
  perform pg_temp.deve_falhar('select apagar_minha_conta()',
    'apagar a conta com pedido em andamento — o balcao ficaria sem quem avisar');

  -- Encerrado o pedido, o caminho abre. O balcao anda passo a passo porque o
  -- banco recusa salto de status — e esta regra nao vai ser a que o contorna.
  perform pg_temp.virar('11111111-1111-1111-1111-111111111111');
  foreach v_passo in array array['confirmed', 'preparing', 'ready', 'delivered'] loop
    update orders set status = v_passo::order_status where id = v_id;
  end loop;
end;
$$;

-- -----------------------------------------------------------------------------
-- Dono de loja e entregador nao se apagam sozinhos
-- -----------------------------------------------------------------------------
do $$
begin
  perform pg_temp.virar('11111111-1111-1111-1111-111111111111');
  perform pg_temp.deve_falhar('select apagar_minha_conta()',
    'dono de estabelecimento apagando a propria conta');

  perform pg_temp.virar('33333333-3333-3333-3333-333333333333');
  perform pg_temp.deve_falhar('select apagar_minha_conta()',
    'entregador apagando a propria conta');
end;
$$;

-- -----------------------------------------------------------------------------
-- O cliente sai: some a pessoa, fica a venda
-- -----------------------------------------------------------------------------
do $$
declare
  v_id uuid;
  v_o orders;
  v_total bigint;
begin
  select id, total_cents into v_id, v_total
    from orders where customer_id = '22222222-2222-2222-2222-222222222222' limit 1;

  perform pg_temp.virar('22222222-2222-2222-2222-222222222222');
  insert into addresses (user_id, street, number, district, city, state, postal_code)
  values ('22222222-2222-2222-2222-222222222222', 'Rua A', '1', 'Centro', 'Goiania', 'GO', '74000000');

  perform apagar_minha_conta();

  perform pg_temp.conferir(
    not exists (select 1 from auth.users where id = '22222222-2222-2222-2222-222222222222'),
    'a credencial some do auth');
  perform pg_temp.conferir(
    not exists (select 1 from profiles where id = '22222222-2222-2222-2222-222222222222'),
    'o perfil some junto, por cascata');
  perform pg_temp.conferir(
    not exists (select 1 from addresses where user_id = '22222222-2222-2222-2222-222222222222'),
    'e os enderecos tambem');

  select * into v_o from orders where id = v_id;

  perform pg_temp.conferir(v_o.id is not null,
    'o pedido continua existindo: e a venda do restaurante, nao so do cliente');
  perform pg_temp.conferir(v_o.total_cents = v_total,
    'com o valor intacto — o faturamento de ontem nao muda porque alguem saiu');
  perform pg_temp.conferir(v_o.customer_id is null,
    'mas sem apontar para pessoa nenhuma');
  perform pg_temp.conferir(v_o.customer_name = 'Cliente removido',
    'o nome copiado no pedido e apagado');
  perform pg_temp.conferir(v_o.customer_phone is null,
    'e o telefone tambem');
  perform pg_temp.conferir(
    v_o.address_summary is null and v_o.address_postal_code is null
      and v_o.address_latitude is null and v_o.address_longitude is null,
    'a rua, o CEP e as coordenadas saem do pedido');
end;
$$;

rollback;
