"use client"

import { useState, useTransition } from "react"
import { Wallet } from "lucide-react"

import { Button } from "@/components/ui/button"
import { formatarReais, formatarValor, paraCentavos } from "@/lib/dinheiro"
import {
  FORMAS_DE_PAGAMENTO,
  ROTULO_DA_FORMA,
  formaDePagamento,
} from "@/modules/caixa/formas-de-pagamento"
import { receberParte } from "@/modules/painel/pedidos"

type Props = {
  pedidoId: string
  numero: number
  /** O que ainda falta receber deste pedido. */
  faltaCents: number
  /** O que ja entrou, em partes anteriores. */
  recebidoCents?: number
  formaPedida: string
}

/**
 * Receber o pagamento feito na entrega, no balcao ou na mesa.
 *
 * O valor ja vem com tudo o que falta, porque na maioria das vezes e isso
 * mesmo: um cliente, uma forma, a conta inteira. Para a mesa que divide, troca
 * o valor e recebe uma parte; o campo volta com o que sobrou, e a proxima
 * parte - ate a mesma, cinquenta e cinquenta - entra como outro recebimento.
 *
 * A forma ja vem marcada com o que o cliente escolheu no aplicativo, mas fica
 * trocavel: quem pediu em dinheiro e passou o cartao tem de entrar no caixa
 * como cartao.
 */
export function ReceberPagamento(props: Props) {
  // A chave remonta o formulario quando o que falta muda: o campo volta com o
  // novo restante, sem o valor da parte anterior ficar la.
  return <Formulario key={props.faltaCents} {...props} />
}

function Formulario({ pedidoId, numero, faltaCents, recebidoCents = 0, formaPedida }: Props) {
  const [enviando, iniciar] = useTransition()
  const [erro, setErro] = useState<string | null>(null)
  const [forma, setForma] = useState(() => formaDePagamento(formaPedida) ?? "cash")
  const [valor, setValor] = useState(() => formatarValor(faltaCents))

  const valorCents = paraCentavos(valor)
  const valido = valorCents !== null && valorCents > 0 && valorCents <= faltaCents
  const tudo = valorCents === faltaCents

  function receber() {
    if (!valido || valorCents === null) {
      setErro(
        valorCents !== null && valorCents > faltaCents
          ? `Falta receber só ${formatarReais(faltaCents)}.`
          : "Diga quanto o cliente pagou.",
      )
      return
    }
    setErro(null)
    iniciar(async () => {
      const r = await receberParte(pedidoId, forma, valorCents)
      if (!r.ok) setErro(r.erro)
    })
  }

  return (
    <div className="space-y-2">
      {recebidoCents > 0 ? (
        <p className="text-xs text-muted-foreground">
          Já recebido <strong className="text-foreground">{formatarReais(recebidoCents)}</strong>
          {" · "}falta <strong className="text-foreground">{formatarReais(faltaCents)}</strong>
        </p>
      ) : null}

      <div className="flex flex-wrap items-center gap-2">
        <Wallet className="size-4 shrink-0 text-muted-foreground" aria-hidden="true" />
        <label htmlFor={`forma-${pedidoId}`} className="sr-only">
          Como o cliente do pedido {numero} pagou
        </label>
        <select
          id={`forma-${pedidoId}`}
          value={forma}
          onChange={(e) => setForma(formaDePagamento(e.target.value) ?? "cash")}
          disabled={enviando}
          className="h-8 rounded-md border bg-background px-2 text-sm"
        >
          {FORMAS_DE_PAGAMENTO.map((f) => (
            <option key={f} value={f}>
              {ROTULO_DA_FORMA[f]}
            </option>
          ))}
        </select>

        <label htmlFor={`valor-${pedidoId}`} className="sr-only">
          Quanto foi recebido do pedido {numero}
        </label>
        <div className="flex h-8 items-center rounded-md border bg-background px-2 text-sm">
          <span className="text-muted-foreground">R$</span>
          <input
            id={`valor-${pedidoId}`}
            inputMode="decimal"
            value={valor}
            onChange={(e) => setValor(e.target.value)}
            onFocus={(e) => e.target.select()}
            disabled={enviando}
            className="w-20 bg-transparent pl-1 text-right tabular-nums outline-none"
          />
        </div>

        <Button size="sm" className="ml-auto" onClick={receber} disabled={enviando || !valido}>
          {tudo ? `Receber ${formatarReais(faltaCents)}` : "Receber parte"}
        </Button>
      </div>

      {/* O atalho da mesa que divide: metade da conta que falta. */}
      {tudo && faltaCents >= 2 ? (
        <button
          type="button"
          onClick={() => setValor(formatarValor(Math.floor(faltaCents / 2)))}
          disabled={enviando}
          className="text-xs font-medium text-muted-foreground underline underline-offset-2 hover:text-foreground"
        >
          Dividir: receber a metade
        </button>
      ) : null}

      {erro ? (
        <p role="alert" className="text-sm font-medium text-destructive">
          {erro}
        </p>
      ) : null}
    </div>
  )
}
