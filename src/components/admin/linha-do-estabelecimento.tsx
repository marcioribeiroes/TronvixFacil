"use client"

import { useState, useTransition } from "react"
import { Check, Pause, Play, Store, X } from "lucide-react"

import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import {
  decidirSobreEstabelecimento,
  mudarComissao,
} from "@/modules/admin/restaurantes"

type Estabelecimento = {
  id: string
  slug: string
  name: string
  description: string | null
  logo_url: string | null
  status: string
  is_open: boolean
  commission_bps: number
  city: string | null
  state: string | null
  district: string | null
  phone: string | null
  created_at: string
  approved_at: string | null
  rating_avg: number
  rating_count: number
}

const SITUACAO: Record<string, { rotulo: string; variante: "default" | "secondary" | "destructive" | "outline" }> = {
  pending: { rotulo: "Esperando aprovação", variante: "outline" },
  approved: { rotulo: "Aprovado", variante: "default" },
  suspended: { rotulo: "Suspenso", variante: "destructive" },
  rejected: { rotulo: "Recusado", variante: "destructive" },
}

/** Pontos base para o que se lê: 1250 -> "12,5%". */
function emPorcentagem(pontosBase: number) {
  return (pontosBase / 100).toLocaleString("pt-BR", {
    minimumFractionDigits: 0,
    maximumFractionDigits: 2,
  })
}

export function LinhaDoEstabelecimento({
  estabelecimento: r,
  destaque = false,
}: {
  estabelecimento: Estabelecimento
  destaque?: boolean
}) {
  const [enviando, iniciar] = useTransition()
  const [erro, setErro] = useState<string | null>(null)
  const [editandoComissao, setEditandoComissao] = useState(false)
  const [comissao, setComissao] = useState(emPorcentagem(r.commission_bps))

  const situacao = SITUACAO[r.status] ?? { rotulo: r.status, variante: "outline" as const }

  function decidir(novo: "approved" | "suspended" | "rejected") {
    setErro(null)
    iniciar(async () => {
      const resultado = await decidirSobreEstabelecimento(r.id, novo)
      if (!resultado.ok) setErro(resultado.erro)
    })
  }

  function salvarComissao() {
    setErro(null)
    // A pessoa digita "12,5"; o banco guarda 1250. A vírgula é como se escreve
    // porcentagem em português, e o formulário não deveria exigir o contrário.
    const pontosBase = Math.round(Number(comissao.replace(",", ".")) * 100)

    if (!Number.isFinite(pontosBase)) {
      setErro("Escreva a comissão em porcentagem, como 12,5")
      return
    }

    iniciar(async () => {
      const resultado = await mudarComissao(r.id, pontosBase)
      if (resultado.ok) setEditandoComissao(false)
      else setErro(resultado.erro)
    })
  }

  return (
    <article
      className={`rounded-xl border bg-card p-4 ${destaque ? "border-marca/40 bg-marca-suave/30" : ""}`}
    >
      <div className="flex flex-wrap items-start gap-4">
        <div className="flex size-12 shrink-0 items-center justify-center overflow-hidden rounded-lg bg-muted">
          {r.logo_url ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={r.logo_url} alt="" className="size-full object-cover" />
          ) : (
            <Store className="size-5 text-muted-foreground" aria-hidden="true" />
          )}
        </div>

        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-2">
            <h3 className="font-bold">{r.name}</h3>
            <Badge variant={situacao.variante}>{situacao.rotulo}</Badge>
            {r.status === "approved" ? (
              <Badge variant="secondary">{r.is_open ? "Aberto" : "Fechado"}</Badge>
            ) : null}
          </div>

          <p className="mt-0.5 text-sm text-muted-foreground">
            /{r.slug}
            {r.district || r.city ? (
              <> · {[r.district, r.city, r.state].filter(Boolean).join(", ")}</>
            ) : null}
            {r.rating_count > 0 ? <> · nota {r.rating_avg.toFixed(1)}</> : null}
          </p>

          {r.description ? (
            <p className="mt-1 line-clamp-1 text-sm text-muted-foreground">{r.description}</p>
          ) : null}
        </div>

        {/* Comissão: o número que a plataforma ganha. Fica editável na linha
            porque é a coisa que mais se ajusta na vida real — negociação por
            estabelecimento é regra, não exceção. */}
        <div className="flex items-center gap-2">
          {editandoComissao ? (
            <>
              <Input
                value={comissao}
                onChange={(e) => setComissao(e.target.value)}
                className="w-20 text-right"
                inputMode="decimal"
                aria-label="Comissão em porcentagem"
              />
              <span className="text-sm text-muted-foreground">%</span>
              <Button size="sm" onClick={salvarComissao} disabled={enviando}>
                Salvar
              </Button>
              <Button
                size="sm"
                variant="ghost"
                onClick={() => {
                  setComissao(emPorcentagem(r.commission_bps))
                  setEditandoComissao(false)
                  setErro(null)
                }}
              >
                Cancelar
              </Button>
            </>
          ) : (
            <button
              type="button"
              onClick={() => setEditandoComissao(true)}
              className="rounded-lg border px-3 py-1.5 text-right transition-colors hover:bg-muted"
            >
              <span className="block text-xs text-muted-foreground">Comissão</span>
              <span className="font-bold">{emPorcentagem(r.commission_bps)}%</span>
            </button>
          )}
        </div>

        <div className="flex flex-wrap gap-2">
          {r.status === "pending" ? (
            <>
              <Button size="sm" onClick={() => decidir("approved")} disabled={enviando}>
                <Check className="size-4" aria-hidden="true" />
                Aprovar
              </Button>
              <Button
                size="sm"
                variant="outline"
                onClick={() => decidir("rejected")}
                disabled={enviando}
              >
                <X className="size-4" aria-hidden="true" />
                Recusar
              </Button>
            </>
          ) : r.status === "approved" ? (
            <Button
              size="sm"
              variant="outline"
              onClick={() => decidir("suspended")}
              disabled={enviando}
            >
              <Pause className="size-4" aria-hidden="true" />
              Suspender
            </Button>
          ) : (
            <Button size="sm" onClick={() => decidir("approved")} disabled={enviando}>
              <Play className="size-4" aria-hidden="true" />
              Reativar
            </Button>
          )}
        </div>
      </div>

      {erro ? (
        <p role="alert" className="mt-3 text-sm font-medium text-destructive">
          {erro}
        </p>
      ) : null}
    </article>
  )
}
