-- =============================================================================
-- O dono cadastra o proprio estabelecimento.
--
-- Ate aqui, so administrador da plataforma criava restaurante: a politica de
-- INSERT em `restaurants` exige app.is_platform_admin(). Isso deixava a secao
-- "Esperando aprovacao" do /admin sem nenhuma porta que a alimentasse, e cada
-- loja nova dependia de alguem rodar um script.
--
-- A tentacao era abrir o INSERT para `authenticated` com um `with check`. Nao
-- da, por duas razoes:
--
--   1. O `with check` teria de proibir nascer aprovado, nascer com a comissao
--      que o proprio dono escolheu, nascer com nota... e cada coluna nova da
--      tabela vira uma chance de esquecer uma proibicao. Lista de proibidos
--      envelhece mal.
--
--   2. Ninguem conseguiria virar dono da loja que acabou de criar:
--      restaurant_members exige app.can_manage(restaurant_id), que exige ja
--      ser membro. O ovo e a galinha.
--
-- Entao o caminho e o mesmo de fechar_pedido: UMA funcao, dona das regras, e a
-- tabela continua fechada. O que o cliente manda e o que ele legitimamente
-- sabe - nome, endereco, telefone. Situacao e comissao nao se pedem: sao
-- decididas aqui.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Slug a partir do nome
-- -----------------------------------------------------------------------------
-- O slug e o endereco publico da loja (/restaurante/pizzaria-da-esquina). Nao
-- pode vir do cliente: quem escolhe o proprio slug escolhe tambem 'admin',
-- 'entrar' ou o slug de um concorrente que ainda nao se cadastrou.
create or replace function app.slug_do_nome(p_nome text)
returns text
language sql
immutable
as $$
  select trim(both '-' from
    regexp_replace(
      lower(translate(p_nome,
        'áàâãäéèêëíìîïóòôõöúùûüçñÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ',
        'aaaaaeeeeiiiiooooouuuucnAAAAAEEEEIIIIOOOOOUUUUCN')),
      '[^a-z0-9]+', '-', 'g'))
$$;

comment on function app.slug_do_nome(text) is
  'Nome legivel vira endereco publico: "Açaí & Cia" -> "acai-cia".';

