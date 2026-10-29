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
  /** So o autonomo tem: o cadastro com documento que a plataforma analisa. */
  cadastro: {
    cpf: string | null
    idade: number | null
    cidade: string | null
    pix: string | null
    modelo: string | null
    cor: string | null
    motivo: string | null
    documentos: { rotulo: string; url: string }[]
  } | null
}

const SITUACAO: Record<
  string,
  { rotulo: string; variante: "default" | "secondary" | "destructive" | "outline" }
> = {
  pending: { rotulo: "Esperando aprovação", variante: "outline" },
  approved: { rotulo: "Aprovado", variante: "default" },
  suspended: { rotulo: "Suspenso", variante: "destructive" },
  rejected: { rotulo: "Recusado", variante: "destructive" },
}

function cpfFormatado(cpf: string) {
  return cpf.replace(/(\d{3})(\d{3})(\d{3})(\d{2})/, "$1.$2.$3-$4")
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
    let motivo: string | undefined
    if (novo === "rejected" || novo === "suspended") {
      const resposta = window.prompt(
        novo === "rejected"
          ? "Por que o cadastro foi recusado? O entregador vai ler e poderá corrigir."
          : "Por que suspender? O entregador vai ler.",
      )
      if (resposta === null) return
      motivo = resposta
    }
    setErro(null)
    iniciar(async () => {
      const resultado = await decidirSobreEntregador(c.id, novo, motivo)
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
                onClick={() => decidir(c.loja ? "suspended" : "rejected")}
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

      {c.cadastro ? (
        <div className="mt-4 space-y-3 border-t pt-4">
          <dl className="grid gap-x-6 gap-y-1 text-sm sm:grid-cols-2 lg:grid-cols-3">
            {(
              [
                ["CPF", c.cadastro.cpf ? cpfFormatado(c.cadastro.cpf) : null],
                ["Idade", c.cadastro.idade !== null ? `${c.cadastro.idade} anos` : null],
                ["Cidade", c.cadastro.cidade],
                ["Veículo", [c.cadastro.modelo, c.cadastro.cor].filter(Boolean).join(" · ") || null],
                ["Chave Pix", c.cadastro.pix],
              ] as const
            ).map(([rotulo, valor]) => (
              <div key={rotulo} className="flex gap-2">
                <dt className="text-muted-foreground">{rotulo}</dt>
                <dd className="font-medium">{valor ?? "—"}</dd>
              </div>
            ))}
          </dl>
          {c.cadastro.motivo ? (
            <p className="text-sm">
              <span className="text-muted-foreground">Motivo informado: </span>
              {c.cadastro.motivo}
            </p>
          ) : null}
          {c.cadastro.documentos.length > 0 ? (
            <ul className="flex flex-wrap gap-3">
              {c.cadastro.documentos.map((d) => (
                <li key={d.rotulo}>
                  <a href={d.url} target="_blank" rel="noopener noreferrer" className="block">
                    {/* URL assinada de validade curta: o documento e privado. */}
                    {/* eslint-disable-next-line @next/next/no-img-element */}
                    <img
                      src={d.url}
                      alt={d.rotulo}
                      className="h-32 w-44 rounded-lg border object-cover"
                    />
                    <span className="mt-1 block text-xs text-muted-foreground">{d.rotulo}</span>
                  </a>
                </li>
              ))}
            </ul>
          ) : null}
        </div>
      ) : null}

      {erro ? <p className="mt-2 text-sm text-destructive">{erro}</p> : null}
    </div>
  )
}
