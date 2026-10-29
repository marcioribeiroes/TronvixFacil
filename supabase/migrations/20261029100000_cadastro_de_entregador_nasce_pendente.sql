-- =============================================================================
-- Tronvix Facil - o cadastro de entregador nasce pendente
--
-- O guarda de couriers so olhava UPDATE. A politica de INSERT confere apenas
-- que a linha e da propria pessoa - e a chave anonima vai publicada em todo
-- aplicativo instalado. Bastava um INSERT direto na API com status
-- 'approved' para alguem se aprovar sozinho, ja disponivel e com reputacao
-- inventada.
--
-- Agora o INSERT de usuario comum e normalizado: nasce pendente, offline e sem
-- historico. Quem aprova continua sendo o estabelecimento (ou a plataforma),
-- pelo UPDATE que o guarda antigo ja vigia.
-- =============================================================================

create or replace function app.guard_courier_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Sem usuario na requisicao (migracao, rotina do banco) ou com a chave de
  -- servico: quem escreve ja pode tudo.
  if auth.uid() is null or app.is_service_role() or app.is_platform_admin() then
    return new;
  end if;

  -- Corrige em vez de recusar: o aplicativo ja manda 'pending', e uma versao
  -- antiga que mandasse outra coisa nao deve travar o cadastro de ninguem.
  new.status := 'pending';
  new.availability := 'offline';
  new.rating_avg := 0;
  new.rating_count := 0;
  new.deliveries_count := 0;
  new.approved_at := null;
  new.approved_by := null;

  return new;
end;
$$;

drop trigger if exists couriers_guard_insert on couriers;

create trigger couriers_guard_insert
  before insert on couriers
  for each row execute function app.guard_courier_insert();
