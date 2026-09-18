-- =============================================================================
-- Tronvix Facil - o dono cadastra a propria loja
--
-- Esta e a primeira porta pela qual alguem de fora escreve em `restaurants`.
-- O que se testa aqui nao e que o cadastro funciona - isso a tela mostra -, e
-- sim que ele NAO deixa escolher o que nao e de quem cadastra: a situacao, a
-- comissao, o endereco publico e o dono da loja.
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

create or replace function pg_temp.virar(p_user uuid)
returns void language sql as $$
  select set_config('request.jwt.claim.sub', p_user::text, true);
$$;

insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'dono@teste.test',
   '{"full_name": "Dono", "phone": "62990000001"}'::jsonb),
  ('22222222-2222-2222-2222-222222222222', 'outro@teste.test',
   '{"full_name": "Outro", "phone": "62990000002"}'::jsonb);

-- -----------------------------------------------------------------------------
-- Sem sessao, ninguem cadastra
-- -----------------------------------------------------------------------------
do $$
begin
  perform set_config('request.jwt.claim.sub', '', true);
  perform pg_temp.deve_falhar(
    $q$select cadastrar_estabelecimento(
        'Loja Anonima', '6232000000', 'Rua A', '1', 'Centro', 'Goiania')$q$,
    'cadastrar sem estar logado');
end;
$$;

-- -----------------------------------------------------------------------------
-- O cadastro comum, e o que ele decide sozinho
-- -----------------------------------------------------------------------------
do $$
declare
  v record;
  v_loja restaurants;
begin
  perform pg_temp.virar('11111111-1111-1111-1111-111111111111');

  select * into v from cadastrar_estabelecimento(
    'Pizzaria da Esquina', '(62) 3241-0000',
    'Av. T-4', '1520', 'Setor Bueno', 'Goiânia', 'go', '74230-035');

  select * into v_loja from restaurants where id = v.id;

  perform pg_temp.conferir(v_loja.status = 'pending',
    'a loja nasce esperando aprovacao');
  perform pg_temp.conferir(v_loja.is_open = false,
    'a loja nasce fechada: cardapio vazio nao recebe pedido');
  perform pg_temp.conferir(v_loja.approved_at is null and v_loja.approved_by is null,
    'ninguem se aprova no proprio cadastro');
  perform pg_temp.conferir(v_loja.commission_bps =
    coalesce((select default_commission_bps from platform_settings limit 1), 1000),
    'a comissao e a padrao da plataforma, nao uma escolhida por quem cadastra');

  perform pg_temp.conferir(v.slug = 'pizzaria-da-esquina',
    'o endereco publico sai do nome, sem acento nem espaco');
  perform pg_temp.conferir(v_loja.phone = '6232410000',
    'o telefone entra so com digitos, como o banco exige');
  perform pg_temp.conferir(v_loja.postal_code = '74230035',
    'o CEP tambem');
  perform pg_temp.conferir(v_loja.state = 'GO',
    'o estado entra em maiuscula');

  perform pg_temp.conferir(
    exists (select 1 from restaurant_members
             where restaurant_id = v.id
               and user_id = '11111111-1111-1111-1111-111111111111'
               and role = 'owner' and is_active),
    'quem cadastrou vira dono da loja');
end;
$$;

-- -----------------------------------------------------------------------------
-- Dois com o mesmo nome nao brigam pelo mesmo endereco
-- -----------------------------------------------------------------------------
do $$
declare v record;
begin
  perform pg_temp.virar('22222222-2222-2222-2222-222222222222');

  select * into v from cadastrar_estabelecimento(
    'Pizzaria da Esquina', '6232000001', 'Rua B', '2', 'Centro', 'Goiania');

  perform pg_temp.conferir(v.slug = 'pizzaria-da-esquina-2',
    'o segundo de mesmo nome ganha sufixo que da para ditar por telefone');
end;
$$;

