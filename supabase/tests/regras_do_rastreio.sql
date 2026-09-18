-- =============================================================================
-- Tronvix Facil - quem pode ver onde o entregador esta
--
-- Posicao de pessoa e o dado mais sensivel deste sistema. Estes testes cuidam
-- das duas pontas: que o cliente veja o entregador do pedido dele enquanto a
-- comida esta a caminho, e que ninguem mais veja nunca.
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

create or replace function pg_temp.virar(p_user uuid)
returns void language sql as $$
  select set_config('request.jwt.claim.sub', p_user::text, true);
$$;

-- -----------------------------------------------------------------------------
-- Cenario: um pedido a caminho
-- -----------------------------------------------------------------------------
insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'dono@teste.test'),
  ('22222222-2222-2222-2222-222222222222', 'cliente@teste.test'),
  ('33333333-3333-3333-3333-333333333333', 'bisbilhoteiro@teste.test'),
  ('44444444-4444-4444-4444-444444444444', 'entregador@teste.test'),
  ('55555555-5555-5555-5555-555555555555', 'outro.entregador@teste.test');

insert into restaurants (id, slug, name, status, is_open, delivery_fee_cents)
values ('aaaaaaaa-0000-0000-0000-000000000001', 'burger', 'Burger House', 'approved', true, 700);

insert into restaurant_members (restaurant_id, user_id, role)
values ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'owner');

insert into couriers (id, user_id, restaurant_id, status, availability) values
  ('77777777-0000-0000-0000-000000000001', '44444444-4444-4444-4444-444444444444',
   'aaaaaaaa-0000-0000-0000-000000000001', 'approved', 'online'),
  ('77777777-0000-0000-0000-000000000002', '55555555-5555-5555-5555-555555555555',
   'aaaaaaaa-0000-0000-0000-000000000001', 'approved', 'online');

insert into categories (id, restaurant_id, name)
values ('cccccccc-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'Lanches');

insert into products (id, restaurant_id, category_id, name, price_cents)
values ('dddddddd-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000001', 'X-Salada', 2500);

insert into addresses (id, user_id, street, number, district, city, state, postal_code)
values ('bbbbbbbb-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222',
        'Rua T 30', '120', 'Setor Bueno', 'Goiania', 'GO', '74210060');

do $$
declare v_cart uuid;
begin
  perform pg_temp.virar('22222222-2222-2222-2222-222222222222');
  insert into carts (user_id, restaurant_id)
  values ('22222222-2222-2222-2222-222222222222', 'aaaaaaaa-0000-0000-0000-000000000001')
  returning id into v_cart;
  insert into cart_items (cart_id, product_id, quantity)
  values (v_cart, 'dddddddd-0000-0000-0000-000000000001', 1);
  perform public.fechar_pedido(v_cart, 'delivery', 'cash', 'on_delivery',
                               'bbbbbbbb-0000-0000-0000-000000000001'::uuid);
end;
$$;

-- A corrida sai e e aceita.
update deliveries set status = 'searching_courier';
update deliveries set courier_id = '77777777-0000-0000-0000-000000000001',
                      status = 'assigned';

-- -----------------------------------------------------------------------------
-- O entregador publica
-- -----------------------------------------------------------------------------
do $$
declare v_pedido uuid := (select id from orders limit 1);
begin
  perform pg_temp.virar('44444444-4444-4444-4444-444444444444');
  perform public.publicar_posicao(-16.7045, -49.2726);

  perform pg_temp.conferir(
    (select current_latitude from couriers
      where id = '77777777-0000-0000-0000-000000000001') = -16.7045,
    'o entregador publica a propria posicao');

  perform pg_temp.conferir(
    (select location_updated_at from couriers
      where id = '77777777-0000-0000-0000-000000000001') is not null,
    'a hora da medida vem do servidor, nao do relogio do celular');

  -- Publicar nao pode mexer na posicao de outro entregador.
  perform pg_temp.conferir(
    (select current_latitude from couriers
      where id = '77777777-0000-0000-0000-000000000002') is null,
    'publicar mexe so na propria linha');
end;
$$;

-- Quem nao e entregador nao publica.
do $$
begin
  perform pg_temp.virar('22222222-2222-2222-2222-222222222222');
  begin
    perform public.publicar_posicao(-16.0, -49.0);
    raise exception 'FALHOU: um cliente publicou posicao de entregador.';
  exception
    when insufficient_privilege then
      raise notice 'ok - rejeitado como esperado: cliente publicando posicao de entregador';
  end;
end;
$$;

-- -----------------------------------------------------------------------------
-- E quem pode perguntar
-- -----------------------------------------------------------------------------
do $$
declare v_pedido uuid := (select id from orders limit 1);
begin
  perform pg_temp.virar('22222222-2222-2222-2222-222222222222');
  perform pg_temp.conferir(
    (public.onde_esta_o_entregador(v_pedido) ->> 'latitude')::numeric = -16.7045,
    'o cliente ve onde esta o entregador do pedido dele');

  perform pg_temp.conferir(
    public.onde_esta_o_entregador(v_pedido) ? 'medido_em',
    'e ve de quando e a medida — posicao velha precisa poder ser dita');

  -- Tres campos. Nem um a mais.
  perform pg_temp.conferir(
    (select count(*) from jsonb_object_keys(
       public.onde_esta_o_entregador(v_pedido))) = 3,
    'a resposta tem tres campos: nada do cadastro do entregador vaza');

  perform pg_temp.virar('11111111-1111-1111-1111-111111111111');
  perform pg_temp.conferir(
    public.onde_esta_o_entregador(v_pedido) is not null,
    'o estabelecimento tambem acompanha a propria entrega');

  perform pg_temp.virar('33333333-3333-3333-3333-333333333333');
  perform pg_temp.conferir(
    public.onde_esta_o_entregador(v_pedido) is null,
    'quem nao tem nada com o pedido nao ve nada');

  perform pg_temp.virar('55555555-5555-5555-5555-555555555555');
  perform pg_temp.conferir(
    public.onde_esta_o_entregador(v_pedido) is null,
    'nem o colega entregador que nao pegou esta corrida');
end;
$$;

-- -----------------------------------------------------------------------------
-- Acabou a corrida, acabou o rastreio
-- -----------------------------------------------------------------------------
do $$
declare v_pedido uuid := (select id from orders limit 1);
begin
  update deliveries set status = 'heading_to_restaurant';
  update deliveries set status = 'picked_up';
  update deliveries set status = 'heading_to_customer';

  perform pg_temp.virar('22222222-2222-2222-2222-222222222222');
  perform pg_temp.conferir(
    public.onde_esta_o_entregador(v_pedido) is not null,
    'durante a corrida inteira o cliente continua vendo');

  update deliveries set status = 'delivered';

  perform pg_temp.conferir(
    public.onde_esta_o_entregador(v_pedido) is null,
    'entregue, o entregador some do mapa — ele parou de trabalhar para este cliente');

  -- E a posicao continua gravada na linha dele; o que muda e quem pode ver.
  perform pg_temp.conferir(
    (select current_latitude from couriers
      where id = '77777777-0000-0000-0000-000000000001') is not null,
    'a ultima posicao continua no cadastro, so deixa de ser respondida');
end;
$$;

rollback;
