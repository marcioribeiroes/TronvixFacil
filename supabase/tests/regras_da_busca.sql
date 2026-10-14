-- =============================================================================
-- Tronvix Facil - busca na vitrine
--
-- Como rodar:  npm run db:test
-- =============================================================================

\set ON_ERROR_STOP on

begin;

create or replace function pg_temp.conferir(p_condicao boolean, p_contexto text)
returns void language plpgsql as $$
begin
  if not coalesce(p_condicao, false) then
    raise exception 'FALHOU: %', p_contexto;
  end if;
  raise notice 'ok - %', p_contexto;
end;
$$;

insert into restaurants (id, slug, name, description, status, is_open)
values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'acai', 'Açaí Mania', 'Açaí cremoso', 'approved', true),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'lanche', 'Lanchonete do Zé', 'O lanche de sempre', 'approved', true),
  ('aaaaaaaa-0000-0000-0000-000000000003', 'pendente', 'Pizzaria Pendente', null, 'pending', true);

insert into categories (id, restaurant_id, name) values
  ('cccccccc-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000002', 'Pratos'),
  ('cccccccc-0000-0000-0000-000000000003', 'aaaaaaaa-0000-0000-0000-000000000003', 'Pizzas');

insert into products (restaurant_id, category_id, name, price_cents, is_available) values
  ('aaaaaaaa-0000-0000-0000-000000000002', 'cccccccc-0000-0000-0000-000000000002', 'Pizza Brotinho', 2000, true),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'cccccccc-0000-0000-0000-000000000002', 'Pizza Fora do Ar', 2000, false),
  ('aaaaaaaa-0000-0000-0000-000000000003', 'cccccccc-0000-0000-0000-000000000003', 'Pizza Grande', 4000, true);

do $$
begin
  perform pg_temp.conferir(
    (select array_agg(restaurant_id) from buscar_na_vitrine('acai'))
      = array['aaaaaaaa-0000-0000-0000-000000000001'::uuid],
    '"acai" acha "Açaí Mania": acento nao importa');

  perform pg_temp.conferir(
    (select pratos from buscar_na_vitrine('PIZZA')
      where restaurant_id = 'aaaaaaaa-0000-0000-0000-000000000002') = array['Pizza Brotinho'],
    'quem procura pizza acha a lanchonete pelo prato, e so o prato que esta no ar');

  perform pg_temp.conferir(
    not exists (select 1 from buscar_na_vitrine('pizza')
                 where restaurant_id = 'aaaaaaaa-0000-0000-0000-000000000003'),
    'loja ainda nao aprovada nao aparece na busca');

  perform pg_temp.conferir(
    not exists (select 1 from buscar_na_vitrine('a')),
    'uma letra so nao busca nada');

  perform pg_temp.conferir(
    not exists (select 1 from buscar_na_vitrine('%')) and not exists (select 1 from buscar_na_vitrine('__')),
    'curinga digitado e texto, nao "tudo"');
end;
$$;

rollback;
