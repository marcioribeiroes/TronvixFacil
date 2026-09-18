import { describe, expect, it } from "vitest"

import {
  COLUNAS_DO_KANBAN,
  ROTULO_DA_SITUACAO,
  SITUACOES_DA_ENTREGA,
  SITUACOES_DO_PEDIDO,
  pedidoEmAndamento,
  pedidoEncerrado,
  proximasSituacoesDoPedido,
  transicaoDaEntregaPermitida,
  transicaoDoPedidoPermitida,
  type SituacaoDoPedido,
} from "./maquina-de-estados"

/**
 * Esta tabela e o contrato do fluxo de pedidos. Os mesmos casos existem em
 * supabase/tests/regras_do_pedido.sql: se as duas implementacoes divergirem,
 * um dos dois lados fica vermelho.
 */
const CAMINHO_FELIZ: Array<[SituacaoDoPedido, SituacaoDoPedido]> = [
  ["received", "confirmed"],
  ["confirmed", "preparing"],
  ["preparing", "ready"],
  ["ready", "out_for_delivery"],
  ["out_for_delivery", "delivered"],
]

describe("maquina de estados do pedido", () => {
  it("percorre o caminho feliz de ponta a ponta", () => {
    for (const [de, para] of CAMINHO_FELIZ) {
      expect(transicaoDoPedidoPermitida(de, para)).toBe(true)
    }
  })

  it("recusa pular etapas", () => {
    expect(transicaoDoPedidoPermitida("received", "delivered")).toBe(false)
    expect(transicaoDoPedidoPermitida("received", "ready")).toBe(false)
    expect(transicaoDoPedidoPermitida("confirmed", "out_for_delivery")).toBe(false)
  })

  it("recusa voltar atras", () => {
    expect(transicaoDoPedidoPermitida("delivered", "preparing")).toBe(false)
    expect(transicaoDoPedidoPermitida("ready", "preparing")).toBe(false)
    expect(transicaoDoPedidoPermitida("out_for_delivery", "ready")).toBe(false)
  })

  it("trata estados terminais como terminais", () => {
    for (const terminal of ["delivered", "cancelled", "rejected"] as const) {
      expect(pedidoEncerrado(terminal)).toBe(true)
      for (const destino of SITUACOES_DO_PEDIDO) {
        expect(transicaoDoPedidoPermitida(terminal, destino)).toBe(false)
      }
    }
  })

  it("permite cancelar de qualquer etapa ainda aberta", () => {
    for (const situacao of SITUACOES_DO_PEDIDO) {
      if (pedidoEncerrado(situacao)) continue
      expect(transicaoDoPedidoPermitida(situacao, "cancelled")).toBe(true)
    }
  })

  it("nao deixa um pedido de retirada sair para entrega", () => {
    expect(transicaoDoPedidoPermitida("ready", "out_for_delivery", "pickup")).toBe(false)
    expect(transicaoDoPedidoPermitida("ready", "out_for_delivery", "delivery")).toBe(true)
  })

  it("conclui a retirada direto de pronto", () => {
    expect(transicaoDoPedidoPermitida("ready", "delivered", "pickup")).toBe(true)
  })

  it("oferece a interface so o que o banco aceitaria", () => {
    // O painel desenha os botoes a partir daqui; tudo que aparecer tem de
    // passar na mesma checagem que a escrita vai enfrentar.
    for (const situacao of SITUACOES_DO_PEDIDO) {
      for (const tipo of ["delivery", "pickup", "dine_in"] as const) {
        for (const proxima of proximasSituacoesDoPedido(situacao, tipo)) {
          expect(transicaoDoPedidoPermitida(situacao, proxima, tipo)).toBe(true)
        }
      }
    }
  })

  it("nao oferece despacho na lista de um pedido de retirada", () => {
    expect(proximasSituacoesDoPedido("ready", "pickup")).not.toContain("out_for_delivery")
    expect(proximasSituacoesDoPedido("ready", "delivery")).toContain("out_for_delivery")
  })

  it("considera em andamento so o que ocupa cozinha ou rua", () => {
    expect(pedidoEmAndamento("preparing")).toBe(true)
    expect(pedidoEmAndamento("out_for_delivery")).toBe(true)
    expect(pedidoEmAndamento("delivered")).toBe(false)
    expect(pedidoEmAndamento("awaiting_payment")).toBe(false)
  })

  it("tem rotulo em portugues para toda situacao", () => {
    for (const situacao of SITUACOES_DO_PEDIDO) {
      expect(ROTULO_DA_SITUACAO[situacao]).toBeTruthy()
    }
  })

  it("nao esquece nenhuma coluna viva no Kanban", () => {
    // Uma situacao nova no enum sem coluna correspondente some da tela do
    // restaurante - o pedido existiria sem aparecer para ninguem.
    const foraDoKanban = SITUACOES_DO_PEDIDO.filter(
      (s) => s !== "awaiting_payment" && s !== "rejected" && !COLUNAS_DO_KANBAN.includes(s),
    )
    expect(foraDoKanban).toEqual([])
  })
})

