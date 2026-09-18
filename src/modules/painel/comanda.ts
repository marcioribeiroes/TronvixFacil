import "server-only"

import { Comanda } from "@/lib/escpos"
import { formatarReais } from "@/lib/dinheiro"
import { formatarTelefone } from "@/lib/telefone"

/**
 * O pedido virando papel.
 *
 * A montagem fica aqui, longe da tela, porque ela e a comanda impressa pelo
 * driver contam a MESMA coisa: se o troco aparece num e nao no outro, a
 * diferenca vira briga no balcao.
 */

export type PedidoParaImprimir = {
  numero: number
  loja: string
  criadoEm: string
  tipo: "delivery" | "pickup" | "dine_in"
  mesa: string | null
  cliente: string
  telefone: string | null
  endereco: string | null
  bairro: string | null
  cidade: string | null
  observacao: string | null
  subtotalCentavos: number
  taxaCentavos: number
  descontoCentavos: number
  totalCentavos: number
  cupom: string | null
  formaDePagamento: string | null
  pagaNaHora: boolean
  trocoParaCentavos: number | null
  itens: {
    nome: string
    quantidade: number
    observacao: string | null
    totalCentavos: number
    adicionais: { nome: string; quantidade: number }[]
  }[]
}

const FORMA: Record<string, string> = {
  pix: "PIX",
  credit_card: "CREDITO",
  debit_card: "DEBITO",
  cash: "DINHEIRO",
  meal_voucher: "VALE-REFEICAO",
}

function quando(iso: string) {
  return new Date(iso).toLocaleString("pt-BR", {
    day: "2-digit",
    month: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  })
}

/**
 * Monta a fita ESC/POS.
 *
 * `colunas` e a largura em caracteres: 48 no papel de 80mm, 32 no de 58mm. E o
 * unico numero que muda entre um rolo e outro — o resto se ajusta sozinho.
 */
export function montarComanda(p: PedidoParaImprimir, colunas = 48): Uint8Array {
  const c = new Comanda(colunas)

  c.alinhar("centro")
  c.negrito(true).linha(p.loja.toUpperCase()).negrito(false)

  // O numero do pedido dobrado: e o que o balcao le de longe, com o papel
  // ainda na mao da impressora.
  c.tamanho(2).linha(`No ${p.numero}`).tamanho(1)

  const destino =
    p.tipo === "dine_in"
      ? (p.mesa ?? "MESA").toUpperCase()
      : p.tipo === "pickup"
        ? "RETIRADA NO BALCAO"
        : "ENTREGA"

  c.negrito(true).linha(destino).negrito(false)
  c.linha(quando(p.criadoEm))
  c.alinhar("esquerda")
  c.separador()

  c.negrito(true).linha(p.cliente).negrito(false)
  if (p.telefone) c.linha(formatarTelefone(p.telefone))
  if (p.tipo === "delivery" && p.endereco) {
    c.linha([p.endereco, p.bairro, p.cidade].filter(Boolean).join(" - "))
  }
  c.separador()

  for (const i of p.itens) {
    c.entre(`${i.quantidade}x ${i.nome}`, formatarReais(i.totalCentavos))
    for (const a of i.adicionais) {
      c.linha(`   + ${a.quantidade > 1 ? `${a.quantidade}x ` : ""}${a.nome}`)
    }
    // A observacao do item em negrito e maiuscula: e o "sem cebola" que vira
    // reclamacao se passar batido.
    if (i.observacao) c.negrito(true).linha(`   ** ${i.observacao.toUpperCase()}`).negrito(false)
  }

  c.separador()
  c.entre("Subtotal", formatarReais(p.subtotalCentavos))
  if (p.taxaCentavos > 0) c.entre("Entrega", formatarReais(p.taxaCentavos))
  if (p.descontoCentavos > 0) {
    c.entre(`Desconto ${p.cupom ?? ""}`.trim(), `-${formatarReais(p.descontoCentavos)}`)
  }
  c.negrito(true).tamanho(1)
  c.entre("TOTAL", formatarReais(p.totalCentavos))
  c.negrito(false)

  c.separador()
  if (p.pagaNaHora) {
    const onde =
      p.tipo === "dine_in" ? "NA MESA" : p.tipo === "pickup" ? "NO BALCAO" : "NA ENTREGA"
    c.negrito(true).linha(`RECEBER ${onde}`).negrito(false)
    c.linha(FORMA[p.formaDePagamento ?? ""] ?? p.formaDePagamento ?? "")
    if (p.formaDePagamento === "cash" && p.trocoParaCentavos) {
      c.negrito(true)
        .linha(
          `TROCO PARA ${formatarReais(p.trocoParaCentavos)} = ` +
            formatarReais(p.trocoParaCentavos - p.totalCentavos),
        )
        .negrito(false)
    }
  } else {
    c.negrito(true).linha(`PAGO PELO SITE - ${FORMA[p.formaDePagamento ?? ""] ?? ""}`).negrito(false)
  }

  if (p.observacao) {
    c.separador()
    c.negrito(true).linha(p.observacao.toUpperCase()).negrito(false)
  }

  c.alinhar("centro").linha().linha("Tronvix Facil")
  c.cortar()

  return c.bytes()
}
