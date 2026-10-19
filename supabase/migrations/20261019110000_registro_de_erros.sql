-- =============================================================================
-- Tronvix Facil - registro de erros
--
-- Ate aqui, se o checkout quebrasse para um cliente, ninguem ficava sabendo:
-- nao havia monitoramento nenhum, nem no site nem no app. Este registro e o
-- minimo que avisa — o servidor do site, o navegador e o aplicativo gravam o
-- erro aqui, e a plataforma ve em /admin/erros.
--
-- Qualquer um pode registrar (o erro acontece tambem com quem nao entrou na
-- conta), mas ninguem le, exceto a plataforma. O registro e limitado: texto
-- cortado, e uma enxurrada (um laco quebrado num navegador) para de gravar.
-- =============================================================================

create table if not exists app_errors (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  source text not null,
  message text not null,
  stack text,
  url text,
  version text,
  user_id uuid references auth.users (id) on delete set null,
  context jsonb,

  constraint app_errors_source check (source in ('servidor', 'navegador', 'app'))
);

create index if not exists app_errors_created_idx on app_errors (created_at desc);

alter table app_errors enable row level security;

create policy "erros visiveis a plataforma"
  on app_errors for select
  to authenticated
  using (app.is_platform_admin());

grant select on app_errors to authenticated;

create or replace function public.registrar_erro(
  p_origem text,
  p_mensagem text,
  p_pilha text default null,
  p_endereco text default null,
  p_versao text default null,
  p_contexto jsonb default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_origem not in ('servidor', 'navegador', 'app') or coalesce(trim(p_mensagem), '') = '' then
    return;
  end if;

  -- Enxurrada: mais de 300 erros no ultimo minuto ja diz o que precisa.
  if (select count(*) from app_errors where created_at > now() - interval '1 minute') > 300 then
    return;
  end if;

  insert into app_errors (source, message, stack, url, version, user_id, context)
  values (
    p_origem,
    left(p_mensagem, 1000),
    left(p_pilha, 8000),
    left(p_endereco, 500),
    left(p_versao, 50),
    auth.uid(),
    case when pg_column_size(p_contexto) <= 4000 then p_contexto end
  );
end;
$$;

revoke all on function public.registrar_erro(text, text, text, text, text, jsonb) from public;
grant execute on function public.registrar_erro(text, text, text, text, text, jsonb) to anon, authenticated, service_role;

comment on table app_errors is
  'Erros do servidor do site, do navegador e do aplicativo. So a plataforma le. Os de mais de 30 dias podem ser apagados.';