describe("maquina de estados da entrega", () => {
  it("percorre a corrida inteira", () => {
    expect(transicaoDaEntregaPermitida("pending", "searching_courier")).toBe(true)
    expect(transicaoDaEntregaPermitida("searching_courier", "assigned")).toBe(true)
    expect(transicaoDaEntregaPermitida("assigned", "heading_to_restaurant")).toBe(true)
    expect(transicaoDaEntregaPermitida("heading_to_restaurant", "picked_up")).toBe(true)
    expect(transicaoDaEntregaPermitida("picked_up", "heading_to_customer")).toBe(true)
    expect(transicaoDaEntregaPermitida("heading_to_customer", "delivered")).toBe(true)
  })

  it("deixa o entregador desistir antes de retirar o pedido", () => {
    expect(transicaoDaEntregaPermitida("assigned", "searching_courier")).toBe(true)
    expect(transicaoDaEntregaPermitida("heading_to_restaurant", "searching_courier")).toBe(true)
  })

  it("nao deixa desistir depois de ja estar com a comida", () => {
    // Devolver a corrida a fila aqui deixaria o pedido na mochila de alguem
    // que nao e mais responsavel por ele.
    expect(transicaoDaEntregaPermitida("picked_up", "searching_courier")).toBe(false)
    expect(transicaoDaEntregaPermitida("heading_to_customer", "searching_courier")).toBe(false)
  })

  it("nao conclui entrega que nunca foi aceita", () => {
    expect(transicaoDaEntregaPermitida("searching_courier", "delivered")).toBe(false)
    expect(transicaoDaEntregaPermitida("pending", "picked_up")).toBe(false)
  })

  it("trata entregue e cancelada como terminais", () => {
    for (const destino of SITUACOES_DA_ENTREGA) {
      expect(transicaoDaEntregaPermitida("delivered", destino)).toBe(false)
      expect(transicaoDaEntregaPermitida("cancelled", destino)).toBe(false)
    }
  })
})

describe("pedido na mesa", () => {
  it("não sai para entrega: o garçom leva até a mesa", () => {
    expect(transicaoDoPedidoPermitida("ready", "out_for_delivery", "dine_in")).toBe(false)
  })

  it("de pronto vai direto a servido", () => {
    expect(transicaoDoPedidoPermitida("ready", "delivered", "dine_in")).toBe(true)
  })

  it("a interface não oferece a rua para quem está sentado", () => {
    expect(proximasSituacoesDoPedido("ready", "dine_in")).not.toContain("out_for_delivery")
    expect(proximasSituacoesDoPedido("ready", "dine_in")).toContain("delivered")
  })

  it("o caminho até a mesa é o mesmo da cozinha", () => {
    expect(transicaoDoPedidoPermitida("received", "confirmed", "dine_in")).toBe(true)
    expect(transicaoDoPedidoPermitida("confirmed", "preparing", "dine_in")).toBe(true)
    expect(transicaoDoPedidoPermitida("preparing", "ready", "dine_in")).toBe(true)
  })
})
