"use client"

import { useState, useTransition } from "react"
import { Bike } from "lucide-react"

import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { formatarReais } from "@/lib/dinheiro"
import {
  aceitarEntregadorDaPlataforma,
  decidirSobreEntregador,
} from "@/modules/painel/configuracoes"

type Entregador = {
  id: string
  nome: string
  telefone: string | null
  situacao: string
  disponibilidade: string
  veiculo: string
  entregas: number
}

type Corrida = {
  id: string
  situacao: string
  semEntregador: boolean
  numeroDoPedido: number
  cliente: string
  bairro: string | null
  taxaCentavos: number
}

const VEICULO: Record<string, string> = {
  motorcycle: "Moto",
  bicycle: "Bicicleta",
  car: "Carro",
  foot: "A pé",
}

const DISPONIBILIDADE: Record<string, string> = {
  offline: "Fora do ar",
  online: "Disponível",
  on_delivery: "Em entrega",
}

export function EquipeDeEntrega({
  aceitaDeFora,
  entregadores,
  corridas,
}: {
  aceitaDeFora: boolean
  entregadores: Entregador[]
  corridas: Corrida[]
}) {
  const [enviando, iniciar] = useTransition()
  const [erro, setErro] = useState<string | null>(null)

  const pendentes = entregadores.filter((e) => e.situacao === "pending")
  const resto = entregadores.filter((e) => e.situacao !== "pending")

  return (
    <div className="space-y-8">
      {erro ? (
        <p role="alert" className="text-sm font-medium text-destructive">
          {erro}
        </p>
      ) : null}

      <section>
        <h2 className="text-sm font-bold uppercase tracking-wide text-muted-foreground">
          Corridas em andamento
        </h2>
        {corridas.length === 0 ? (
          <p className="mt-2 rounded-xl border border-dashed p-6 text-center text-sm text-muted-foreground">
            Nenhuma corrida agora. Elas aparecem quando você despacha um pedido.
          </p>
        ) : (
          <ul className="mt-2 divide-y rounded-xl border bg-card">
            {corridas.map((c) => (
              <li key={c.id} className="flex flex-wrap items-center gap-3 p-4 text-sm">
                <span className="font-bold">nº {c.numeroDoPedido}</span>
                <Badge variant={c.semEntregador ? "destructive" : "secondary"}>
                  {c.situacao}
                </Badge>
                <span className="flex-1 text-muted-foreground">
                  {c.cliente}
                  {c.bairro ? ` · ${c.bairro}` : ""}
                </span>
                <span className="font-semibold">{formatarReais(c.taxaCentavos)}</span>
              </li>
            ))}
          </ul>
        )}
      </section>

      {pendentes.length > 0 ? (
        <section>
          <div className="flex items-center gap-2">
            <h2 className="text-sm font-bold uppercase tracking-wide text-muted-foreground">
              Esperando sua aprovação
            </h2>
            <Badge variant="destructive">{pendentes.length}</Badge>
          </div>
          <ul className="mt-2 divide-y rounded-xl border border-marca/40 bg-marca-suave/30">
            {pendentes.map((e) => (
              <Linha key={e.id} entregador={e} enviando={enviando} aoDecidir={(s) =>
                iniciar(async () => {
                  const r = await decidirSobreEntregador(e.id, s)
                  if (!r.ok) setErro(r.erro)
                })
              } />
            ))}
          </ul>
        </section>
      ) : null}

      <section>
        <h2 className="text-sm font-bold uppercase tracking-wide text-muted-foreground">
          Sua equipe
        </h2>
        {resto.length === 0 ? (
          <p className="mt-2 rounded-xl border border-dashed p-6 text-center text-sm text-muted-foreground">
            Ninguém aprovado ainda. Quem quiser entregar para você se cadastra pelo
            aplicativo e aparece aqui.
          </p>
        ) : (
          <ul className="mt-2 divide-y rounded-xl border bg-card">
            {resto.map((e) => (
              <Linha key={e.id} entregador={e} enviando={enviando} aoDecidir={(s) =>
                iniciar(async () => {
                  const r = await decidirSobreEntregador(e.id, s)
                  if (!r.ok) setErro(r.erro)
                })
              } />
            ))}
          </ul>
        )}
      </section>

      <label className="flex cursor-pointer items-start gap-3 rounded-xl border bg-card p-4">
        <input
          type="checkbox"
          checked={aceitaDeFora}
          disabled={enviando}
          className="mt-0.5 size-4 accent-marca"
          onChange={(e) =>
            iniciar(async () => {
              const r = await aceitarEntregadorDaPlataforma(e.target.checked)
              if (!r.ok) setErro(r.erro)
            })
          }
        />
        <span>
          <span className="font-semibold">Aceitar entregador de fora</span>
          <span className="mt-0.5 block text-sm text-muted-foreground">
            Desligado, suas corridas só aparecem para a sua equipe. Ligado,
            entregadores autônomos da plataforma também podem pegá-las.
          </span>
        </span>
      </label>
    </div>
  )
}

function Linha({
  entregador: e,
  enviando,
  aoDecidir,
}: {
  entregador: Entregador
  enviando: boolean
  aoDecidir: (situacao: "approved" | "suspended") => void
}) {
  return (
    <li className="flex flex-wrap items-center gap-3 p-4">
      <Bike className="size-5 shrink-0 text-muted-foreground" aria-hidden="true" />

      <div className="min-w-0 flex-1">
        <p className="font-semibold">{e.nome}</p>
        <p className="text-sm text-muted-foreground">
          {VEICULO[e.veiculo] ?? e.veiculo} · {e.entregas} entregas
          {e.telefone ? ` · ${e.telefone}` : ""}
        </p>
      </div>

      <Badge
        variant={
          e.situacao === "approved"
            ? "secondary"
            : e.situacao === "suspended"
              ? "destructive"
              : "outline"
        }
      >
        {e.situacao === "approved"
          ? DISPONIBILIDADE[e.disponibilidade]
          : e.situacao === "suspended"
            ? "Suspenso"
            : "Pendente"}
      </Badge>

      {e.situacao === "approved" ? (
        <Button size="sm" variant="outline" disabled={enviando} onClick={() => aoDecidir("suspended")}>
          Suspender
        </Button>
      ) : (
        <Button size="sm" disabled={enviando} onClick={() => aoDecidir("approved")}>
          {e.situacao === "pending" ? "Aprovar" : "Reativar"}
        </Button>
      )}
    </li>
  )
}
