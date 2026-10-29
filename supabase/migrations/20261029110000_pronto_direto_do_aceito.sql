-- =============================================================================
-- Tronvix Facil - "pronto" direto de "aceito"
--
-- Nem todo pedido passa pelo fogo: a bebida, o doce da vitrine, o lanche que ja
-- estava montado. Obrigar a cozinha a tocar em "comecar preparo" so para tocar
-- em "pronto" logo depois e um clique que nao diz nada - e, na correria, o
-- pedido fica parado em "aceito" porque ninguem quer dar os dois toques.
--
-- So o atalho confirmed -> ready e novo; o resto do fluxo nao muda. O espelho em
-- TypeScript (src/modules/pedidos/maquina-de-estados.ts) e em Dart
-- (celular/lib/modelos/enums.dart) muda junto.
-- =============================================================================

create or replace function app.order_transition_allowed(
  p_from order_status,
  p_to order_status
)
returns boolean
language sql
immutable
as $$
  select case p_from
    when 'awaiting_payment' then p_to in ('received', 'cancelled')
    when 'received'         then p_to in ('confirmed', 'rejected', 'cancelled')
    -- "Pronto" direto: o pedido que nao precisa de preparo.
    when 'confirmed'        then p_to in ('preparing', 'ready', 'cancelled')
    when 'preparing'        then p_to in ('ready', 'cancelled')
    -- De "pronto" o caminho depende do tipo: entrega sai para a rua,
    -- retirada e concluida no balcao.
    when 'ready'            then p_to in ('out_for_delivery', 'delivered', 'cancelled')
    when 'out_for_delivery' then p_to in ('delivered', 'cancelled')
    -- Estados terminais nao tem saida.
    when 'delivered'        then false
    when 'cancelled'        then false
    when 'rejected'         then false
  end;
$$;
