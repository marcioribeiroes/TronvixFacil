/**
 * Maquina de estados do pedido e da entrega.
 *
 * Este arquivo e o espelho em TypeScript das funcoes
 * app.order_transition_allowed e app.delivery_transition_allowed, definidas em
 * supabase/migrations/20260917100200_pedidos.sql.
 *
 * Por que a regra existe duas vezes:
 *
 *   No banco, para ser inviolavel. Nenhum caminho - tela com bug, chamada
 *   direta a API, script de migracao apressado - consegue levar um pedido de
 *   "entregue" de volta para "em preparo".
 *
 *   Aqui, para a interface saber o que oferecer ANTES de tentar. O painel do
 *   restaurante precisa desenhar os botoes possiveis para cada pedido; sem
 *   isso, a unica forma de descobrir seria mandar e ver o banco recusar.
 *
 * As duas copias sao verificadas contra a mesma tabela de casos em
 * maquina-de-estados.test.ts e em supabase/tests/regras_do_pedido.sql. Mudar
 * uma sem mudar a outra quebra os testes.
 */

export const SITUACOES_DO_PEDIDO = [
  "awaiting_payment",
  "received",
  "confirmed",
  "preparing",
  "ready",
  "out_for_delivery",
  "delivered",
  "cancelled",
  "rejected",
] as const

export type SituacaoDoPedido = (typeof SITUACOES_DO_PEDIDO)[number]

export const SITUACOES_DA_ENTREGA = [
  "pending",
  "searching_courier",
  "assigned",
  "heading_to_restaurant",
  "picked_up",
  "heading_to_customer",
  "delivered",
  "cancelled",
] as const

export type SituacaoDaEntrega = (typeof SITUACOES_DA_ENTREGA)[number]

export type TipoDeEntrega = "delivery" | "pickup" | "dine_in"

/**
 * Como o pedido chega ao cliente, em palavras.
 *
 * "Mesa" e nao "consumo no local": e o que o balcao fala, e a tela tem de
 * falar a lingua de quem trabalha nela.
 */
export const ROTULO_DO_TIPO: Record<TipoDeEntrega, string> = {
  delivery: "Entrega",
  pickup: "Retirada",
  dine_in: "Mesa",
}

/** Transicoes validas do pedido. Espelho de app.order_transition_allowed. */
const TRANSICOES_DO_PEDIDO: Record<SituacaoDoPedido, readonly SituacaoDoPedido[]> = {
  awaiting_payment: ["received", "cancelled"],
  received: ["confirmed", "rejected", "cancelled"],
  confirmed: ["preparing", "cancelled"],
  preparing: ["ready", "cancelled"],
  // De "pronto" o caminho depende do tipo: entrega vai para a rua, retirada
  // se conclui no balcao. A checagem do tipo fica em transicaoDoPedidoPermitida.
  ready: ["out_for_delivery", "delivered", "cancelled"],
  out_for_delivery: ["delivered", "cancelled"],
  delivered: [],
  cancelled: [],
  rejected: [],
}

/** Transicoes validas da entrega. Espelho de app.delivery_transition_allowed. */
const TRANSICOES_DA_ENTREGA: Record<SituacaoDaEntrega, readonly SituacaoDaEntrega[]> = {
  pending: ["searching_courier", "cancelled"],
  searching_courier: ["assigned", "cancelled"],
  // A volta para "searching_courier" e a desistencia do entregador: devolve a
  // corrida a fila em vez de deixar o pedido preso.
  assigned: ["heading_to_restaurant", "searching_courier", "cancelled"],
  heading_to_restaurant: ["picked_up", "searching_courier", "cancelled"],
  picked_up: ["heading_to_customer", "cancelled"],
  heading_to_customer: ["delivered", "cancelled"],
  delivered: [],
  cancelled: [],
}

export function transicaoDoPedidoPermitida(
  de: SituacaoDoPedido,
  para: SituacaoDoPedido,
  tipo: TipoDeEntrega = "delivery",
): boolean {
  if (!TRANSICOES_DO_PEDIDO[de]?.includes(para)) return false
  // So a entrega passa pela rua. Retirada termina no balcao, e mesa termina
  // quando o garcom poe o prato na frente do cliente - nenhuma das duas tem
  // "saiu para entrega".
  if (para === "out_for_delivery" && tipo !== "delivery") return false
  return true
}

/**
 * Em que situacao do pedido a comida pode ser retirada.
 *
 * `ready` e o caso que passa a existir: a corrida e aceita durante o preparo, e
 * o entregador chega antes da comida. `out_for_delivery` e o caminho antigo, em
 * que o balcao marcou o pedido como saido antes de existir entregador — esse
 * continua valendo, e por isso os dois estao aqui.
 */
const SITUACOES_QUE_PERMITEM_RETIRAR: readonly SituacaoDoPedido[] = [
  "ready",
  "out_for_delivery",
]

