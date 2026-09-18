-- =============================================================================
-- Um terceiro jeito de receber o pedido: na mesa.
--
-- Ate aqui o sistema conhecia entrega e retirada. Falta o caso do salao: o
-- cliente sentado, lendo o QR da mesa, pedindo e pagando pelo proprio celular,
-- e o pedido caindo na cozinha com o numero da mesa.
--
-- Esta migracao so acrescenta o valor ao enum, e esta sozinha de proposito: o
-- Postgres nao deixa usar um valor de enum na mesma transacao que o criou. Todo
-- o resto - mesas, regras, fechamento - vem no arquivo seguinte.
-- =============================================================================

alter type fulfillment_type add value if not exists 'dine_in';
