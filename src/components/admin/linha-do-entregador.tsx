"use client"

import { useState, useTransition } from "react"
import { Bike, Check, Pause, X } from "lucide-react"

import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { decidirSobreEntregador } from "@/modules/admin/plataforma"
import type { Enums } from "@/types/banco"

export type EntregadorNaLista = {
  id: string
  nome: string
  email: string | null
  telefone: string | null
  situacao: Enums<"courier_status">
  disponibilidade: Enums<"courier_availability">
  veiculo: string
  placa: string | null
  entregas: number
  nota: number
  avaliacoes: number
  loja: string | null
  desde: string
}

const SITUACAO: Record<
  string,
  { rotulo: string; variante: "default" | "secondary" | "destructive" | "outline" }
> = {
  pending: { rotulo: "Esperando aprovação", variante: "outline" },
  approved: { rotulo: "Aprovado", variante: "default" },
  suspended: { rotulo: "Fora", variante: "destructive" },
}

const VEICULO: Record<string, string> = {
  motorcycle: "Moto",
  bicycle: "Bicicleta",
  car: "Carro",
  foot: "A pé",
}

export function LinhaDoEntregador({
  entregador: c,
  destaque = false,
}: {
  entregador: EntregadorNaLista
  destaque?: boolean
}) {
  const [enviando, iniciar] = useTransition()
  const [erro, setErro] = useState<string | null>(null)

  const situacao = SITUACAO[c.situacao] ?? { rotulo: c.situacao, variante: "outline" as const }

  function decidir(novo: Enums<"courier_status">) {
    setErro(null)
    iniciar(async () => {
      const resultado = await decidirSobreEntregador(c.id, novo)
      if (!resultado.ok) setErro(resultado.erro)
    })
  }

  return (
    <div
      className={`rounded-xl border bg-card p-4 ${destaque ? "border-marca ring-1 ring-marca/20" : ""}`}
    >
      <div className="flex flex-wrap items-start gap-3">
        <span className="flex size-10 shrink-0 items-center justify-center rounded-full bg-muted">
          <Bike className="size-5 text-muted-foreground" aria-hidden="true" />
        </span>

        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-2">
            <p className="truncate font-semibold">{c.nome}</p>
            <Badge variant={situacao.variante}>{situacao.rotulo}</Badge>
            {c.loja ? (
              <Badge variant="secondary">entregador de {c.loja}</Badge>
            ) : (
              <Badge variant="outline">da plataforma</Badge>
            )}
          </div>
          <p className="mt-0.5 truncate text-xs text-muted-foreground">
            {[c.email, c.telefone].filter(Boolean).join(" · ") || "sem contato"}
          </p>
          <p className="mt-0.5 text-xs text-muted-foreground">
            {VEICULO[c.veiculo] ?? c.veiculo}
            {c.placa ? ` ${c.placa}` : ""} · {c.entregas}{" "}
            {c.entregas === 1 ? "entrega" : "entregas"}
            {c.avaliacoes > 0
              ? ` · ${c.nota.toFixed(1).replace(".", ",")} (${c.avaliacoes})`
              : ""}
          </p>
        </div>

        <div className="flex shrink-0 flex-wrap gap-2">
          {c.situacao === "pending" ? (
            <>
              <Button size="sm" disabled={enviando} onClick={() => decidir("approved")}>
                <Check className="size-4" aria-hidden="true" />
                Aprovar
              </Button>
              <Button
                size="sm"
                variant="outline"
                disabled={enviando}
                onClick={() => decidir("suspended")}
              >
                <X className="size-4" aria-hidden="true" />
                Recusar
              </Button>
            </>
          ) : c.situacao === "approved" ? (
            <Button
              size="sm"
              variant="outline"
              disabled={enviando}
              onClick={() => decidir("suspended")}
            >
              <Pause className="size-4" aria-hidden="true" />
              Suspender
            </Button>
          ) : (
            <Button size="sm" disabled={enviando} onClick={() => decidir("approved")}>
              <Check className="size-4" aria-hidden="true" />
              Liberar
            </Button>
          )}
        </div>
      </div>

      {erro ? <p className="mt-2 text-sm text-destructive">{erro}</p> : null}
    </div>
  )
}
