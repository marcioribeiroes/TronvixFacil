-- =============================================================================
-- Tronvix Facil - o cadastro do entregador autonomo
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
  when check_violation or insufficient_privilege or unique_violation or no_data_found then
    raise notice 'ok - rejeitado como esperado: %', p_contexto;
end;
$$;

-- Um cadastro valido, mudando so o que cada caso precisa.
create or replace function pg_temp.cadastrar(
  p_usuario text,
  p_cpf text default '529.982.247-25',
  p_nascimento date default date '1995-05-10',
  p_veiculo text default 'motorcycle',
  p_placa text default 'abc-1d23',
  p_cidade text default 'Cachoeiro de Itapemirim',
  p_cnh text default null
)
returns uuid language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_usuario, true);
  return cadastrar_entregador_autonomo(
    p_cpf, p_nascimento, p_veiculo, p_placa, 'CG 160', 'Vermelha', p_cidade,
    'motoboy@email.com',
    coalesce(p_cnh, p_usuario || '/cnh.jpg'), p_usuario || '/crlv.jpg', p_usuario || '/selfie.jpg');
end;
$$;

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'motoboy@teste.test'),
  ('22222222-2222-2222-2222-222222222222', 'outro@teste.test'),
  ('33333333-3333-3333-3333-333333333333', 'novinho@teste.test'),
  ('44444444-4444-4444-4444-444444444444', 'dono@teste.test'),
  ('55555555-5555-5555-5555-555555555555', 'admin@teste.test');

-- O administrador nasce pela chave de servico, como em producao.
select set_config('request.jwt.claim.role', 'service_role', true);
update profiles set platform_role = 'platform_admin'
 where id = '55555555-5555-5555-5555-555555555555';
select set_config('request.jwt.claim.role', '', true);

-- -----------------------------------------------------------------------------
-- O que o cadastro confere
-- -----------------------------------------------------------------------------
do $$
begin
  perform pg_temp.conferir(app.cpf_valido('52998224725'), 'CPF valido passa');
  perform pg_temp.conferir(not app.cpf_valido('52998224724'), 'digito verificador errado nao passa');
  perform pg_temp.conferir(not app.cpf_valido('11111111111'), 'CPF de numeros repetidos nao passa');

  perform pg_temp.deve_falhar(
    $q$select pg_temp.cadastrar('11111111-1111-1111-1111-111111111111', p_cpf => '123.456.789-00')$q$,
    'CPF invalido');
  perform pg_temp.deve_falhar(
    format($q$select pg_temp.cadastrar('11111111-1111-1111-1111-111111111111', p_nascimento => '%s')$q$,
           current_date - interval '17 years'),
    'menor de 18 anos');
  perform pg_temp.deve_falhar(
    $q$select pg_temp.cadastrar('11111111-1111-1111-1111-111111111111', p_cidade => 'Vitoria')$q$,
    'cidade que a plataforma ainda nao atende');
  perform pg_temp.deve_falhar(
    $q$select pg_temp.cadastrar('11111111-1111-1111-1111-111111111111', p_placa => '12345')$q$,
    'placa em formato invalido');
  perform pg_temp.deve_falhar(
    $q$select pg_temp.cadastrar('11111111-1111-1111-1111-111111111111',
       p_cnh => '22222222-2222-2222-2222-222222222222/cnh.jpg')$q$,
    'usar a CNH que esta na pasta de outra pessoa');

  perform set_config('request.jwt.claim.sub', '', true);
  perform pg_temp.deve_falhar(
    $q$select cadastrar_entregador_autonomo('52998224725', '1995-05-10', 'foot', null, null,
       null, 'Cachoeiro de Itapemirim', 'chave@pix.com', 'x/cnh.jpg', null, 'x/selfie.jpg')$q$,
    'cadastro sem estar logado');
end;
$$;

