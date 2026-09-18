-- =============================================================================
-- O guarda do ultimo proprietario impedia apagar o proprio estabelecimento.
--
-- app.guard_last_owner existe por um bom motivo: tirar o ultimo dono deixa a
-- loja sem ninguem que possa entrar nela - inacessivel para sempre, com
-- cardapio e historico dentro.
--
-- Mas ele dispara tambem quando a linha de restaurant_members sai EM CASCATA,
-- porque o estabelecimento inteiro esta sendo apagado. Ai a regra protege algo
-- que nao existe mais, e o efeito e o contrario do pretendido: o cadastro fica
-- impossivel de remover.
--
-- Encontrado ao apagar um cadastro de teste:
--
--   delete from restaurants where slug = '...'
--   ERRO: O estabelecimento precisa de ao menos um proprietario ativo.
--
-- E apagar a CONTA do dono dava o mesmo erro por outro caminho - profiles
-- cascateia para restaurant_members -, o que tornava impossivel remover a
-- conta de qualquer proprietario. Numa plataforma que precisa atender pedido
-- de exclusao de dados, isso e mais do que inconveniente.
--
-- A correcao nao afrouxa a regra: mantem a excecao no unico caso em que ela
-- perdeu o sentido - quando o estabelecimento ja nao esta mais la.
-- =============================================================================

create or replace function app.guard_last_owner()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_restaurant uuid := coalesce(old.restaurant_id, new.restaurant_id);
  v_owners int;
  v_was_owner boolean := old.role = 'owner' and old.is_active and old.deleted_at is null;
  v_still_owner boolean := tg_op = 'UPDATE'
    and new.role = 'owner' and new.is_active and new.deleted_at is null;
begin
  if not v_was_owner or v_still_owner then
    return coalesce(new, old);
  end if;

  -- O estabelecimento esta sendo apagado e esta linha sai em cascata: nao ha
  -- mais loja a proteger. A propria ausencia da linha em restaurants e a
  -- prova - numa cascata, o pai ja saiu quando o gatilho do filho roda.
  if not exists (select 1 from restaurants where id = v_restaurant) then
    return coalesce(new, old);
  end if;

  select count(*) into v_owners
  from restaurant_members m
  where m.restaurant_id = v_restaurant
    and m.role = 'owner'
    and m.is_active
    and m.deleted_at is null;

  if v_owners <= 1 then
    raise exception 'O estabelecimento precisa de ao menos um proprietario ativo.'
      using errcode = 'check_violation';
  end if;

  return coalesce(new, old);
end;
$$;
