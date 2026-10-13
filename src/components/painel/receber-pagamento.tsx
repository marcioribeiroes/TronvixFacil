"use client"

import { useState, useTransition } from "react"
import { Wallet } from "lucide-react"

import { Button } from "@/components/ui/button"
import { formatarReais } from "@/lib/dinheiro"
import {
  FORMAS_DE_PAGAMENTO,
  ROTULO_DA_FORMA,
  formaDePagamento,
} from "@/modules/caixa/formas-de-pagamento"
import { receberPagamento } from "@/modules/painel/pedidos"

/**
 * Receber o pagamento feito na entrega, no balcao ou na mesa.
 *
 * A forma ja vem marcada com o que o cliente escolheu no aplicativo, porque na
 * maioria das vezes e isso mesmo. Mas fica trocavel ali do lado do botao: quem
 * pediu em dinheiro e passou o cartao tem de entrar no caixa como cartao.
 */
export function ReceberPagamento({
  pedidoId,
  numero,
  totalCents,
  formaPedida,
}: {
  pedidoId: string
  numero: number
  totalCents: number
  formaPedida: string
}) {
  const [enviando, iniciar] = useTransition()
  const [erro, setErro] = useState<string | null>(null)
  const [forma, setForma] = useState(() => formaDePagamento(formaPedida) ?? "cash")

  function receber() {
    setErro(null)
    iniciar(async () => {
      const r = await receberPagamento(pedidoId, forma)
      if (!r.ok) setErro(r.erro)
    })
  }

  return (
    <div className="space-y-2">
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
        <Button size="sm" className="ml-auto" onClick={receber} disabled={enviando}>
          Receber {formatarReais(totalCents)}
        </Button>
      </div>
      {erro ? (
        <p role="alert" className="text-sm font-medium text-destructive">
          {erro}
        </p>
      ) : null}
    </div>
  )
}
