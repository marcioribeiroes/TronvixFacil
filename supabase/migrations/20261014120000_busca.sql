-- =============================================================================
-- Tronvix Facil - busca na vitrine
--
-- O campo "Buscar restaurantes, lanches, pizzas..." do site nao fazia nada, e
-- o do aplicativo so achava loja pelo nome — e com acento: "acai" nao achava
-- "Acai Mania", e quem procurava "pizza" nao achava a lanchonete que vende
-- pizza.
--
-- `buscar_na_vitrine` acha a loja pelo nome, pela descricao, pela categoria
-- da plataforma ou por um prato do cardapio, sem diferenciar acento nem
-- maiuscula. Devolve tambem os pratos que bateram, para a vitrine mostrar POR
-- QUE a loja apareceu.
-- =============================================================================

create extension if not exists unaccent;

-- unaccent depende de dicionario e por isso nao e imutavel; o envelope fixa o
-- dicionario e o esquema, e deixa usar a funcao em qualquer lugar.
create or replace function app.sem_acento(p_texto text)
returns text
language sql
immutable
parallel safe
set search_path = public
as $$
  select lower(unaccent('unaccent', coalesce(p_texto, '')));
$$;

create or replace function public.buscar_na_vitrine(p_termo text)
returns table (restaurant_id uuid, pratos text[])
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_termo text := app.sem_acento(trim(coalesce(p_termo, '')));
  v_padrao text;
begin
  -- Uma letra acharia tudo; duas ja dizem alguma coisa ("x-", "pf").
  if length(v_termo) < 2 then
    return;
  end if;

  -- % e _ digitados sao texto, nao curinga.
  v_padrao := '%' || replace(replace(replace(v_termo, '\', '\\'), '%', '\%'), '_', '\_') || '%';

  return query
    with lojas as (
      select r.id from restaurants r
       where r.status = 'approved' and r.deleted_at is null
    ),
    por_prato as (
      select p.restaurant_id,
             (array_agg(p.name order by p.sold_count desc, p.name))[1:3] as pratos
        from products p
        join lojas l on l.id = p.restaurant_id
       where p.deleted_at is null
         and p.is_available
         and (app.sem_acento(p.name) like v_padrao
              or app.sem_acento(p.description) like v_padrao)
       group by p.restaurant_id
    ),
    por_loja as (
      select r.id as restaurant_id
        from restaurants r
        join lojas l on l.id = r.id
       where app.sem_acento(r.name) like v_padrao
          or app.sem_acento(r.description) like v_padrao
          or exists (
            select 1
              from restaurant_platform_categories rc
              join platform_categories c on c.id = rc.category_id
             where rc.restaurant_id = r.id
               and app.sem_acento(c.name) like v_padrao
          )
    )
    select coalesce(pl.restaurant_id, pp.restaurant_id),
           coalesce(pp.pratos, '{}')
      from por_loja pl
      full join por_prato pp on pp.restaurant_id = pl.restaurant_id;
end;
$$;

revoke all on function public.buscar_na_vitrine(text) from public;
grant execute on function public.buscar_na_vitrine(text) to anon, authenticated;

comment on function public.buscar_na_vitrine(text) is
  'Lojas aprovadas que batem com o termo pelo nome, descricao, categoria ou por um prato do cardapio — sem acento nem maiuscula. Devolve ate tres pratos que bateram.';
