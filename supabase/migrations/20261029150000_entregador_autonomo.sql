-- =============================================================================
-- Tronvix Facil - o entregador autonomo se cadastra
--
-- O banco ja conhecia o autonomo (couriers.restaurant_id nulo) e o
-- restaurante ja podia aceita-lo (accepts_platform_couriers). Faltava a porta:
-- o cadastro com o que a plataforma precisa para aprovar alguem que ela nao
-- conhece - quem e (CPF, idade, selfie), se pode dirigir (CNH), o que dirige
-- (documento do veiculo), onde trabalha e como recebe (Pix).
--
--   couriers.*                       os dados do cadastro
--   documentos-entregador            balde PRIVADO: <usuario>/<arquivo>
--   cadastrar_entregador_autonomo    valida e grava; reenviar depois de
--                                    recusado volta para a fila
--   app.cidades_atendidas            onde a plataforma opera hoje
--
-- Quem aprova o autonomo e a plataforma (tela de admin). O entregador de
-- restaurante continua como era: o restaurante aprova, sem documento.
-- =============================================================================

alter table couriers
  add column if not exists cpf text,
  add column if not exists birth_date date,
  add column if not exists vehicle_model text,
  add column if not exists vehicle_color text,
  add column if not exists city text,
  add column if not exists pix_key text,
  add column if not exists document_cnh_path text,
  add column if not exists document_vehicle_path text,
  add column if not exists document_selfie_path text,
  add column if not exists review_note text,
  add column if not exists submitted_at timestamptz;

alter table couriers drop constraint if exists couriers_cpf_format;
alter table couriers
  add constraint couriers_cpf_format check (cpf is null or cpf ~ '^\d{11}$');

alter table couriers drop constraint if exists couriers_review_note_length;
alter table couriers
  add constraint couriers_review_note_length check (review_note is null or length(review_note) <= 500);

-- Um CPF, um cadastro: quem foi recusado ou suspenso nao volta com outra conta.
create unique index if not exists couriers_cpf_unique
  on couriers (cpf)
  where cpf is not null and deleted_at is null;

comment on column couriers.review_note is
  'O motivo da recusa ou da suspensao, que o entregador ve no aplicativo.';

-- -----------------------------------------------------------------------------
-- Onde a plataforma opera
-- -----------------------------------------------------------------------------

-- Lista no banco, e nao na tela: a cidade que nao esta aqui e recusada no
-- cadastro mesmo que alguem chame a API direto. Abrir uma cidade nova e uma
-- migracao de uma linha.
create or replace function app.cidades_atendidas()
returns text[]
language sql
immutable
as $$
  select array['Cachoeiro de Itapemirim'];
$$;

create or replace function public.cidades_para_entregador()
returns text[]
language sql
stable
as $$
  select app.cidades_atendidas();
$$;

grant execute on function public.cidades_para_entregador() to anon, authenticated;

-- -----------------------------------------------------------------------------
-- CPF
-- -----------------------------------------------------------------------------

create or replace function app.cpf_valido(p_cpf text)
returns boolean
language plpgsql
immutable
as $$
declare
  d int[];
  soma int;
  resto int;
  i int;
begin
  if p_cpf is null or p_cpf !~ '^\d{11}$' or p_cpf ~ '^(\d)\1{10}$' then
    return false;
  end if;

  select array_agg(substr(p_cpf, n, 1)::int order by n) into d
    from generate_series(1, 11) n;

  soma := 0;
  for i in 1..9 loop soma := soma + d[i] * (11 - i); end loop;
  resto := (soma * 10) % 11;
  if resto = 10 then resto := 0; end if;
  if resto <> d[10] then return false; end if;

  soma := 0;
  for i in 1..10 loop soma := soma + d[i] * (12 - i); end loop;
  resto := (soma * 10) % 11;
  if resto = 10 then resto := 0; end if;
  return resto = d[11];
end;
$$;

-- -----------------------------------------------------------------------------
-- O guarda: reenviar depois de recusado
-- -----------------------------------------------------------------------------

-- Igual ao de 20260917100600, com uma porta a mais: o proprio entregador
-- recusado pode voltar para "pendente" - e o reenvio do cadastro corrigido.
-- Aprovar continua sendo so da plataforma ou do estabelecimento.
create or replace function app.guard_courier_platform_fields()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_gestao boolean := new.restaurant_id is not null
                      and app.can_manage(new.restaurant_id);
  v_reenvio boolean := old.status = 'rejected'
                       and new.status = 'pending'
                       and old.user_id = auth.uid();
