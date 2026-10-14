-- =============================================================================
-- Tronvix Facil - modo suporte
--
-- So a equipe da plataforma entra no painel de uma loja sem ser da loja, e
-- cada entrada fica registrada — visivel a gestao da loja.
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
  when check_violation or insufficient_privilege or no_data_found then
    raise notice 'ok - rejeitado como esperado: %', p_contexto;
end;
$$;

create or replace function pg_temp.virar(p_user uuid)
returns void language sql as $$
  select set_config('request.jwt.claim.sub', p_user::text, true);
$$;

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'suporte@teste.test'),
  ('22222222-2222-2222-2222-222222222222', 'dono@teste.test'),
  ('33333333-3333-3333-3333-333333333333', 'dono-vizinho@teste.test');

-- Feito aqui, fora de qualquer sessao: e a promocao que o script
-- criar-administrador faz com a chave de servico.
select set_config('request.jwt.claim.role', 'service_role', true);
update profiles set platform_role = 'platform_admin'
 where id = '11111111-1111-1111-1111-111111111111';
select set_config('request.jwt.claim.role', '', true);

insert into restaurants (id, slug, name, status, is_open, min_order_cents)
values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'loja', 'A Loja', 'approved', true, 0),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'vizinha', 'Vizinha', 'approved', true, 0);

insert into restaurant_members (restaurant_id, user_id, role) values
  ('aaaaaaaa-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 'owner'),
  ('aaaaaaaa-0000-0000-0000-000000000002', '33333333-3333-3333-3333-333333333333', 'owner');

insert into categories (id, restaurant_id, name)
values ('cccccccc-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'Pratos');
insert into products (id, restaurant_id, category_id, name, price_cents)
values ('dddddddd-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000001', 'Prato', 3000);

do $$
declare v_sessao uuid; v_outra uuid; v_pedido uuid;
begin
  -- Dono nao entra como suporte na loja dos outros.
  perform pg_temp.virar('22222222-2222-2222-2222-222222222222');
  perform pg_temp.deve_falhar(
    $q$select entrar_como_suporte('aaaaaaaa-0000-0000-0000-000000000002')$q$,
    'dono de loja entrando como suporte na loja vizinha');

  -- A plataforma entra, e fica registrado.
  perform pg_temp.virar('11111111-1111-1111-1111-111111111111');
  v_sessao := entrar_como_suporte('aaaaaaaa-0000-0000-0000-000000000001');
  perform pg_temp.conferir(
    (select admin_id = '11111111-1111-1111-1111-111111111111' and ended_at is null
       from support_sessions where id = v_sessao),
    'a entrada do suporte fica registrada, com quem entrou');

  -- E age como a loja: lanca pedido e mexe no caixa.
  v_pedido := lancar_pedido('aaaaaaaa-0000-0000-0000-000000000001',
    '{"tipo":"pickup","itens":[{"produto_id":"dddddddd-0000-0000-0000-000000000001","quantidade":1}]}');
  perform registrar_fundo_de_caixa('aaaaaaaa-0000-0000-0000-000000000001', 5000);
  perform pg_temp.conferir(v_pedido is not null, 'o suporte lanca pedido e mexe no caixa da loja');

  -- Entrar em outra loja encerra a sessao anterior.
  v_outra := entrar_como_suporte('aaaaaaaa-0000-0000-0000-000000000002');
  perform pg_temp.conferir(
    (select ended_at is not null from support_sessions where id = v_sessao),
    'entrar em outra loja encerra a sessao anterior');

  perform sair_do_suporte();
  perform pg_temp.conferir(
    (select ended_at is not null from support_sessions where id = v_outra),
    'sair do suporte encerra a sessao');

  -- A gestao da loja ve que o suporte esteve la; a vizinha nao ve.
  perform pg_temp.virar('22222222-2222-2222-2222-222222222222');
  set local role authenticated;
  perform pg_temp.conferir(
    (select count(*) from support_sessions) = 1,
    'o dono ve as entradas do suporte na loja dele, e so as dele');
  reset role;
end;
$$;

do $$
begin
  perform pg_temp.virar('22222222-2222-2222-2222-222222222222');
  perform pg_temp.deve_falhar(
    $q$set local role authenticated;
       insert into support_sessions (restaurant_id, admin_id)
       values ('aaaaaaaa-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222')$q$,
    'registrar sessao de suporte direto na tabela');
  reset role;
end;
$$;

rollback;
