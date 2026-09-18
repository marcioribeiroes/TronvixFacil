-- =============================================================================
-- Tronvix Facil - a corrida na fila precisa mostrar o pedido
--
-- A politica de orders libera o entregador designado:
--
--   or app.is_order_courier(id)   -- deliveries.courier_id = o meu
--
-- So que na fila ainda nao ha entregador designado - courier_id e nulo, e e
-- justamente disso que a fila e feita. Resultado: o entregador enxergava a
-- corrida e nao enxergava o pedido. O cartao na tela vinha sem nome da loja,
-- sem endereco de retirada, sem endereco de entrega e sem coordenada; o mapa
-- abria vazio e ninguem tinha como decidir se aceitava.
--
-- O que este arquivo libera, e o que nao libera: o pedido OFERECIDO fica
-- visivel a quem atende aquele estabelecimento. Nome, telefone e endereco do
-- cliente entram nisso - e tem de entrar, porque sao a decisao ("da para ir
-- ate la?") e o trabalho. Os ITENS do pedido continuam fora: o que a pessoa
-- comeu nao e assunto de quem so vai carregar a sacola, e quem aceita a corrida
-- passa a ver tudo pelo caminho normal.
-- =============================================================================

create or replace function app.is_order_offered_to_courier(p_order uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from deliveries d
    where d.order_id = p_order
      and d.status = 'searching_courier'
      and app.courier_serves(d.restaurant_id)
  );
$$;

comment on function app.is_order_offered_to_courier(uuid) is
  'O pedido esta na fila de corridas e eu atendo este estabelecimento. E o que deixa o cartao da fila mostrar de onde sai e para onde vai.';

drop policy if exists "pedido visivel a quem participa dele" on orders;

create policy "pedido visivel a quem participa dele"
  on orders for select
  to authenticated
  using (
    customer_id = auth.uid()
    or app.is_member(restaurant_id)
    or app.is_platform_admin()
    or app.is_order_courier(id)
    or app.is_order_offered_to_courier(id)
  );

-- O pagamento tambem: o entregador precisa saber, ANTES de aceitar, se vai
-- receber dinheiro na porta. Sair para uma entrega de R$ 80 em especie sem
-- troco e problema dele.
drop policy if exists "pagamento segue a visibilidade do pedido" on payments;

create policy "pagamento segue a visibilidade do pedido"
  on payments for select
  to authenticated
  using (app.can_see_order(order_id) or app.is_order_offered_to_courier(order_id));
