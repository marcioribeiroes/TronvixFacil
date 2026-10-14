-- =============================================================================
-- Tronvix Facil - aviso no celular, com o aplicativo fechado
--
-- O aviso so existia para o navegador (Web Push). O aplicativo nao recebia
-- nada com a tela fechada: o balcao que guardava o celular no bolso nao sabia
-- do pedido novo, e o cliente reabria o app para ver se tinha andado.
--
-- No celular o caminho e o Firebase Cloud Messaging (que no iPhone passa pela
-- Apple). Cada aparelho tem um token; esta tabela guarda de quem e cada um, e
-- a funcao `avisar-pedido` manda para os tokens das mesmas pessoas que ja
-- recebiam no navegador.
-- =============================================================================

create table if not exists device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles (id) on delete cascade,

  -- O token e o aparelho. Unico: o mesmo celular, depois de trocar de conta,
  -- passa a ser da conta nova — o aviso da anterior nao pode continuar
  -- chegando nele.
  token text not null unique,
  platform text not null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint device_tokens_platform check (platform in ('android', 'ios'))
);

create index if not exists device_tokens_user_idx on device_tokens (user_id);

drop trigger if exists device_tokens_touch on device_tokens;
create trigger device_tokens_touch
  before update on device_tokens
  for each row execute function app.touch_updated_at();

alter table device_tokens enable row level security;

-- Cada um ve os proprios aparelhos. Escrita so pelas funcoes abaixo: o token
-- muda de dono quando o celular troca de conta, e isso a RLS sozinha nao deixa.
drop policy if exists "cada um ve os proprios aparelhos" on device_tokens;
create policy "cada um ve os proprios aparelhos"
  on device_tokens for select
  to authenticated
  using (user_id = auth.uid());

grant select on device_tokens to authenticated;

create or replace function public.registrar_aparelho(p_token text, p_plataforma text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Entre na sua conta.' using errcode = 'insufficient_privilege';
  end if;
  if length(coalesce(p_token, '')) < 20 or length(p_token) > 4096 then
    raise exception 'Token de aparelho invalido.' using errcode = 'check_violation';
  end if;
  if p_plataforma not in ('android', 'ios') then
    raise exception 'Plataforma invalida.' using errcode = 'check_violation';
  end if;

  insert into device_tokens (user_id, token, platform)
  values (auth.uid(), p_token, p_plataforma)
  on conflict (token) do update
    set user_id = excluded.user_id,
        platform = excluded.platform,
        updated_at = now();
end;
$$;

-- Ao sair da conta: o celular para de receber os avisos dela.
create or replace function public.esquecer_aparelho(p_token text)
returns void
language sql
security definer
set search_path = public
as $$
  delete from device_tokens where token = p_token and user_id = auth.uid();
$$;

revoke all on function public.registrar_aparelho(text, text) from public;
revoke all on function public.esquecer_aparelho(text) from public;
grant execute on function public.registrar_aparelho(text, text) to authenticated;
grant execute on function public.esquecer_aparelho(text) to authenticated;
