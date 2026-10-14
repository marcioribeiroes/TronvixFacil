-- =============================================================================
-- Tronvix Facil - aparelhos para o aviso no celular
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

create or replace function pg_temp.deve_falhar(p_sql text, p_contexto text)
returns void language plpgsql as $$
begin
  execute p_sql;
  raise exception 'FALHOU: % deveria ter sido rejeitado, mas passou.', p_contexto;
exception
  when check_violation or insufficient_privilege or no_data_found then
    raise notice 'ok - rejeitado como esperado: %', p_contexto;
end;
$$;

create or replace function pg_temp.virar(p_user uuid)
returns void language sql as $$
  select set_config('request.jwt.claim.sub', p_user::text, true);
$$;

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'ana@teste.test'),
  ('22222222-2222-2222-2222-222222222222', 'bia@teste.test');

do $$
begin
  perform pg_temp.virar('11111111-1111-1111-1111-111111111111');
  perform registrar_aparelho('token-do-celular-da-loja-0000000001', 'android');
  perform registrar_aparelho('token-do-celular-da-loja-0000000001', 'android');
  perform pg_temp.conferir(
    (select count(*) from device_tokens) = 1,
    'registrar o mesmo aparelho de novo nao duplica');

  -- O celular troca de conta: o aparelho passa a ser da conta nova.
  perform pg_temp.virar('22222222-2222-2222-2222-222222222222');
  perform registrar_aparelho('token-do-celular-da-loja-0000000001', 'android');
  perform pg_temp.conferir(
    (select user_id from device_tokens) = '22222222-2222-2222-2222-222222222222',
    'o aparelho que troca de conta deixa de receber os avisos da anterior');

  -- Ana nao apaga o aparelho que agora e da Bia.
  perform pg_temp.virar('11111111-1111-1111-1111-111111111111');
  perform esquecer_aparelho('token-do-celular-da-loja-0000000001');
  perform pg_temp.conferir((select count(*) from device_tokens) = 1,
    'quem nao e dono nao esquece o aparelho dos outros');

  perform pg_temp.virar('22222222-2222-2222-2222-222222222222');
  perform esquecer_aparelho('token-do-celular-da-loja-0000000001');
  perform pg_temp.conferir((select count(*) from device_tokens) = 0,
    'sair da conta esquece o aparelho');

  perform pg_temp.deve_falhar(
    $q$select registrar_aparelho('token-do-celular-0000000000000002', 'windows')$q$,
    'plataforma que nao existe');

  perform set_config('request.jwt.claim.sub', '', true);
  perform pg_temp.deve_falhar(
    $q$select registrar_aparelho('token-do-celular-0000000000000003', 'ios')$q$,
    'registrar aparelho sem estar logado');
end;
$$;

rollback;
