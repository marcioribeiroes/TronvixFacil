-- =============================================================================
-- Tronvix Facil - aviso de pedido com o navegador fechado
--
-- O alerta sonoro da fila resolve para quem esta com a aba aberta. Quem fecha
-- o notebook volta a nao saber do pedido - e esse e o buraco que sobra.
--
-- Web Push resolve porque quem entrega o aviso e o navegador, nao a pagina: a
-- inscricao vive no servico de push do fabricante (Google, Apple, Mozilla) e
-- funciona com o site fechado.
--
-- Duas pecas aqui:
--
--   push_subscriptions   onde avisar cada pessoa. Uma linha por aparelho.
--   avisar_pedido()      o gatilho que chama a Edge Function quando um pedido
--                        chega em "recebido".
-- =============================================================================

create table if not exists push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles (id) on delete cascade,

  -- O endereco que o navegador deu. E o identificador de verdade da inscricao:
  -- a mesma pessoa em tres aparelhos tem tres linhas, e reinstalar o navegador
  -- gera um endereco novo.
  endpoint text not null unique,
  p256dh text not null,
  auth text not null,

  -- Para a pessoa reconhecer o aparelho numa lista, se um dia houver uma.
  descricao text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists push_subscriptions_user_idx on push_subscriptions (user_id);

drop trigger if exists push_subscriptions_touch on push_subscriptions;
create trigger push_subscriptions_touch
  before update on push_subscriptions
  for each row execute function app.touch_updated_at();

alter table push_subscriptions enable row level security;

-- Cada um cuida das proprias inscricoes. Ninguem le a de ninguem - nem a
-- plataforma: um endpoint de push e um canal direto para o aparelho de uma
-- pessoa, e quem precisa dele para enviar e a funcao, que roda com a chave de
-- servico e passa por fora da RLS.
drop policy if exists "cada um cuida das proprias inscricoes" on push_subscriptions;
create policy "cada um cuida das proprias inscricoes"
  on push_subscriptions for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- -----------------------------------------------------------------------------
-- O gatilho que chama a funcao
--
-- pg_net envia a requisicao de forma assincrona: o INSERT do pedido nao espera
-- a resposta do servico de push. Um fechamento de pedido NAO pode ficar mais
-- lento - nem falhar - porque o aviso demorou.
-- -----------------------------------------------------------------------------
-- pg_net existe no Supabase e nao num Postgres comum. A migracao precisa
-- aplicar nos dois: `npm run db:test` roda num Postgres local descartavel, e
-- uma migracao que exige extensao indisponivel quebraria a suite inteira.
do $$
begin
  create extension if not exists pg_net with schema extensions;
exception
  when others then
    raise notice 'pg_net indisponivel: o aviso por push fica desligado neste banco.';
end;
$$;

create or replace function app.avisar_pedido()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_url text := current_setting('app.url_da_funcao_de_aviso', true);
  v_chave text := current_setting('app.chave_de_servico', true);
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
  -- desenvolvimento recem-criado nao deve quebrar por nao ter push.
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

comment on function app.avisar_pedido() is
  'Chama a Edge Function de aviso quando um pedido chega a "recebido". Assincrono por pg_net: o fechamento do pedido nao espera nem depende do push.';

drop trigger if exists orders_avisar_push on orders;
create trigger orders_avisar_push
  after insert or update of status on orders
  for each row execute function app.avisar_pedido();
