-- =============================================================================
-- Apagar a propria conta.
--
-- A Play Store nao publica aplicativo que deixa criar conta e nao deixa apagar:
-- exige um caminho dentro do aplicativo e uma pagina publica explicando. A LGPD
-- pede a mesma coisa por outro motivo. E "escreva para o suporte" nao e um
-- caminho — e uma fila.
--
-- O que apagar significa aqui:
--
--   some       a credencial (auth.users), o perfil, os enderecos, os
--              favoritos, os avisos, as avaliacoes — tudo que e a pessoa.
--   fica       o pedido, sem quem o fez. Ele e o registro de uma venda de
--              TERCEIRO: o restaurante tem obrigacao fiscal sobre ela e nao
--              pode perder o faturamento de ontem porque um cliente saiu.
--              Some dali o nome, o telefone, a rua e as coordenadas; sobram o
--              bairro e a cidade, que sustentam a estatistica de entrega da
--              loja sem apontar para ninguem.
--
-- Quem NAO se apaga sozinho: dono ou funcionario de loja, e entregador. A
-- conta deles carrega o negocio de outra gente — pedido em andamento, comissao,
-- corrida paga. Some por aqui e o estrago cai no restaurante. Esses falam com o
-- suporte, que apaga sabendo o que esta desmontando.
-- =============================================================================

create or replace function public.apagar_minha_conta()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_eu uuid := auth.uid();
  v_abertos int;
begin
  if v_eu is null then
    raise exception 'Entre na conta para poder apaga-la.'
      using errcode = 'insufficient_privilege';
  end if;

  if exists (
    select 1 from restaurant_members m
     where m.user_id = v_eu and m.is_active and m.deleted_at is null
  ) then
    raise exception
      'Esta conta administra um estabelecimento. Fale com o suporte para encerrar a loja antes de apagar a conta.'
      using errcode = 'check_violation';
  end if;

  if exists (select 1 from couriers c where c.user_id = v_eu and c.deleted_at is null) then
    raise exception
      'Esta conta e de entregador. Fale com o suporte: ha corridas e pagamentos ligados a ela.'
      using errcode = 'check_violation';
  end if;

  -- Pedido em andamento e comida sendo feita. Apagar o cliente no meio disso
  -- deixa o balcao com um pedido sem ninguem para avisar.
  select count(*) into v_abertos
    from orders o
   where o.customer_id = v_eu
     and o.status not in ('delivered', 'cancelled', 'rejected');

  if v_abertos > 0 then
    raise exception
      'Voce tem % pedido(s) em andamento. Espere terminar ou cancele antes de apagar a conta.', v_abertos
      using errcode = 'check_violation';
  end if;

  -- A venda continua; quem comprou, nao.
  update orders
     set customer_name = 'Cliente removido',
         customer_phone = null,
         address_summary = null,
         address_postal_code = null,
         address_latitude = null,
         address_longitude = null,
         notes = null
   where customer_id = v_eu;

  -- Daqui em diante e cascata: profiles referencia auth.users com ON DELETE
  -- CASCADE, e enderecos, favoritos, avaliacoes e avisos referenciam profiles
  -- do mesmo jeito. orders.customer_id e ON DELETE SET NULL de proposito.
  delete from auth.users where id = v_eu;
end;
$$;

revoke all on function public.apagar_minha_conta() from public;
grant execute on function public.apagar_minha_conta() to authenticated;

comment on function public.apagar_minha_conta is
  'Apaga a conta de quem chamou. Recusa dono de loja, entregador e quem tem pedido em andamento; anonimiza os pedidos antigos e deixa a venda de pe.';