begin
  if pg_trigger_depth() > 1 then
    return new;
  end if;

  if app.is_service_role() then
    return new;
  end if;

  if not app.is_platform_admin() then
    if new.status is distinct from old.status and not v_gestao and not v_reenvio then
      raise exception 'Somente a plataforma ou o estabelecimento aprova um entregador.'
        using errcode = 'insufficient_privilege';
    end if;

    if new.restaurant_id is distinct from old.restaurant_id
       and old.status = 'approved'
       and not v_gestao then
      raise exception 'O vinculo com o estabelecimento so muda antes da aprovacao.'
        using errcode = 'insufficient_privilege';
    end if;

    -- O motivo da recusa e de quem recusou.
    if new.review_note is distinct from old.review_note and not v_gestao and not v_reenvio then
      new.review_note := old.review_note;
    end if;

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

-- -----------------------------------------------------------------------------
-- O cadastro
-- -----------------------------------------------------------------------------

create or replace function public.cadastrar_entregador_autonomo(
  p_cpf text,
  p_nascimento date,
  p_veiculo text,
  p_placa text,
  p_modelo text,
  p_cor text,
  p_cidade text,
  p_chave_pix text,
  p_cnh text,                 -- caminho no balde: <usuario>/...
  p_documento_do_veiculo text,
  p_selfie text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_usuario uuid := auth.uid();
  v_cpf text := regexp_replace(coalesce(p_cpf, ''), '\D', '', 'g');
  v_placa text := upper(regexp_replace(coalesce(p_placa, ''), '[^A-Za-z0-9]', '', 'g'));
  v_motorizado boolean := p_veiculo in ('motorcycle', 'car');
  v_pasta text := v_usuario::text || '/';
  v_atual couriers;
  v_id uuid;
begin
  if v_usuario is null then
    raise exception 'Entre na sua conta para se cadastrar.' using errcode = 'insufficient_privilege';
  end if;

  if not app.cpf_valido(v_cpf) then
    raise exception 'CPF invalido.' using errcode = 'check_violation';
  end if;

  if p_nascimento is null or p_nascimento > (current_date - interval '18 years')::date
     or p_nascimento < date '1930-01-01' then
    raise exception 'Para entregar e preciso ter 18 anos ou mais.' using errcode = 'check_violation';
  end if;

  if p_veiculo is null or p_veiculo not in ('motorcycle', 'bicycle', 'car', 'foot') then
    raise exception 'Escolha como voce entrega.' using errcode = 'check_violation';
  end if;

  if v_motorizado then
    if v_placa !~ '^[A-Z]{3}[0-9][A-Z0-9][0-9]{2}$' then
      raise exception 'Placa invalida: use o formato ABC1D23 ou ABC1234.' using errcode = 'check_violation';
    end if;
    if length(btrim(coalesce(p_modelo, ''))) not between 2 and 60 then
      raise exception 'Informe o modelo do veiculo.' using errcode = 'check_violation';
    end if;
    if length(btrim(coalesce(p_cor, ''))) not between 2 and 30 then
      raise exception 'Informe a cor do veiculo.' using errcode = 'check_violation';
    end if;
  end if;

  if p_cidade is null or not (p_cidade = any (app.cidades_atendidas())) then
    raise exception 'Ainda nao atendemos essa cidade.' using errcode = 'check_violation';
  end if;

  if length(btrim(coalesce(p_chave_pix, ''))) not between 5 and 77 then
    raise exception 'Informe a chave Pix para receber.' using errcode = 'check_violation';
  end if;

  -- Os documentos tem de estar na pasta da propria pessoa: apontar para o
  -- arquivo de outro entregador seria se cadastrar com a CNH dele.
  if coalesce(p_cnh, '') not like v_pasta || '%'
     or coalesce(p_selfie, '') not like v_pasta || '%'
     or (v_motorizado and coalesce(p_documento_do_veiculo, '') not like v_pasta || '%') then
    raise exception 'Envie as fotos dos documentos pedidos.' using errcode = 'check_violation';
  end if;

  if exists (
    select 1 from couriers
     where cpf = v_cpf and user_id <> v_usuario and deleted_at is null
  ) then
    raise exception 'Este CPF ja tem cadastro de entregador.' using errcode = 'unique_violation';
  end if;

  select * into v_atual from couriers where user_id = v_usuario for update;

  if v_atual.id is not null then
    if v_atual.restaurant_id is not null and v_atual.status = 'approved' then
      raise exception 'Voce ja entrega por um estabelecimento. Fale com ele para sair antes.'
        using errcode = 'check_violation';
    end if;
    if v_atual.status in ('approved', 'suspended') then
      raise exception 'Seu cadastro ja foi analisado. Fale com o suporte.'
        using errcode = 'check_violation';
    end if;

    update couriers set
      restaurant_id = null,
      status = 'pending',
      availability = 'offline',
      cpf = v_cpf,
      birth_date = p_nascimento,
      vehicle_type = p_veiculo,
      vehicle_plate = case when v_motorizado then v_placa end,
      vehicle_model = case when v_motorizado then btrim(p_modelo) end,
      vehicle_color = case when v_motorizado then btrim(p_cor) end,
      city = p_cidade,
      pix_key = btrim(p_chave_pix),
      document_cnh_path = p_cnh,
      document_vehicle_path = case when v_motorizado then p_documento_do_veiculo end,
      document_selfie_path = p_selfie,
      review_note = null,
      submitted_at = now()
    where id = v_atual.id
    returning id into v_id;
  else
    insert into couriers (
      user_id, restaurant_id, status, vehicle_type, vehicle_plate, vehicle_model,
      vehicle_color, cpf, birth_date, city, pix_key, document_cnh_path,
      document_vehicle_path, document_selfie_path, submitted_at
    )
    values (
      v_usuario, null, 'pending', p_veiculo,
      case when v_motorizado then v_placa end,
      case when v_motorizado then btrim(p_modelo) end,
      case when v_motorizado then btrim(p_cor) end,
      v_cpf, p_nascimento, p_cidade, btrim(p_chave_pix), p_cnh,
      case when v_motorizado then p_documento_do_veiculo end,
      p_selfie, now()
    )
    returning id into v_id;
  end if;

  return v_id;
end;
$$;

revoke all on function public.cadastrar_entregador_autonomo(
  text, date, text, text, text, text, text, text, text, text, text
) from public;
grant execute on function public.cadastrar_entregador_autonomo(
  text, date, text, text, text, text, text, text, text, text, text
) to authenticated;

-- -----------------------------------------------------------------------------
-- O balde dos documentos
-- -----------------------------------------------------------------------------

-- Fora do bloco, como app.pasta_da_loja: as politicas a chamam, e os testes do
-- banco conferem a regra sem o Supabase inteiro.
create or replace function app.dono_da_pasta(p_caminho text)
returns uuid
language plpgsql
immutable
as $$
begin
  return split_part(coalesce(p_caminho, ''), '/', 1)::uuid;
exception
  when invalid_text_representation then
    return null;
end;
$$;

do $$
begin
  if not exists (select 1 from information_schema.schemata where schema_name = 'storage') then
    raise notice 'schema storage indisponivel: documentos de entregador desligados neste banco.';
    return;
  end if;

  -- PRIVADO, ao contrario das fotos do cardapio: CNH e selfie sao dado pessoal.
  -- Quem le e o dono e a plataforma, por URL assinada de validade curta.
  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values (
    'documentos-entregador', 'documentos-entregador', false,
    10485760,
    array['image/jpeg', 'image/png', 'image/webp', 'image/heic']
  )
  on conflict (id) do update
    set public = excluded.public,
        file_size_limit = excluded.file_size_limit,
        allowed_mime_types = excluded.allowed_mime_types;

  execute $p$
    drop policy if exists "entregador e plataforma leem os documentos" on storage.objects;
    create policy "entregador e plataforma leem os documentos"
      on storage.objects for select
      to authenticated
      using (
        bucket_id = 'documentos-entregador'
        and (app.dono_da_pasta(name) = auth.uid() or app.is_platform_admin())
      );
  $p$;

  execute $p$
    drop policy if exists "entregador envia os proprios documentos" on storage.objects;
    create policy "entregador envia os proprios documentos"
      on storage.objects for insert
      to authenticated
      with check (
        bucket_id = 'documentos-entregador'
        and app.dono_da_pasta(name) = auth.uid()
      );
  $p$;

  execute $p$
    drop policy if exists "entregador troca os proprios documentos" on storage.objects;
    create policy "entregador troca os proprios documentos"
      on storage.objects for update
      to authenticated
      using (
        bucket_id = 'documentos-entregador'
        and app.dono_da_pasta(name) = auth.uid()
      );
  $p$;
end;
$$;
