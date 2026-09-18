-- =============================================================================
-- Tronvix Facil - o entregador passa a ser do estabelecimento
--
-- O desenho original era de plataforma que gerencia a entrega: a corrida caia
-- numa fila e QUALQUER entregador aprovado podia aceitar - quem chegasse
-- primeiro levava. Funciona para um marketplace, e e o oposto do que este
-- produto promete: "o sistema nao gerencia a entrega, permitindo o uso de
-- entregadores proprios".
--
-- O que muda:
--
--   couriers.restaurant_id      de quem e este entregador. Nulo = autonomo da
--                               plataforma, para quem quiser operar assim.
--
--   restaurants.accepts_platform_couriers
--                               o estabelecimento aceita entregador de fora?
--                               Padrao FALSE: por omissao, so os seus.
--
-- E quem aprova deixa de ser so a plataforma: o estabelecimento aprova os
-- proprios entregadores. Faz sentido - e ele que conhece a pessoa, e e o
-- dinheiro dele na mochila.
--
-- O que NAO muda: reputacao e contagem de entregas continuam fora do alcance
-- de qualquer um dos dois. Ninguem edita a propria nota.
-- =============================================================================

alter table couriers
  add column if not exists restaurant_id uuid references restaurants (id) on delete cascade;

comment on column couriers.restaurant_id is
  'De qual estabelecimento este entregador e. Nulo = autonomo da plataforma, que so enxerga quem aceita entregador de fora.';

create index if not exists couriers_restaurant_idx
  on couriers (restaurant_id, status)
  where deleted_at is null;

alter table restaurants
  add column if not exists accepts_platform_couriers boolean not null default false;

comment on column restaurants.accepts_platform_couriers is
  'Padrao falso: o estabelecimento entrega com gente propria. Ligar isto abre a corrida aos autonomos da plataforma.';

-- -----------------------------------------------------------------------------
-- Quem chegou com a chave de servico?
--
-- A chave service_role ignora a RLS por completo, mas NAO ignora gatilho - e um
-- gatilho que barra a rotina de administracao nao protege nada, so quebra seed
-- e manutencao.
--
-- Nao da para perguntar `current_user`: dentro de uma funcao SECURITY DEFINER
-- ele e o DONO da funcao, nao quem chamou. Quem sabe a verdade e o JWT. As duas
-- formas abaixo existem porque o Supabase ja usou as duas.
-- -----------------------------------------------------------------------------
create or replace function app.is_service_role()
returns boolean
language sql
stable
as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
    ''
  ) = 'service_role';
$$;

-- -----------------------------------------------------------------------------
-- Este entregador atende este estabelecimento?
-- -----------------------------------------------------------------------------
create or replace function app.courier_serves(p_restaurant uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from couriers c
    join restaurants r on r.id = p_restaurant
    where c.user_id = auth.uid()
      and c.deleted_at is null
      and c.status = 'approved'
      and (
        c.restaurant_id = p_restaurant
        or (c.restaurant_id is null and r.accepts_platform_couriers)
      )
  );
$$;

comment on function app.courier_serves(uuid) is
  'Quem pode pegar corrida deste estabelecimento: entregador dele, ou autonomo quando o estabelecimento aceita gente de fora.';

-- Sou a gestao do estabelecimento deste entregador?
create or replace function app.manages_courier(p_courier uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from couriers c
    where c.id = p_courier
      and c.restaurant_id is not null
      and app.can_manage(c.restaurant_id)
  );
$$;

-- -----------------------------------------------------------------------------
-- A fila deixa de ser da plataforma e passa a ser do estabelecimento
-- -----------------------------------------------------------------------------
drop policy if exists "entrega visivel a quem participa" on deliveries;

create policy "entrega visivel a quem participa"
  on deliveries for select
  to authenticated
  using (
    app.is_member(restaurant_id)
    or app.is_platform_admin()
    or courier_id = app.my_courier_id()
    -- Antes: qualquer entregador aprovado da plataforma. Agora: so quem
    -- atende este estabelecimento.
    or (status = 'searching_courier' and app.courier_serves(restaurant_id))
    or app.is_order_customer(order_id)
  );

drop policy if exists "entregador e equipe atualizam a entrega" on deliveries;

create policy "entregador e equipe atualizam a entrega"
  on deliveries for update
  to authenticated
  using (
    app.is_member(restaurant_id)
    or app.is_platform_admin()
    or courier_id = app.my_courier_id()
    or (status = 'searching_courier' and app.courier_serves(restaurant_id))
  )
  with check (
    app.is_member(restaurant_id)
    or app.is_platform_admin()
    or courier_id = app.my_courier_id()
    or (status = 'searching_courier' and app.courier_serves(restaurant_id))
  );

-- -----------------------------------------------------------------------------
-- O estabelecimento enxerga e administra os proprios entregadores
-- -----------------------------------------------------------------------------
drop policy if exists "entregador ve o proprio cadastro" on couriers;
drop policy if exists "cadastro de entregador visivel a quem o emprega" on couriers;

create policy "cadastro de entregador visivel a quem o emprega"
  on couriers for select
  to authenticated
  using (
    user_id = auth.uid()
    or app.is_platform_admin()
    or (restaurant_id is not null and app.is_member(restaurant_id))
  );

drop policy if exists "entregador edita o proprio cadastro" on couriers;

create policy "entregador edita o proprio cadastro"
  on couriers for update
  to authenticated
  using (
    user_id = auth.uid()
    or app.is_platform_admin()
    or app.manages_courier(id)
  )
  with check (
    user_id = auth.uid()
    or app.is_platform_admin()
    or app.manages_courier(id)
  );

-- -----------------------------------------------------------------------------
-- Quem aprova, e o que continua trancado
-- -----------------------------------------------------------------------------
create or replace function app.guard_courier_platform_fields()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_gestao boolean := new.restaurant_id is not null
                      and app.can_manage(new.restaurant_id);
begin
  -- Escrita vinda de gatilho (o contador de entregas, por exemplo) passa.
  if pg_trigger_depth() > 1 then
    return new;
  end if;

  -- E a chave de servico tambem: ela ja pode tudo por definicao.
  if app.is_service_role() then
    return new;
  end if;

  if not app.is_platform_admin() then
    -- A aprovacao agora tem dois donos possiveis: a plataforma, para o
    -- autonomo, e o estabelecimento, para a gente dele. Ninguem se aprova.
    if new.status is distinct from old.status and not v_gestao then
      raise exception 'Somente a plataforma ou o estabelecimento aprova um entregador.'
        using errcode = 'insufficient_privilege';
    end if;

    -- Trocar de estabelecimento so antes de ser aprovado. Depois disso o
    -- vinculo e do estabelecimento, nao do entregador - senao alguem aprovado
    -- num lugar se mudaria para outro ja aprovado.
    if new.restaurant_id is distinct from old.restaurant_id
       and old.status = 'approved'
       and not v_gestao then
      raise exception 'O vinculo com o estabelecimento so muda antes da aprovacao.'
        using errcode = 'insufficient_privilege';
    end if;

    -- Reputacao continua fora do alcance dos dois.
    new.rating_avg := old.rating_avg;
    new.rating_count := old.rating_count;
    new.deliveries_count := old.deliveries_count;
  end if;

  if new.availability <> 'offline' and new.status <> 'approved' then
    raise exception 'Entregador ainda nao aprovado nao pode ficar disponivel.'
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;
