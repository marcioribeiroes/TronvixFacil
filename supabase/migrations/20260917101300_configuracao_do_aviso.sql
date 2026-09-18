-- =============================================================================
-- Tronvix Facil - onde o gatilho de aviso guarda a configuracao dele
--
-- A migracao anterior leu a URL da funcao e a chave de servico de
-- `current_setting('app.url_da_funcao_de_aviso')`, que se define com
--
--   alter database postgres set app.url_da_funcao_de_aviso = '...'
--
-- No Supabase isso e negado: a role `postgres` do projeto nao e superusuaria.
--
--   ERROR: permission denied to set parameter "app.url_da_funcao_de_aviso"
--
-- E uma migracao tambem nao serve para guardar esses valores: a URL carrega a
-- referencia do projeto, e uma migracao com ela dentro quebraria em qualquer
-- outro ambiente.
--
-- A saida e uma tabela no schema `app`. O PostgREST expoe apenas `public`,
-- entao nada disto e alcancavel pela API - nem a chave de servico que mora
-- ali. Quem escreve e `npm run avisos:ligar`, por conexao direta.
-- =============================================================================

create table if not exists app.configuracao (
  chave text primary key,
  valor text not null,
  atualizado_em timestamptz not null default now()
);

comment on table app.configuracao is
  'Valores de ambiente que o banco precisa conhecer — hoje, o endereco da funcao de aviso e a chave para chama-la. Fora do schema public de proposito: nao e dado de produto e nao deve ser alcancavel pela API.';

create or replace function app.avisar_pedido()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_url text := (select valor from app.configuracao where chave = 'url_da_funcao_de_aviso');
  v_chave text := (select valor from app.configuracao where chave = 'chave_de_servico');
begin
  -- So quando o pedido CHEGA a "recebido". Um pedido andando de "em preparo"
  -- para "pronto" tambem dispara este gatilho, e avisar a cada passo ensinaria
  -- a equipe a ignorar o aviso.
  if new.status <> 'received' then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.status = 'received' then
    return new;
  end if;

  -- Sem configuracao, o gatilho nao faz nada e nao reclama: um banco de
  -- desenvolvimento recem-criado nao deve tentar mandar push.
  if v_url is null or v_url = '' then
    return new;
  end if;

  -- Chamada dinamica, e nao `perform net.http_post(...)` direto: sem pg_net
  -- instalado, a referencia a `net.http_post` impediria ate a CRIACAO desta
  -- funcao, e a migracao nao aplicaria num Postgres comum.
  if to_regproc('net.http_post') is null then
    return new;
  end if;

  execute format(
    'select net.http_post(url := %L, headers := %L::jsonb, body := %L::jsonb)',
    v_url,
    jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || coalesce(v_chave, '')
    )::text,
    jsonb_build_object(
      'type', tg_op,
      'record', to_jsonb(new),
      'old_record', case when tg_op = 'UPDATE' then to_jsonb(old) else null end
    )::text
  );

  return new;
end;
$$;
