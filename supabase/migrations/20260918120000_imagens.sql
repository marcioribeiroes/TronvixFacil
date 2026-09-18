-- =============================================================================
-- As fotos: logo, capa e produto.
--
-- As colunas logo_url, cover_url e image_url existem desde o primeiro dia, e
-- nunca houve como preenche-las. Um cardapio sem foto de produto vende menos,
-- e uma vitrine sem logo parece um sistema pela metade — as duas coisas sao
-- verdade e as duas eram visiveis na tela.
--
-- Um balde so, publico, com a pasta nomeada pelo id do estabelecimento:
--
--   imagens/<restaurante>/logo-<momento>.jpg
--   imagens/<restaurante>/capa-<momento>.jpg
--   imagens/<restaurante>/produtos/<produto>-<momento>.jpg
--
-- Publico porque foto de cardapio E publica: ela aparece para quem nem tem
-- conta. Balde privado exigiria URL assinada com validade, renovada a cada
-- carregamento de lista — custo e complexidade para esconder o que se quer
-- mostrar.
--
-- O que NAO e publico e a escrita: a politica exige que quem envia gerencie o
-- estabelecimento da PASTA. Sem isso, qualquer pessoa autenticada trocaria a
-- logo de qualquer loja.
--
-- O nome carrega o momento de proposito. Sobrescrever o mesmo caminho deixa a
-- foto velha em cache de CDN e de navegador, e o dono trocaria a logo sem ver
-- diferenca nenhuma.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- De qual loja e esta pasta?
-- -----------------------------------------------------------------------------
-- Antes do bloco, e nao depois: as politicas a chamam, e uma politica que
-- referencia funcao inexistente nao chega a ser criada. No banco local o bloco
-- sai cedo e esconderia o erro ate o dia do deploy.
--
-- Fora do bloco tambem, para existir onde nao ha storage: assim os testes do
-- banco conferem a regra sem o Supabase inteiro.
create or replace function app.pasta_da_loja(p_caminho text)
returns uuid
language plpgsql
immutable
as $$
declare
  v_primeira text := split_part(coalesce(p_caminho, ''), '/', 1);
begin
  -- Caminho que nao comeca por um uuid nao pertence a loja nenhuma. Devolver
  -- null em vez de estourar deixa a politica recusar em silencio, que e o
  -- comportamento certo para uma tentativa de escrever fora da propria pasta.
  return v_primeira::uuid;
exception
  when invalid_text_representation then
    return null;
end;
$$;

comment on function app.pasta_da_loja(text) is
  'O id do estabelecimento dono de um caminho no balde de imagens. Null quando o caminho nao comeca por um uuid.';

do $$
begin
  -- storage e schema do Supabase, e nao existe num Postgres comum. A migracao
  -- precisa rodar nos dois: no banco local dos testes isto vira um aviso.
  if not exists (select 1 from information_schema.schemata where schema_name = 'storage') then
    raise notice 'schema storage indisponivel: as fotos ficam desligadas neste banco.';
    return;
  end if;

  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values (
    'imagens', 'imagens', true,
    -- 5 MB: foto de celular moderno passa disso, e a tela reduz antes de
    -- enviar. O limite existe para o engano — o video mandado por engano, o
    -- PDF do cardapio inteiro.
    5242880,
    array['image/jpeg', 'image/png', 'image/webp', 'image/avif']
  )
  on conflict (id) do update
    set public = excluded.public,
        file_size_limit = excluded.file_size_limit,
        allowed_mime_types = excluded.allowed_mime_types;

  -- Leitura: qualquer um, inclusive quem nao entrou. E o cardapio.
  execute $p$
    drop policy if exists "imagens sao publicas" on storage.objects;
    create policy "imagens sao publicas"
      on storage.objects for select
      to anon, authenticated
      using (bucket_id = 'imagens');
  $p$;

  -- Escrita: so quem gerencia o estabelecimento dono da pasta.
  --
  -- storage.foldername(name) devolve as pastas do caminho; a primeira e o id
  -- do restaurante. O cast para uuid tambem serve de filtro: caminho que nao
  -- comece por um uuid nao passa.
  execute $p$
    drop policy if exists "gestao envia imagem da propria loja" on storage.objects;
    create policy "gestao envia imagem da propria loja"
      on storage.objects for insert
      to authenticated
      with check (
        bucket_id = 'imagens'
        and app.pasta_da_loja(name) is not null
        and (app.can_manage(app.pasta_da_loja(name)) or app.is_platform_admin())
      );
  $p$;

  execute $p$
    drop policy if exists "gestao troca imagem da propria loja" on storage.objects;
    create policy "gestao troca imagem da propria loja"
      on storage.objects for update
      to authenticated
      using (
        bucket_id = 'imagens'
        and app.pasta_da_loja(name) is not null
        and (app.can_manage(app.pasta_da_loja(name)) or app.is_platform_admin())
      );
  $p$;

  execute $p$
    drop policy if exists "gestao apaga imagem da propria loja" on storage.objects;
    create policy "gestao apaga imagem da propria loja"
      on storage.objects for delete
      to authenticated
      using (
        bucket_id = 'imagens'
        and app.pasta_da_loja(name) is not null
        and (app.can_manage(app.pasta_da_loja(name)) or app.is_platform_admin())
      );
  $p$;
end;
$$;

