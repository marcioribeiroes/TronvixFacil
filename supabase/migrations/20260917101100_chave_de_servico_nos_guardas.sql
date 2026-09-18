-- =============================================================================
-- Tronvix Facil - a chave de servico nos guardas que faltavam
--
-- Terceira vez que o mesmo ponto cego aparece. A chave service_role ignora a
-- RLS por completo, mas NAO ignora gatilho - e tres guardas tratavam uma
-- rotina administrativa como se fosse o usuario comum:
--
--   app.guard_courier_platform_fields    corrigido em 20260917100600
--   app.guard_platform_role              corrigido em 20260917100800
--   app.guard_restaurant_platform_fields corrigido AQUI
--
-- O terceiro apareceu ao devolver um estabelecimento de demonstracao para a
-- fila de aprovacao: "Somente a plataforma altera a situacao do
-- estabelecimento." - dito a uma chamada feita com a chave que pode tudo.
--
-- O padrao que fica: todo guarda que pergunta "voce e a plataforma?" tem de
-- aceitar as DUAS formas de ser a plataforma - o administrador autenticado e a
-- chave de servico. Quem escrever o proximo guarda copia app.is_service_role()
-- junto com pg_trigger_depth().
-- =============================================================================

create or replace function app.guard_restaurant_platform_fields()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Atualizacao vinda de outro gatilho (a media de avaliacoes, por exemplo)
  -- e do proprio banco, nao de um cliente. pg_trigger_depth() > 1 identifica
  -- esse caso e nao e falsificavel pela API: uma chamada direta do cliente
  -- sempre entra com profundidade 1.
  if pg_trigger_depth() > 1 then
    return new;
  end if;

  -- A chave de servico e a outra forma de ser a plataforma. Ela ja ignora a
  -- RLS; barra-la aqui nao protege nada e quebra semente e manutencao.
  if app.is_service_role() then
    return new;
  end if;

  if not app.is_platform_admin() then
    if new.status is distinct from old.status then
      raise exception 'Somente a plataforma altera a situacao do estabelecimento.'
        using errcode = 'insufficient_privilege';
    end if;
    if new.commission_bps is distinct from old.commission_bps then
      raise exception 'Somente a plataforma altera a comissao.'
        using errcode = 'insufficient_privilege';
    end if;
    -- Reputacao e consequencia das avaliacoes, nunca campo editavel.
    new.rating_avg := old.rating_avg;
    new.rating_count := old.rating_count;
  end if;
  return new;
end;
$$;
