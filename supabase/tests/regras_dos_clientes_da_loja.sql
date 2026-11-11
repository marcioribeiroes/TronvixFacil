-- =============================================================================
-- Tronvix Facil - o caderno de clientes da loja
--
-- Cada loja ve so o seu. A equipe le, a gestao escreve, e o telefone e um so
-- por cliente dentro da mesma loja.
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

-- Roda o SQL como o usuario logado, com a RLS valendo.
create or replace function pg_temp.como(p_user uuid, p_sql text)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  set local role authenticated;
  execute p_sql;
  reset role;
exception when others then
  reset role;
  raise;
end;
$$;

create or replace function pg_temp.deve_falhar(p_user uuid, p_sql text, p_contexto text)
returns void language plpgsql as $$
begin
  perform pg_temp.como(p_user, p_sql);
  raise exception 'FALHOU: % deveria ter sido rejeitado, mas passou.', p_contexto;
exception
  when check_violation or insufficient_privilege or unique_violation then
    raise notice 'ok - rejeitado como esperado: %', p_contexto;
end;
$$;

create or replace function pg_temp.quantos(p_user uuid, p_loja uuid)
returns int language plpgsql as $$
declare n int;
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  set local role authenticated;
  select count(*) into n from restaurant_customers
   where restaurant_id = p_loja and deleted_at is null;
  reset role;
  return n;
end;
$$;

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'dono@teste.test'),
  ('22222222-2222-2222-2222-222222222222', 'atendente@teste.test'),
  ('33333333-3333-3333-3333-333333333333', 'dono-vizinho@teste.test');

insert into restaurants (id, slug, name, status, is_open, min_order_cents) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'loja', 'A Loja', 'approved', true, 0),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'vizinha', 'A Vizinha', 'approved', true, 0);

insert into restaurant_members (restaurant_id, user_id, role) values
  ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'owner'),
  ('aaaaaaaa-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 'staff'),
  ('aaaaaaaa-0000-0000-0000-000000000002', '33333333-3333-3333-3333-333333333333', 'owner');

do $$
declare
  v_dono constant uuid := '11111111-1111-1111-1111-111111111111';
  v_atendente constant uuid := '22222222-2222-2222-2222-222222222222';
  v_vizinho constant uuid := '33333333-3333-3333-3333-333333333333';
  v_loja constant uuid := 'aaaaaaaa-0000-0000-0000-000000000001';
begin
  perform pg_temp.como(v_dono, format($q$
    insert into restaurant_customers (restaurant_id, name, phone, address_street, address_district)
    values ('%s', 'Seu Joao', '62999990000', 'Rua das Flores', 'Centro')$q$, v_loja));
  perform pg_temp.conferir(pg_temp.quantos(v_dono, v_loja) = 1, 'o dono cadastra um cliente');

  perform pg_temp.conferir(pg_temp.quantos(v_atendente, v_loja) = 1,
    'o atendente ve o cliente: e ele quem atende o telefone');
  perform pg_temp.conferir(pg_temp.quantos(v_vizinho, v_loja) = 0,
    'a loja vizinha nao ve o caderno desta');

  perform pg_temp.deve_falhar(v_atendente, format($q$
    insert into restaurant_customers (restaurant_id, name) values ('%s', 'Maria')$q$, v_loja),
    'atendente cadastrando cliente');
  perform pg_temp.deve_falhar(v_vizinho, format($q$
    insert into restaurant_customers (restaurant_id, name) values ('%s', 'Maria')$q$, v_loja),
    'dono de outra loja cadastrando aqui');

  perform pg_temp.deve_falhar(v_dono, format($q$
    insert into restaurant_customers (restaurant_id, name, phone)
    values ('%s', 'Outro Joao', '62999990000')$q$, v_loja),
    'o mesmo telefone em duas fichas da mesma loja');
  perform pg_temp.deve_falhar(v_dono, format($q$
    insert into restaurant_customers (restaurant_id, name, phone)
    values ('%s', 'Formatado', '(62) 99999-1111')$q$, v_loja),
    'telefone com formatacao em vez de so digitos');
  perform pg_temp.deve_falhar(v_dono, format($q$
    insert into restaurant_customers (restaurant_id, name) values ('%s', '   ')$q$, v_loja),
    'cliente sem nome');

  -- O mesmo telefone em outra loja e outra ficha: cada loja tem o seu caderno.
  perform pg_temp.como(v_vizinho, $q$
    insert into restaurant_customers (restaurant_id, name, phone)
    values ('aaaaaaaa-0000-0000-0000-000000000002', 'Seu Joao', '62999990000')$q$);
  perform pg_temp.conferir(true, 'o mesmo telefone cabe em lojas diferentes');

  -- Tirado da lista, o telefone fica livre para uma ficha nova.
  perform pg_temp.como(v_dono, format($q$
    update restaurant_customers set deleted_at = now()
     where restaurant_id = '%s' and phone = '62999990000'$q$, v_loja));
  perform pg_temp.conferir(pg_temp.quantos(v_dono, v_loja) = 0, 'o cliente tirado some da lista');
  perform pg_temp.como(v_dono, format($q$
    insert into restaurant_customers (restaurant_id, name, phone)
    values ('%s', 'Seu Joao', '62999990000')$q$, v_loja));
  perform pg_temp.conferir(pg_temp.quantos(v_dono, v_loja) = 1,
    'e o telefone dele pode ser cadastrado de novo');

  -- O atendente le, mas nao corrige: o update passa sem tocar em linha nenhuma.
  perform pg_temp.como(v_atendente, format($q$
    update restaurant_customers set name = 'Mudado' where restaurant_id = '%s'$q$, v_loja));
  perform pg_temp.conferir(
    not exists (select 1 from restaurant_customers where name = 'Mudado'),
    'o atendente nao corrige a ficha');
end;
$$;

rollback;
