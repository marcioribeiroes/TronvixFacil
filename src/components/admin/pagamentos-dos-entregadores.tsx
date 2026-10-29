"use client"

import { useState, useTransition } from "react"
import { Check } from "lucide-react"

import { Button } from "@/components/ui/button"
import { formatarReais } from "@/lib/dinheiro"
import { confirmarPagamentoDoEntregador } from "@/modules/admin/plataforma"

/**
 * Os Pix de assinatura que os motoboys geraram e ainda nao foram confirmados.
 * Confirmar so quando o dinheiro aparecer no extrato - a referencia e o que
 * casa a linha daqui com a linha de la.
 */

export type PagamentoPendente = {
  id: string
  entregador: string
  valorCentavos: number
  referencia: string
  criadoEm: string
}

export function PagamentosDosEntregadores({ pagamentos }: { pagamentos: PagamentoPendente[] }) {
  const [enviando, iniciar] = useTransition()
  const [erro, setErro] = useState<string | null>(null)

  if (pagamentos.length === 0) return null

  return (
    <section>
      <h2 className="text-sm font-bold uppercase tracking-wide text-muted-foreground">
        Assinaturas para confirmar
      </h2>
      <ul className="mt-3 divide-y rounded-xl border bg-card">
        {pagamentos.map((p) => (
          <li key={p.id} className="flex flex-wrap items-center gap-3 p-3 text-sm">
            <span className="min-w-0 flex-1">
              <span className="block font-semibold">{p.entregador}</span>
              <span className="block text-xs text-muted-foreground">
                Referência {p.referencia} · gerado em{" "}
                {new Date(p.criadoEm).toLocaleString("pt-BR", {
                  dateStyle: "short",
                  timeStyle: "short",
                  timeZone: "America/Sao_Paulo",
                })}
              </span>
            </span>
            <span className="font-bold">{formatarReais(p.valorCentavos)}</span>
            <Button
              size="sm"
              disabled={enviando}
              onClick={() => {
                if (!window.confirm(`O Pix ${p.referencia} de ${p.entregador} caiu na conta?`)) return
                setErro(null)
                iniciar(async () => {
                  const r = await confirmarPagamentoDoEntregador(p.id)
                  if (!r.ok) setErro(r.erro)
                })
              }}
            >
              <Check className="size-4" aria-hidden="true" />
              Confirmar
            </Button>
          </li>
        ))}
      </ul>
      {erro ? <p className="mt-2 text-sm text-destructive">{erro}</p> : null}
    </section>
  )
}
