-- =============================================================================
-- Tronvix Facil - registro de erros
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

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'cliente@teste.test'),
  ('33333333-3333-3333-3333-333333333333', 'plataforma@teste.test');

select set_config('request.jwt.claim.role', 'service_role', true);
update profiles set platform_role = 'platform_admin'
 where id = '33333333-3333-3333-3333-333333333333';
select set_config('request.jwt.claim.role', '', true);

do $$
begin
  perform set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
  perform registrar_erro('app', 'Falhou ao fechar o pedido', repeat('x', 20000), '/carrinho', '1.0.0+3');
  perform registrar_erro('desconhecida', 'nao entra');
  perform registrar_erro('navegador', '   ');

  perform pg_temp.conferir((select count(*) from app_errors) = 1,
    'so entra erro com origem conhecida e mensagem');
  perform pg_temp.conferir(
    (select length(stack) = 8000 and user_id = '11111111-1111-1111-1111-111111111111' from app_errors),
    'a pilha e cortada, e o erro diz de quem foi');

  set local role authenticated;
  perform pg_temp.conferir((select count(*) from app_errors) = 0,
    'o cliente nao le os erros, nem o proprio');
  reset role;

  perform set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', true);
  set local role authenticated;
  perform pg_temp.conferir((select count(*) from app_errors) = 1, 'a plataforma le');
  reset role;

  -- Enxurrada.
  insert into app_errors (source, message) select 'navegador', 'laco' from generate_series(1, 301);
  perform registrar_erro('navegador', 'mais um');
  perform pg_temp.conferir(not exists (select 1 from app_errors where message = 'mais um'),
    'enxurrada de erros para de gravar');
end;
$$;

rollback;
