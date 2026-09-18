-- =============================================================================
-- Tronvix Facil - ninguem se faz administrador
--
-- app.handle_new_user copiava o papel direto dos metadados do cadastro:
--
--   coalesce((new.raw_user_meta_data ->> 'platform_role')::platform_role,
--            'customer')
--
-- Metadado de cadastro e escrito pelo CLIENTE. Qualquer pessoa, com a chave
-- anonima que vai publicada em todo aplicativo instalado, podia fazer:
--
--   signUp({ email, password, data: { platform_role: 'platform_admin' } })
--
-- e nascer administrador da plataforma. Verificado contra o banco antes desta
-- correcao: o gatilho gravou 'platform_admin' e o usuario passou a poder
-- aprovar estabelecimentos, mexer na comissao dos outros e - por
-- app.guard_order_money, que abre excecao para administrador - reescrever o
-- valor de qualquer pedido ja fechado.
--
-- O guarda de UPDATE (app.guard_platform_role) estava certo o tempo todo. O
-- buraco era o INSERT, que nao passava por ele.
--
-- Agora:
--
--   * do cadastro publico so saem 'customer' e 'courier' - os dois papeis que
--     uma pessoa pode legitimamente escolher ser por conta propria;
--   * 'platform_admin' vem de uma promocao explicita, feita por quem ja e
--     administrador ou pela chave de servico (scripts/criar-administrador.mjs).
-- =============================================================================

create or replace function app.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pedido text := new.raw_user_meta_data ->> 'platform_role';
  v_papel platform_role;
begin
  -- Lista de permitidos, nao lista de proibidos: um papel novo no enum nasce
  -- fora do alcance do cadastro publico ate alguem decidir o contrario.
  v_papel := case v_pedido
    when 'customer' then 'customer'::platform_role
    when 'courier'  then 'courier'::platform_role
    else 'customer'::platform_role
  end;

  insert into public.profiles (id, full_name, email, phone, platform_role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    new.email,
    nullif(new.raw_user_meta_data ->> 'phone', ''),
    v_papel
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

comment on function app.handle_new_user() is
  'Cria o perfil junto com a credencial. O papel vem de uma lista de permitidos: quem se cadastra escolhe ser cliente ou entregador, nunca administrador.';

-- -----------------------------------------------------------------------------
-- A promocao a administrador, e quem pode faze-la
--
-- O guarda de UPDATE ja exigia ser administrador. Faltava a chave de servico:
-- ela ignora a RLS, mas nao ignora gatilho - entao nem uma rotina de
-- administracao conseguia promover a primeira pessoa. O ovo e a galinha.
-- -----------------------------------------------------------------------------
create or replace function app.guard_platform_role()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.platform_role is distinct from old.platform_role
     and not app.is_platform_admin()
     and not app.is_service_role() then
    raise exception 'Alterar o papel na plataforma e exclusivo do administrador.'
      using errcode = 'insufficient_privilege';
  end if;
  return new;
end;
$$;
