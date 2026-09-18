-- =============================================================================
-- "Promoções", ao lado de "Tudo".
--
-- A vitrine filtra por categoria da plataforma. Faltava o filtro que o cliente
-- com fome e sem pressa realmente usa: quem esta com preco bom AGORA.
--
-- A pergunta e do banco, e nao do celular. Responder no aplicativo exigiria
-- baixar o cardapio inteiro de trinta lojas para descobrir que duas tem
-- promocao — trinta consultas para jogar fora vinte e oito.
--
-- Coluna calculada, como `aberto_agora`: o PostgREST a expoe em `select` e em
-- filtro, entao a lista ja chega recortada.
-- =============================================================================

create or replace function public.tem_promocao(restaurants)
returns boolean
language sql
stable
as $$
  select exists (
    select 1
    from products p
    where p.restaurant_id = $1.id
      and p.deleted_at is null
      and p.is_available
      and p.promo_price_cents is not null
      -- A janela manda. Promocao vencida e preco cheio, e anunciar o contrario
      -- e o cliente chegando na tela e vendo outro valor.
      and (p.promo_starts_at is null or now() >= p.promo_starts_at)
      and (p.promo_ends_at is null or now() <= p.promo_ends_at)
  );
$$;

comment on function public.tem_promocao(restaurants) is
  'Coluna calculada: a loja tem ao menos um produto em promocao valendo agora?';

grant execute on function public.tem_promocao(restaurants) to anon, authenticated;

-- Sem indice, cada linha da vitrine varre os produtos da loja. Com trinta
-- lojas isso nao aparece; com trezentas, aparece na primeira tela que o
-- cliente abre.
create index if not exists products_promocao_idx
  on products (restaurant_id)
  where deleted_at is null and is_available and promo_price_cents is not null;
