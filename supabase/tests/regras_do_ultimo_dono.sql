-- =============================================================================
-- Tronvix Facil - o ultimo proprietario
--
-- app.guard_last_owner impede que um estabelecimento fique sem dono: sem
-- ninguem com cargo de owner, ninguem entra no painel e a loja vira um
-- registro inacessivel, com cardapio e historico dentro.
--
-- A regra e boa e continua valendo. O que estes testes fixam e a fronteira
-- dela: quando o proprio estabelecimento esta sendo apagado, nao ha mais nada
-- a proteger - e o guarda estava tornando o cadastro impossivel de remover, e
-- com ele a conta de qualquer proprietario.
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
-- Cenario: duas lojas, uma com um dono, outra com dois
-- -----------------------------------------------------------------------------
insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'dono.unico@teste.test'),
  ('22222222-2222-2222-2222-222222222222', 'dono.a@teste.test'),
  ('33333333-3333-3333-3333-333333333333', 'dono.b@teste.test');

insert into restaurants (id, slug, name, status, delivery_fee_cents) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'so-um-dono', 'Só Um Dono', 'approved', 700),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'dois-donos', 'Dois Donos', 'approved', 700);

insert into restaurant_members (restaurant_id, user_id, role) values
  ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'owner'),
  ('aaaaaaaa-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222222', 'owner'),
  ('aaaaaaaa-0000-0000-0000-000000000002', '33333333-3333-3333-3333-333333333333', 'owner');

-- -----------------------------------------------------------------------------
-- A regra, como sempre foi
-- -----------------------------------------------------------------------------
do $$
begin
  perform pg_temp.deve_falhar(
    $q$delete from restaurant_members
        where restaurant_id = 'aaaaaaaa-0000-0000-0000-000000000001'
          and user_id = '11111111-1111-1111-1111-111111111111'$q$,
    'tirar o unico proprietario de uma loja que continua existindo');

  perform pg_temp.deve_falhar(
    $q$update restaurant_members set role = 'staff'
        where restaurant_id = 'aaaaaaaa-0000-0000-0000-000000000001'
          and user_id = '11111111-1111-1111-1111-111111111111'$q$,
    'rebaixar o unico proprietario');

  perform pg_temp.deve_falhar(
    $q$update restaurant_members set is_active = false
        where restaurant_id = 'aaaaaaaa-0000-0000-0000-000000000001'
          and user_id = '11111111-1111-1111-1111-111111111111'$q$,
    'desativar o unico proprietario');
end;
$$;

-- Com dois donos, sair e permitido: sobra um.
do $$
begin
  delete from restaurant_members
   where restaurant_id = 'aaaaaaaa-0000-0000-0000-000000000002'
     and user_id = '33333333-3333-3333-3333-333333333333';

  perform pg_temp.conferir(
    (select count(*) from restaurant_members
      where restaurant_id = 'aaaaaaaa-0000-0000-0000-000000000002'
        and role = 'owner' and is_active) = 1,
    'com dois proprietarios, um pode sair');

  perform pg_temp.deve_falhar(
    $q$delete from restaurant_members
        where restaurant_id = 'aaaaaaaa-0000-0000-0000-000000000002'
          and user_id = '22222222-2222-2222-2222-222222222222'$q$,
    'o que sobrou virou o ultimo, e nao sai');
end;
$$;

-- -----------------------------------------------------------------------------
-- A fronteira: nao ha loja a proteger
-- -----------------------------------------------------------------------------
do $$
begin
  -- Apagar o estabelecimento leva o vinculo em cascata. O guarda nao pode
  -- disparar: o que ele protege ja nao existe.
  delete from restaurants where id = 'aaaaaaaa-0000-0000-0000-000000000001';

  perform pg_temp.conferir(
    not exists (select 1 from restaurants
                 where id = 'aaaaaaaa-0000-0000-0000-000000000001'),
    'apagar o estabelecimento leva o ultimo proprietario junto');

  perform pg_temp.conferir(
    not exists (select 1 from restaurant_members
                 where restaurant_id = 'aaaaaaaa-0000-0000-0000-000000000001'),
    'o vinculo sai em cascata, sem sobrar orfao');
end;
$$;

-- E a conta do proprietario pode ser apagada quando a loja dele ja saiu. Sem
-- isto, nenhum dono conseguiria exercer o direito de excluir os proprios dados.
do $$
begin
  delete from auth.users where id = '22222222-2222-2222-2222-222222222222';
  raise exception 'FALHOU: apagar a conta do unico dono de uma loja VIVA deveria ser recusado.';
exception
  when check_violation then
    raise notice 'ok - rejeitado como esperado: apagar a conta do unico dono de uma loja viva';
end;
$$;

do $$
begin
  delete from restaurants where id = 'aaaaaaaa-0000-0000-0000-000000000002';
  delete from auth.users where id = '22222222-2222-2222-2222-222222222222';

  perform pg_temp.conferir(
    not exists (select 1 from auth.users
                 where id = '22222222-2222-2222-2222-222222222222'),
    'com a loja apagada, a conta do dono pode ser apagada');
end;
$$;

rollback;
