"use client"

import { useRouter } from "next/navigation"
import { useState, useTransition } from "react"
import { Check } from "lucide-react"

import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { formatarReais } from "@/lib/dinheiro"
import { gerarFechamento, marcarComissaoPaga } from "@/modules/admin/comissoes"

export type Extrato = {
  id: string
  loja: string
  pedidos: number
  vendas: number
  comissao: number
  pago: boolean
  pagoEm: string | null
  observacao: string | null
}

/**
 * O fechamento do mes: quanto cada loja deve de comissao, e quem ja pagou.
 *
 * "Gerar" refaz as contas do que esta em aberto — pode rodar de novo no meio
 * do mes, ou depois de um pedido entregue atrasado. O que ja foi pago fica.
 */
export function FechamentoDeComissoes({ mes, extratos }: { mes: string; extratos: Extrato[] }) {
  const router = useRouter()
  const [enviando, iniciar] = useTransition()
  const [erro, setErro] = useState<string | null>(null)

  const aReceber = extratos.filter((e) => !e.pago).reduce((s, e) => s + e.comissao, 0)
  const recebido = extratos.filter((e) => e.pago).reduce((s, e) => s + e.comissao, 0)

  function executar(acao: () => Promise<{ ok: boolean; erro?: string }>) {
    setErro(null)
    iniciar(async () => {
      const r = await acao()
      if (!r.ok) setErro(r.erro ?? "Não deu certo.")
      else router.refresh()
    })
  }

  return (
    <section className="space-y-4 rounded-xl border bg-card p-5">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h2 className="font-bold">Comissão a cobrar</h2>
          <p className="text-sm text-muted-foreground">
            O cliente paga direto à loja; a comissão dos pedidos entregues no mês é cobrada de
            cada loja e baixada aqui quando chega.
          </p>
        </div>
        <div className="flex items-end gap-2">
          <form className="flex items-end gap-2">
            <label className="text-sm">
              <span className="block text-xs text-muted-foreground">Mês</span>
              <input
                type="month"
                name="mes"
                defaultValue={mes}
                className="h-9 rounded-lg border bg-background px-2 text-sm"
              />
            </label>
            <Button type="submit" variant="outline" size="sm">
              Ver
            </Button>
          </form>
          <Button size="sm" disabled={enviando} onClick={() => executar(() => gerarFechamento(mes))}>
            {extratos.length > 0 ? "Atualizar fechamento" : "Gerar fechamento"}
          </Button>
        </div>
      </div>

      <dl className="flex flex-wrap gap-x-8 gap-y-1 text-sm">
        <div className="flex gap-2">
          <dt className="text-muted-foreground">A receber</dt>
          <dd className="font-bold">{formatarReais(aReceber)}</dd>
        </div>
        <div className="flex gap-2">
          <dt className="text-muted-foreground">Recebido</dt>
          <dd className="font-bold">{formatarReais(recebido)}</dd>
        </div>
      </dl>

      {extratos.length === 0 ? (
        <p className="rounded-lg border border-dashed p-6 text-center text-sm text-muted-foreground">
          Nenhum fechamento para este mês. &quot;Gerar fechamento&quot; soma os pedidos entregues.
        </p>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="border-b text-left text-xs uppercase text-muted-foreground">
              <tr>
                <th className="py-2 font-semibold">Loja</th>
                <th className="py-2 text-right font-semibold">Pedidos</th>
                <th className="py-2 text-right font-semibold">Vendas</th>
                <th className="py-2 text-right font-semibold">Comissão</th>
                <th className="py-2 text-right font-semibold">Situação</th>
              </tr>
            </thead>
            <tbody className="divide-y">
              {extratos.map((e) => (
                <tr key={e.id}>
                  <td className="py-2.5 font-semibold">{e.loja}</td>
                  <td className="py-2.5 text-right">{e.pedidos}</td>
                  <td className="py-2.5 text-right">{formatarReais(e.vendas)}</td>
                  <td className="py-2.5 text-right font-bold">{formatarReais(e.comissao)}</td>
                  <td className="py-2.5 text-right">
                    {e.pago ? (
                      <Badge variant="secondary" title={e.observacao ?? undefined}>
                        <Check className="size-3" aria-hidden="true" />
                        pago
                        {e.pagoEm ? ` em ${new Date(e.pagoEm).toLocaleDateString("pt-BR")}` : ""}
                      </Badge>
                    ) : e.comissao === 0 ? (
                      <span className="text-xs text-muted-foreground">nada a cobrar</span>
                    ) : (
                      <Button
                        size="sm"
                        variant="outline"
                        disabled={enviando}
                        onClick={() => {
                          const obs = window.prompt(
                            `Baixa da comissão de ${e.loja} (${formatarReais(e.comissao)}). Observação (opcional):`,
                            "Pix recebido",
                          )
                          if (obs === null) return
                          executar(() => marcarComissaoPaga(e.id, obs))
                        }}
                      >
                        Marcar como pago
                      </Button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {erro ? (
        <p role="alert" className="text-sm font-medium text-destructive">
          {erro}
        </p>
      ) : null}
    </section>
  )
}