-- -----------------------------------------------------------------------------
-- O que o cadastro recusa
-- -----------------------------------------------------------------------------
do $$
begin
  perform pg_temp.virar('11111111-1111-1111-1111-111111111111');

  perform pg_temp.deve_falhar(
    $q$select cadastrar_estabelecimento('X', '6232000000', 'Rua A', '1', 'Centro', 'Goiania')$q$,
    'nome de uma letra');

  perform pg_temp.deve_falhar(
    $q$select cadastrar_estabelecimento('Loja Boa', '3200', 'Rua A', '1', 'Centro', 'Goiania')$q$,
    'telefone sem DDD');

  perform pg_temp.deve_falhar(
    $q$select cadastrar_estabelecimento('Loja Boa', '6232000000', '', '1', 'Centro', 'Goiania')$q$,
    'endereco sem rua');

  perform pg_temp.deve_falhar(
    $q$select cadastrar_estabelecimento('Loja Boa', '6232000000', 'Rua A', '1', 'Centro', '  ')$q$,
    'endereco sem cidade');
end;
$$;

-- -----------------------------------------------------------------------------
-- Freio de enchente: tres esperando, e para
-- -----------------------------------------------------------------------------
do $$
begin
  perform pg_temp.virar('11111111-1111-1111-1111-111111111111');

  perform cadastrar_estabelecimento('Segunda Loja', '6232000002', 'Rua C', '3', 'Centro', 'Goiania');
  perform cadastrar_estabelecimento('Terceira Loja', '6232000003', 'Rua D', '4', 'Centro', 'Goiania');

  perform pg_temp.deve_falhar(
    $q$select cadastrar_estabelecimento('Quarta Loja', '6232000004', 'Rua E', '5', 'Centro', 'Goiania')$q$,
    'o quarto cadastro esperando aprovacao');
end;
$$;

-- Aprovada, ela sai da fila e a pessoa pode cadastrar outra: o freio conta
-- quem espera, nao quem ja foi analisado.
do $$
begin
  -- Aprovar e ato da plataforma: app.guard_restaurant_platform_fields recusa
  -- que o dono mexa na propria situacao. A chave de servico e a outra forma de
  -- ser a plataforma, e e ela que o /admin usa por tras.
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);

  update restaurants set status = 'approved'
   where slug = 'pizzaria-da-esquina';

  perform set_config('request.jwt.claim.role', '', true);
  perform pg_temp.virar('11111111-1111-1111-1111-111111111111');
  perform cadastrar_estabelecimento('Quinta Loja', '6232000005', 'Rua F', '6', 'Centro', 'Goiania');

  perform pg_temp.conferir(true,
    'com uma aprovada, abre vaga na fila para cadastrar outra');
end;
$$;

-- -----------------------------------------------------------------------------
-- A porta da plataforma
-- -----------------------------------------------------------------------------
do $$
begin
  perform set_config('request.jwt.claim.role', 'service_role', true);
  update platform_settings set allow_new_signups = false;
  perform set_config('request.jwt.claim.role', '', true);

  perform pg_temp.virar('22222222-2222-2222-2222-222222222222');
  perform pg_temp.deve_falhar(
    $q$select cadastrar_estabelecimento('Tarde Demais', '6232000009', 'Rua Z', '9', 'Centro', 'Goiania')$q$,
    'cadastrar com a plataforma fechada a novos estabelecimentos');

  perform set_config('request.jwt.claim.role', 'service_role', true);
  update platform_settings set allow_new_signups = true;
  perform set_config('request.jwt.claim.role', '', true);
end;
$$;

-- -----------------------------------------------------------------------------
-- A tabela continua fechada: a funcao e o unico caminho
-- -----------------------------------------------------------------------------
-- `set local role authenticated` e obrigatorio aqui: no psql a sessao roda como
-- dona das tabelas, e dono de tabela ignora RLS. Sem trocar de papel, este
-- teste passaria sempre - inclusive com a politica apagada.
create or replace function pg_temp.insercao_direta(p_user uuid)
returns text language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  set local role authenticated;
  insert into restaurants (slug, name, status, commission_bps)
  values ('na-marra', 'Na Marra', 'approved', 0);
  reset role;
  return 'passou';
exception
  when insufficient_privilege then
    reset role;
    return 'recusado';
end;
$$;

do $$
begin
  perform pg_temp.conferir(
    pg_temp.insercao_direta('22222222-2222-2222-2222-222222222222') = 'recusado',
    'a tabela continua fechada: inserir direto em restaurants e recusado');
end;
$$;

rollback;