-- -----------------------------------------------------------------------------
-- O cadastro nasce pendente, autonomo e com tudo guardado
-- -----------------------------------------------------------------------------
do $$
begin
  perform pg_temp.cadastrar('11111111-1111-1111-1111-111111111111');

  perform pg_temp.conferir(
    (select status = 'pending' and restaurant_id is null and availability = 'offline'
            and cpf = '52998224725' and vehicle_plate = 'ABC1D23'
            and city = 'Cachoeiro de Itapemirim' and submitted_at is not null
            and document_selfie_path = '11111111-1111-1111-1111-111111111111/selfie.jpg'
       from couriers where user_id = '11111111-1111-1111-1111-111111111111'),
    'o autonomo nasce pendente, sem restaurante, com CPF e placa normalizados');

  perform pg_temp.deve_falhar(
    $q$select pg_temp.cadastrar('22222222-2222-2222-2222-222222222222')$q$,
    'o mesmo CPF numa segunda conta');

  -- A pe nao tem placa nem documento de veiculo.
  perform set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);
  perform cadastrar_entregador_autonomo('111.444.777-35', '1990-01-01', 'foot', null, null, null,
    'Cachoeiro de Itapemirim', '28999990000',
    '22222222-2222-2222-2222-222222222222/cnh.jpg', null,
    '22222222-2222-2222-2222-222222222222/selfie.jpg');
  perform pg_temp.conferir(
    (select vehicle_plate is null and document_vehicle_path is null
       from couriers where user_id = '22222222-2222-2222-2222-222222222222'),
    'quem entrega a pe se cadastra sem placa e sem documento de veiculo');
end;
$$;

-- -----------------------------------------------------------------------------
-- Recusado, corrige e reenvia; aprovar e da plataforma
-- -----------------------------------------------------------------------------
do $$
begin
  perform set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
  perform pg_temp.deve_falhar(
    $q$update couriers set status = 'approved'
        where user_id = '11111111-1111-1111-1111-111111111111'$q$,
    'o autonomo aprovando a si mesmo');

  perform set_config('request.jwt.claim.sub', '55555555-5555-5555-5555-555555555555', true);
  update couriers set status = 'rejected', review_note = 'A foto da CNH esta ilegivel.'
   where user_id = '11111111-1111-1111-1111-111111111111';

  perform set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
  update couriers set review_note = 'nada'
   where user_id = '11111111-1111-1111-1111-111111111111';
  perform pg_temp.conferir(
    (select review_note = 'A foto da CNH esta ilegivel.'
       from couriers where user_id = '11111111-1111-1111-1111-111111111111'),
    'o entregador le o motivo da recusa, mas nao apaga');

  perform pg_temp.cadastrar('11111111-1111-1111-1111-111111111111');
  perform pg_temp.conferir(
    (select status = 'pending' and review_note is null
       from couriers where user_id = '11111111-1111-1111-1111-111111111111'),
    'reenviar o cadastro corrigido volta para a fila');

  perform set_config('request.jwt.claim.sub', '55555555-5555-5555-5555-555555555555', true);
  update couriers set status = 'approved'
   where user_id = '11111111-1111-1111-1111-111111111111';

  perform pg_temp.deve_falhar(
    $q$select pg_temp.cadastrar('11111111-1111-1111-1111-111111111111')$q$,
    'reenviar o cadastro depois de aprovado');
end;
$$;

-- -----------------------------------------------------------------------------
-- O entregador de restaurante continua no caminho dele
-- -----------------------------------------------------------------------------
insert into restaurants (id, slug, name, status, delivery_fee_cents)
values ('aaaaaaaa-0000-0000-0000-000000000001', 'cantina', 'Cantina', 'approved', 700);
insert into restaurant_members (restaurant_id, user_id, role)
values ('aaaaaaaa-0000-0000-0000-000000000001', '44444444-4444-4444-4444-444444444444', 'owner');
insert into couriers (user_id, restaurant_id, status)
values ('33333333-3333-3333-3333-333333333333', 'aaaaaaaa-0000-0000-0000-000000000001', 'approved');

do $$
begin
  perform pg_temp.deve_falhar(
    $q$select pg_temp.cadastrar('33333333-3333-3333-3333-333333333333', p_cpf => '390.533.447-05')$q$,
    'entregador aprovado de restaurante virando autonomo por conta propria');
end;
$$;

rollback;
