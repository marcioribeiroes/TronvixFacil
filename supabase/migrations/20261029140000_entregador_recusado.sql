-- =============================================================================
-- Tronvix Facil - o entregador pode ser recusado
--
-- Ate aqui o cadastro so tinha pendente, aprovado e suspenso. Recusar era
-- suspender quem nunca trabalhou - e o motoboy nao sabia se tinha sido
-- recusado ou se ainda estava na fila. Com o cadastro do autonomo, que manda
-- documento, a plataforma precisa dizer "nao, e por isso".
--
-- Arquivo proprio de proposito: um valor novo de enum so pode ser usado depois
-- que a transacao que o criou termina. A migracao seguinte ja o usa.
-- =============================================================================

alter type courier_status add value if not exists 'rejected';