-- -----------------------------------------------------------------------------
-- O cadastro
-- -----------------------------------------------------------------------------
create or replace function public.cadastrar_estabelecimento(
  p_nome            text,
  p_telefone        text,
  p_rua             text,
  p_numero          text,
  p_bairro          text,
  p_cidade          text,
  p_estado          text default 'GO',
  p_cep             text default null,
  p_complemento     text default null,
  p_documento       text default null,
  p_descricao       text default null,
  p_email           text default null
)
returns table (id uuid, slug text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_usuario uuid := auth.uid();
  v_slug text;
  v_base text;
  v_tentativa int := 1;
  v_pendentes int;
  v_comissao int;
  v_aceita boolean;
  v_id uuid;
  v_telefone text := regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g');
begin
  if v_usuario is null then
    raise exception 'Entre na sua conta antes de cadastrar o estabelecimento.'
      using errcode = 'insufficient_privilege';
  end if;

  -- A plataforma pode fechar a porta. Sem isto, "nao aceitar novos cadastros"
  -- nas configuracoes seria um botao que nao faz nada.
  select allow_new_signups, default_commission_bps
    into v_aceita, v_comissao
    from platform_settings
   limit 1;

  if coalesce(v_aceita, true) is false then
    raise exception 'A plataforma não está aceitando novos estabelecimentos agora.'
      using errcode = 'check_violation';
  end if;

  if coalesce(length(trim(p_nome)), 0) < 2 then
    raise exception 'O estabelecimento precisa de um nome.'
      using errcode = 'check_violation';
  end if;

  -- profiles ja exige 10 a 13 digitos; aqui a mensagem e melhor, e o telefone
  -- e o unico jeito de a plataforma falar com a loja antes de aprova-la.
  if length(v_telefone) not between 10 and 13 then
    raise exception 'Telefone inválido: informe DDD e número.'
      using errcode = 'check_violation';
  end if;

  if coalesce(length(trim(p_rua)), 0) = 0
     or coalesce(length(trim(p_numero)), 0) = 0
     or coalesce(length(trim(p_bairro)), 0) = 0
     or coalesce(length(trim(p_cidade)), 0) = 0 then
    raise exception 'O endereço é obrigatório: é de onde o pedido sai.'
      using errcode = 'check_violation';
  end if;

  -- Freio de enchente. Cadastro pendente nao vende nada, mas enche a fila de
  -- aprovacao - e uma fila cheia de lixo faz o cadastro de verdade passar
  -- despercebido. Tres esperando e mais do que qualquer pessoa honesta precisa.
  select count(*) into v_pendentes
    from restaurants r
    join restaurant_members m on m.restaurant_id = r.id
   where m.user_id = v_usuario
     and m.role = 'owner'
     and r.status = 'pending'
     and r.deleted_at is null;

  if v_pendentes >= 3 then
    raise exception 'Você já tem 3 cadastros esperando aprovação. Aguarde a análise.'
      using errcode = 'check_violation';
  end if;

  -- Slug unico. O sufixo numerico so entra quando ha choque de verdade: a
  -- segunda "Pizzaria do Chef" da cidade vira pizzaria-do-chef-2, e nao
  -- pizzaria-do-chef-9f3a1c, que ninguem consegue ditar por telefone.
  v_base := app.slug_do_nome(p_nome);
  if v_base = '' then v_base := 'estabelecimento'; end if;
  v_slug := v_base;

  -- restaurants.slug qualificado: `slug` sozinho aqui e ambiguo, porque o
  -- RETURNS TABLE tambem declara um campo com esse nome.
  while exists (select 1 from restaurants r where r.slug = v_slug::citext) loop
    v_tentativa := v_tentativa + 1;
    v_slug := v_base || '-' || v_tentativa;
  end loop;

  insert into restaurants (
    slug, name, document, description, phone, email,
    street, number, complement, district, city, state, postal_code,
    -- Nasce esperando, fechada, e com a comissao PADRAO da plataforma. Estes
    -- tres nao sao parametros de proposito: sao exatamente o que alguem
    -- tentaria escolher para si.
    status, is_open, commission_bps
  ) values (
    v_slug, trim(p_nome),
    nullif(regexp_replace(coalesce(p_documento, ''), '\D', '', 'g'), ''),
    nullif(trim(coalesce(p_descricao, '')), ''),
    v_telefone,
    nullif(trim(coalesce(p_email, '')), ''),
    trim(p_rua), trim(p_numero),
    nullif(trim(coalesce(p_complemento, '')), ''),
    trim(p_bairro), trim(p_cidade), upper(trim(coalesce(p_estado, 'GO'))),
    nullif(regexp_replace(coalesce(p_cep, ''), '\D', '', 'g'), ''),
    'pending', false, coalesce(v_comissao, 1000)
  )
  returning restaurants.id into v_id;

  -- Quem cadastrou e o dono. Sem esta linha a loja nasce inacessivel ate um
  -- administrador entrar e amarrar alguem nela.
  insert into restaurant_members (restaurant_id, user_id, role, is_active)
  values (v_id, v_usuario, 'owner', true);

  return query select v_id, v_slug;
end;
$$;

revoke all on function public.cadastrar_estabelecimento(
  text, text, text, text, text, text, text, text, text, text, text, text
) from public;

grant execute on function public.cadastrar_estabelecimento(
  text, text, text, text, text, text, text, text, text, text, text, text
) to authenticated;

comment on function public.cadastrar_estabelecimento is
  'Unico caminho para uma pessoa cadastrar o proprio estabelecimento. Nasce pending, fechado e com a comissao padrao da plataforma; quem chamou vira owner.';