/**
 * Espelho de app.guard_delivery_status.
 *
 * `situacaoDoPedido` e opcional porque a fila desenha o cartao da corrida sem
 * ter o pedido em maos. Quando vem, vale a trava de "peguei o pedido": sem ela
 * o entregador que chega cedo empurra para a rua um pedido ainda no fogo.
 */
export function transicaoDaEntregaPermitida(
  de: SituacaoDaEntrega,
  para: SituacaoDaEntrega,
  situacaoDoPedido?: SituacaoDoPedido,
): boolean {
  if (!TRANSICOES_DA_ENTREGA[de]?.includes(para)) return false
  if (para === "picked_up" && situacaoDoPedido !== undefined) {
    return SITUACOES_QUE_PERMITEM_RETIRAR.includes(situacaoDoPedido)
  }
  return true
}

/** O que a interface pode oferecer a partir da situacao atual. */
export function proximasSituacoesDoPedido(
  de: SituacaoDoPedido,
  tipo: TipoDeEntrega = "delivery",
): SituacaoDoPedido[] {
  return (TRANSICOES_DO_PEDIDO[de] ?? []).filter((para) =>
    transicaoDoPedidoPermitida(de, para, tipo),
  )
}

export function proximasSituacoesDaEntrega(de: SituacaoDaEntrega): SituacaoDaEntrega[] {
  return [...(TRANSICOES_DA_ENTREGA[de] ?? [])]
}

/** Pedido encerrado: nao aceita mais nenhuma transicao. */
export function pedidoEncerrado(situacao: SituacaoDoPedido): boolean {
  return TRANSICOES_DO_PEDIDO[situacao].length === 0
}

/** Pedido que ainda ocupa a cozinha ou a rua - o que o painel chama de "em andamento". */
export function pedidoEmAndamento(situacao: SituacaoDoPedido): boolean {
  return (
    situacao === "received" ||
    situacao === "confirmed" ||
    situacao === "preparing" ||
    situacao === "ready" ||
    situacao === "out_for_delivery"
  )
}

// ---------------------------------------------------------------------------
// Apresentacao
//
// O banco fala em ingles; a tela fala com o dono da lanchonete. A traducao
// mora aqui, num lugar so, para nao existirem cinco versoes de "Saiu para
// entrega" espalhadas pelos quatro aplicativos.
// ---------------------------------------------------------------------------

export const ROTULO_DA_SITUACAO: Record<SituacaoDoPedido, string> = {
  awaiting_payment: "Aguardando pagamento",
  received: "Recebido",
  confirmed: "Confirmado",
  preparing: "Em preparo",
  ready: "Pronto",
  out_for_delivery: "Saiu para entrega",
  delivered: "Entregue",
  cancelled: "Cancelado",
  rejected: "Recusado",
}

export const ROTULO_DA_ENTREGA: Record<SituacaoDaEntrega, string> = {
  pending: "Aguardando",
  searching_courier: "Procurando entregador",
  assigned: "Entregador a caminho",
  heading_to_restaurant: "Indo ao restaurante",
  picked_up: "Pedido retirado",
  heading_to_customer: "A caminho do cliente",
  delivered: "Entregue",
  cancelled: "Cancelada",
}

/**
 * Verbo da acao, para o botao. Diferente do rotulo: a coluna mostra "Em
 * preparo", mas o botao que leva ate ela diz "Iniciar preparo".
 */
export const ACAO_DA_SITUACAO: Record<SituacaoDoPedido, string> = {
  awaiting_payment: "Aguardar pagamento",
  received: "Receber",
  confirmed: "Confirmar pedido",
  preparing: "Iniciar preparo",
  ready: "Marcar como pronto",
  out_for_delivery: "Despachar",
  delivered: "Concluir",
  cancelled: "Cancelar",
  rejected: "Recusar",
}

/** Token de cor definido em globals.css. Mesma etapa, mesma cor nos quatro apps. */
export const COR_DA_SITUACAO: Record<SituacaoDoPedido, string> = {
  awaiting_payment: "var(--status-recebido)",
  received: "var(--status-recebido)",
  confirmed: "var(--status-confirmado)",
  preparing: "var(--status-preparo)",
  ready: "var(--status-pronto)",
  out_for_delivery: "var(--status-entrega)",
  delivered: "var(--status-entregue)",
  cancelled: "var(--status-cancelado)",
  rejected: "var(--status-cancelado)",
}

/** As colunas do Kanban do painel do restaurante, na ordem do fluxo. */
export const COLUNAS_DO_KANBAN: readonly SituacaoDoPedido[] = [
  "received",
  "confirmed",
  "preparing",
  "ready",
  "out_for_delivery",
  "delivered",
  "cancelled",
]

/** As etapas que o cliente ve na tela de acompanhamento. */
export const ETAPAS_DO_CLIENTE: readonly SituacaoDoPedido[] = [
  "received",
  "preparing",
  "out_for_delivery",
  "delivered",
]
