-- =============================================================================
-- Tronvix Facil - o filtro de promocoes da vitrine
--
-- "Tem promocao agora?" e pergunta do banco: responder no celular exigiria
-- baixar o cardapio de trinta lojas para descobrir que duas tem. E a resposta
-- tem de respeitar a janela — promocao vencida e preco cheio, e anunciar o
-- contrario e o cliente chegando na tela e vendo outro valor.
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

create or replace function pg_temp.promocao(p_slug text)
returns boolean language sql as $$
  select tem_promocao(r) from restaurants r where r.slug = p_slug;
$$;

insert into restaurants (id, slug, name, status, is_open) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'com-promo', 'Com Promocao', 'approved', true),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'sem-promo', 'Sem Promocao', 'approved', true),
  ('aaaaaaaa-0000-0000-0000-000000000003', 'promo-vencida', 'Promo Vencida', 'approved', true),
  ('aaaaaaaa-0000-0000-0000-000000000004', 'promo-futura', 'Promo Futura', 'approved', true),
  ('aaaaaaaa-0000-0000-0000-000000000005', 'promo-esgotada', 'Promo Esgotada', 'approved', true);

insert into categories (id, restaurant_id, name)
select ('cccccccc-0000-0000-0000-00000000000' || n)::uuid,
       ('aaaaaaaa-0000-0000-0000-00000000000' || n)::uuid,
       'Pratos'
  from generate_series(1, 5) n;

insert into products (restaurant_id, category_id, name, price_cents,
                      promo_price_cents, promo_starts_at, promo_ends_at, is_available)
values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-000000000001',
   'Em promocao', 5000, 3900, null, null, true),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'cccccccc-0000-0000-0000-000000000002',
   'Preco cheio', 5000, null, null, null, true),
  ('aaaaaaaa-0000-0000-0000-000000000003', 'cccccccc-0000-0000-0000-000000000003',
   'Promocao de ontem', 5000, 3900, now() - interval '3 days', now() - interval '1 day', true),
  ('aaaaaaaa-0000-0000-0000-000000000004', 'cccccccc-0000-0000-0000-000000000004',
   'Promocao de amanha', 5000, 3900, now() + interval '1 day', now() + interval '3 days', true),
  -- Produto fora do ar: a promocao dele nao anuncia nada, porque ninguem
  -- consegue comprar.
  ('aaaaaaaa-0000-0000-0000-000000000005', 'cccccccc-0000-0000-0000-000000000005',
   'Acabou', 5000, 3900, null, null, false);

do $$
begin
  perform pg_temp.conferir(pg_temp.promocao('com-promo'),
    'loja com promocao valendo aparece no filtro');

  perform pg_temp.conferir(not pg_temp.promocao('sem-promo'),
    'loja sem promocao nenhuma nao aparece');

  perform pg_temp.conferir(not pg_temp.promocao('promo-vencida'),
    'promocao que terminou ontem nao conta: e preco cheio de novo');

  perform pg_temp.conferir(not pg_temp.promocao('promo-futura'),
    'promocao que comeca amanha tambem nao: ainda nao vale');

  perform pg_temp.conferir(not pg_temp.promocao('promo-esgotada'),
    'produto indisponivel nao anuncia promocao: ninguem consegue comprar');
end;
$$;

-- E some quando a promocao sai.
do $$
begin
  update products set promo_price_cents = null
   where restaurant_id = 'aaaaaaaa-0000-0000-0000-000000000001';

  perform pg_temp.conferir(not pg_temp.promocao('com-promo'),
    'tirar a promocao tira a loja do filtro na hora');
end;
$$;

rollback;
