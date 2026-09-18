-- =============================================================================
-- Tronvix Facil - ninguem se faz administrador
--
-- O papel de administrador da plataforma abre tudo: aprovar estabelecimento,
-- mexer na comissao alheia e, por app.guard_order_money, reescrever o valor de
-- um pedido ja fechado. Estes testes cuidam da porta.
--
-- Como rodar:  npm run db:test
-- =============================================================================

\set ON_ERROR_STOP on

begin;

create or replace function pg_temp.conferir(p_condicao boolean, p_contexto text)
returns void language plpgsql as $$
begin
  if not p_condicao then
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
  when check_violation or insufficient_privilege then
    raise notice 'ok - rejeitado como esperado: %', p_contexto;
end;
$$;

-- -----------------------------------------------------------------------------
-- O cadastro publico escolhe o papel — dentro de uma lista de permitidos
-- -----------------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-0000-0000-0000-000000000001', 'cliente@teste.test',
   '{"full_name": "Cliente", "platform_role": "customer"}'::jsonb),
  ('11111111-0000-0000-0000-000000000002', 'entregador@teste.test',
   '{"full_name": "Entregador", "platform_role": "courier"}'::jsonb),
  -- O ataque: pedir para nascer administrador.
  ('11111111-0000-0000-0000-000000000003', 'esperto@teste.test',
   '{"full_name": "Esperto", "platform_role": "platform_admin"}'::jsonb),
  -- E um papel que nem existe no enum.
  ('11111111-0000-0000-0000-000000000004', 'inventado@teste.test',
   '{"full_name": "Inventado", "platform_role": "deus"}'::jsonb),
  ('11111111-0000-0000-0000-000000000005', 'semnada@teste.test',
   '{"full_name": "Sem Nada"}'::jsonb);

do $$
begin
  perform pg_temp.conferir(
    (select platform_role from profiles
      where id = '11111111-0000-0000-0000-000000000001') = 'customer',
    'quem pede para ser cliente nasce cliente');

  perform pg_temp.conferir(
    (select platform_role from profiles
      where id = '11111111-0000-0000-0000-000000000002') = 'courier',
    'quem pede para ser entregador nasce entregador');

  perform pg_temp.conferir(
    (select platform_role from profiles
      where id = '11111111-0000-0000-0000-000000000003') = 'customer',
    'quem pede para nascer administrador nasce cliente');

  perform pg_temp.conferir(
    (select platform_role from profiles
      where id = '11111111-0000-0000-0000-000000000004') = 'customer',
    'papel inventado nos metadados nao derruba o cadastro: vira cliente');

  perform pg_temp.conferir(
    (select platform_role from profiles
      where id = '11111111-0000-0000-0000-000000000005') = 'customer',
    'sem papel nos metadados, cliente');
end;
$$;

-- -----------------------------------------------------------------------------
-- Nem depois: promover-se continua fora de alcance
-- -----------------------------------------------------------------------------
do $$
begin
  perform set_config('request.jwt.claim.sub',
                     '11111111-0000-0000-0000-000000000003', true);

  perform pg_temp.deve_falhar(
    $f$update profiles set platform_role = 'platform_admin'
        where id = '11111111-0000-0000-0000-000000000003'$f$,
    'a pessoa se promovendo a administrador depois do cadastro');

  perform pg_temp.deve_falhar(
    $f$update profiles set platform_role = 'platform_admin'
        where id = '11111111-0000-0000-0000-000000000001'$f$,
    'promovendo outra pessoa a administrador');
end;
$$;

-- -----------------------------------------------------------------------------
-- A chave de servico promove — e e por ela que nasce o primeiro administrador
-- -----------------------------------------------------------------------------
do $$
begin
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);

  update profiles set platform_role = 'platform_admin'
   where id = '11111111-0000-0000-0000-000000000001';

  perform pg_temp.conferir(
    (select platform_role from profiles
      where id = '11111111-0000-0000-0000-000000000001') = 'platform_admin',
    'a chave de servico promove: e assim que nasce o primeiro administrador');

  perform set_config('request.jwt.claim.role', '', true);
end;
$$;

-- E um administrador promove outro, como sempre pôde.
do $$
begin
  perform set_config('request.jwt.claim.sub',
                     '11111111-0000-0000-0000-000000000001', true);

  update profiles set platform_role = 'platform_admin'
   where id = '11111111-0000-0000-0000-000000000002';

  perform pg_temp.conferir(
    (select platform_role from profiles
      where id = '11111111-0000-0000-0000-000000000002') = 'platform_admin',
    'administrador promove outro administrador');
end;
$$;

rollback;
