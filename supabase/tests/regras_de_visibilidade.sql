-- =============================================================================
-- Tronvix Facil - quem enxerga o que
--
-- Estes testes consultam como o papel `authenticated`, nao como superusuario.
-- E a diferenca que importa: superusuario ignora RLS, entao um teste rodado
-- como postgres da "passou" para uma politica quebrada. Foi assim que a
-- recursao entre orders e deliveries atravessou a suite inteira sem aparecer,
-- ate a primeira consulta do aplicativo contra o Supabase de verdade.
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

-- -----------------------------------------------------------------------------
-- Cenario: dois estabelecimentos, dois clientes, um entregador
-- -----------------------------------------------------------------------------
insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'dono@burger.test'),
  ('22222222-2222-2222-2222-222222222222', 'cliente@teste.test'),
  ('33333333-3333-3333-3333-333333333333', 'outro@teste.test'),
  ('44444444-4444-4444-4444-444444444444', 'entregador@teste.test');

insert into restaurants (id, slug, name, status, is_open, delivery_fee_cents)
values ('aaaaaaaa-0000-0000-0000-000000000001', 'burger', 'Burger House', 'approved', true, 700);

insert into restaurant_members (restaurant_id, user_id, role)
values ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'owner');

-- O papel na plataforma e coisa do administrador (app.guard_platform_role); o
-- que decide se alguem e entregador, para a RLS, e a linha em couriers.
-- Entregador DO estabelecimento: e assim que o produto opera por omissao.
-- A fila de corridas nao e da plataforma; e de quem emprega.
insert into couriers (id, user_id, restaurant_id, status, availability)
values ('77777777-0000-0000-0000-000000000001',
        '44444444-4444-4444-4444-444444444444',
        'aaaaaaaa-0000-0000-0000-000000000001', 'approved', 'online');

insert into categories (id, restaurant_id, name)
values ('cccccccc-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'Lanches');

insert into products (id, restaurant_id, category_id, name, price_cents)
values ('dddddddd-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000001', 'X-Salada', 2500);

insert into addresses (id, user_id, street, number, district, city, state, postal_code)
values ('bbbbbbbb-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222',
        'Rua das Flores', '100', 'Centro', 'Vitoria', 'ES', '29010000');

-- O pedido nasce pelo caminho de verdade: fechar_pedido.
do $$
declare v_cart uuid;
begin
  perform set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);

  insert into carts (user_id, restaurant_id)
  values ('22222222-2222-2222-2222-222222222222', 'aaaaaaaa-0000-0000-0000-000000000001')
  returning id into v_cart;
  insert into cart_items (cart_id, product_id, quantity)
  values (v_cart, 'dddddddd-0000-0000-0000-000000000001', 1);

  perform public.fechar_pedido(
    v_cart, 'delivery', 'cash', 'on_delivery',
    'bbbbbbbb-0000-0000-0000-000000000001'::uuid);
end;
$$;

-- A corrida vai para a fila, como o balcao faz ao despachar.
update deliveries set status = 'searching_courier';

grant usage on schema public to authenticated;
grant select on all tables in schema public to authenticated;

-- Conta linhas visiveis para um usuario, consultando como `authenticated`.
create or replace function pg_temp.visiveis(p_user uuid, p_tabela text)
returns int
language plpgsql
as $$
declare n int;
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  set local role authenticated;
  execute format('select count(*) from %I', p_tabela) into n;
  reset role;
  return n;
end;
$$;

-- -----------------------------------------------------------------------------
-- O ciclo nao existe mais
-- -----------------------------------------------------------------------------
do $$
begin
  -- Antes da correcao, qualquer uma destas linhas morria com
  -- "infinite recursion detected in policy for relation ...".
  perform pg_temp.visiveis('22222222-2222-2222-2222-222222222222', 'deliveries');
  perform pg_temp.conferir(true, 'consultar deliveries como cliente nao recorre');

  perform pg_temp.visiveis('22222222-2222-2222-2222-222222222222', 'orders');
  perform pg_temp.conferir(true, 'consultar orders como cliente nao recorre');

  perform pg_temp.visiveis('44444444-4444-4444-4444-444444444444', 'deliveries');
  perform pg_temp.conferir(true, 'consultar deliveries como entregador nao recorre');
end;
$$;

-- -----------------------------------------------------------------------------
-- E quem ve o que continua igual
-- -----------------------------------------------------------------------------
do $$
begin
  perform pg_temp.conferir(
    pg_temp.visiveis('22222222-2222-2222-2222-222222222222', 'orders') = 1,
    'o cliente ve o proprio pedido');
  perform pg_temp.conferir(
    pg_temp.visiveis('33333333-3333-3333-3333-333333333333', 'orders') = 0,
    'outro cliente nao ve o pedido alheio');
  perform pg_temp.conferir(
    pg_temp.visiveis('11111111-1111-1111-1111-111111111111', 'orders') = 1,
    'a equipe do estabelecimento ve o pedido');

  perform pg_temp.conferir(
    pg_temp.visiveis('22222222-2222-2222-2222-222222222222', 'deliveries') = 1,
    'o cliente ve a entrega do proprio pedido');
  perform pg_temp.conferir(
    pg_temp.visiveis('33333333-3333-3333-3333-333333333333', 'deliveries') = 0,
    'outro cliente nao ve a entrega alheia');
  perform pg_temp.conferir(
    pg_temp.visiveis('44444444-4444-4444-4444-444444444444', 'deliveries') = 1,
    'entregador do estabelecimento ve a corrida na fila');

  perform pg_temp.conferir(
    pg_temp.visiveis('22222222-2222-2222-2222-222222222222', 'order_items') = 1,
    'o cliente ve os itens do proprio pedido');
  perform pg_temp.conferir(
    pg_temp.visiveis('33333333-3333-3333-3333-333333333333', 'order_items') = 0,
    'outro cliente nao ve os itens alheios');
  perform pg_temp.conferir(
    pg_temp.visiveis('22222222-2222-2222-2222-222222222222', 'payments') = 1,
    'o cliente ve o proprio pagamento');
  perform pg_temp.conferir(
    pg_temp.visiveis('33333333-3333-3333-3333-333333333333', 'payments') = 0,
    'outro cliente nao ve o pagamento alheio');
end;
$$;

-- O entregador ainda nao aprovado nao enxerga a fila.
--
-- Nasce 'pending' em vez de ser rebaixado depois: app.guard_courier_platform_fields
-- so deixa a plataforma mexer em status, e com razao - senao qualquer um se
-- aprovaria.
insert into auth.users (id, email)
values ('66666666-6666-6666-6666-666666666666', 'novato@teste.test');

insert into couriers (id, user_id, restaurant_id, status, availability)
values ('77777777-0000-0000-0000-000000000002',
        '66666666-6666-6666-6666-666666666666',
        'aaaaaaaa-0000-0000-0000-000000000001', 'pending', 'offline');

do $$
begin
  perform pg_temp.conferir(
    pg_temp.visiveis('66666666-6666-6666-6666-666666666666', 'deliveries') = 0,
    'entregador ainda nao aprovado nao ve a fila de corridas');
end;
$$;

rollback;
