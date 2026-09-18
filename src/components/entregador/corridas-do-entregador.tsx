"use client"

import { useState, useTransition } from "react"
import { Bike, MapPin, Phone, Store } from "lucide-react"

import { Button } from "@/components/ui/button"
import { formatarReais } from "@/lib/dinheiro"
import { formatarTelefone, paraDiscagem } from "@/lib/telefone"
import {
  aceitarCorrida,
  avancarCorrida,
  desistirDaCorrida,
  mudarDisponibilidade,
} from "@/modules/entregador/corridas"
import type { SituacaoDaEntrega } from "@/modules/pedidos/maquina-de-estados"

/**
 * A tela do entregador na rua.
 *
 * Um botao grande de cada vez. Quem esta de capacete, com o celular numa mao
 * e a mochila na outra, nao escolhe entre seis acoes: ele confirma o proximo
 * passo. Por isso `proximoPasso` devolve UM destino, e a tela mostra so ele.
 */

export type CorridaNaTela = {
  id: string
  situacao: SituacaoDaEntrega
  ganhoCentavos: number
  numeroDoPedido: number
  totalDoPedidoCentavos: number
  cliente: string
  telefoneDoCliente: string | null
  enderecoDeEntrega: string | null
  bairro: string | null
  restaurante: string
  enderecoDoRestaurante: string | null
  telefoneDoRestaurante: string | null
  observacao: string | null
  recebeNaPorta: boolean
  criadaEm: string
}

/** Espelho de Corridas.proximoPasso, em celular/lib/dados/corridas.dart. */
function proximoPasso(atual: SituacaoDaEntrega): SituacaoDaEntrega | null {
  switch (atual) {
    case "assigned":
      return "heading_to_restaurant"
    case "heading_to_restaurant":
      return "picked_up"
    case "picked_up":
      return "heading_to_customer"
    case "heading_to_customer":
      return "delivered"
    default:
      return null
  }
}

const VERBO: Partial<Record<SituacaoDaEntrega, string>> = {
  heading_to_restaurant: "Estou a caminho da loja",
  picked_up: "Peguei o pedido",
  heading_to_customer: "Saí para o cliente",
  delivered: "Entreguei",
}

function Endereco({
  icone: Icone,
  titulo,
  linha,
  telefone,
}: {
  icone: typeof Store
  titulo: string
  linha: string | null
  telefone: string | null
}) {
  return (
    <div className="flex gap-3">
      <Icone className="mt-0.5 size-4 shrink-0 text-muted-foreground" aria-hidden="true" />
      <div className="min-w-0 flex-1">
        <p className="text-xs font-semibold uppercase text-muted-foreground">{titulo}</p>
        <p className="text-sm font-medium">{linha ?? "—"}</p>
        {telefone ? (
          <a
            href={`tel:${paraDiscagem(telefone)}`}
            className="mt-0.5 inline-flex items-center gap-1 text-sm font-semibold text-marca"
          >
            <Phone className="size-3.5" aria-hidden="true" />
            {formatarTelefone(telefone)}
          </a>
        ) : null}
      </div>
    </div>
  )
}

export function CorridasDoEntregador({
  minhaCorrida,
  fila,
  online,
  entreguesHoje,
  ganhoDeHoje,
}: {
  minhaCorrida: CorridaNaTela | null
  fila: CorridaNaTela[]
  online: boolean
  entreguesHoje: number
  ganhoDeHoje: number
}) {
  const [enviando, iniciar] = useTransition()
  const [erro, setErro] = useState<string | null>(null)

  function rodar(acao: () => Promise<{ ok: true } | { ok: false; erro: string }>) {
    setErro(null)
    iniciar(async () => {
      const resultado = await acao()
      if (!resultado.ok) setErro(resultado.erro)
    })
  }

  // Com corrida em curso, a fila some. Nao e economia de tela: e nao oferecer
  // uma segunda corrida a quem ja esta com comida esfriando na mochila.
  if (minhaCorrida) {
    const destino = proximoPasso(minhaCorrida.situacao)
    const podeDesistir =
      minhaCorrida.situacao === "assigned" ||
      minhaCorrida.situacao === "heading_to_restaurant"

    return (
      <div className="mx-auto max-w-lg space-y-4">
        <div className="rounded-xl border-2 border-marca bg-card p-4">
          <div className="flex items-center justify-between">
            <p className="text-xs font-semibold uppercase text-muted-foreground">
              Pedido #{minhaCorrida.numeroDoPedido}
            </p>
            <p className="text-lg font-bold text-marca">
              {formatarReais(minhaCorrida.ganhoCentavos)}
            </p>
          </div>

          <div className="mt-4 space-y-4">
            <Endereco
              icone={Store}
              titulo="Retirar em"
              linha={`${minhaCorrida.restaurante} — ${minhaCorrida.enderecoDoRestaurante ?? "—"}`}
              telefone={minhaCorrida.telefoneDoRestaurante}
            />
            <Endereco
              icone={MapPin}
              titulo="Entregar a"
              linha={`${minhaCorrida.cliente} — ${minhaCorrida.enderecoDeEntrega ?? "—"}${
                minhaCorrida.bairro ? `, ${minhaCorrida.bairro}` : ""
              }`}
              telefone={minhaCorrida.telefoneDoCliente}
            />
          </div>

          {minhaCorrida.observacao ? (
            <p className="mt-4 rounded-lg bg-muted p-3 text-sm">{minhaCorrida.observacao}</p>
          ) : null}

          {minhaCorrida.recebeNaPorta ? (
            <p className="mt-4 rounded-lg border border-amber-300 bg-amber-50 p-3 text-sm font-semibold dark:border-amber-900 dark:bg-amber-950/30">
              Receber na porta: {formatarReais(minhaCorrida.totalDoPedidoCentavos)}
            </p>
          ) : (
            <p className="mt-4 text-sm text-muted-foreground">Pedido já pago pelo aplicativo.</p>
          )}
        </div>

        {erro ? <p className="text-sm text-destructive">{erro}</p> : null}

        {destino ? (
          <Button
            size="lg"
            className="h-14 w-full text-base"
            disabled={enviando}
            onClick={() => rodar(() => avancarCorrida(minhaCorrida.id, destino))}
          >
            {VERBO[destino] ?? "Avançar"}
          </Button>
        ) : null}

        {podeDesistir ? (
          <Button
            variant="outline"
            className="w-full"
            disabled={enviando}
            onClick={() => rodar(() => desistirDaCorrida(minhaCorrida.id))}
          >
            Devolver à fila
          </Button>
        ) : null}
      </div>
    )
  }

  return (
    <div className="mx-auto max-w-lg space-y-4">
      <div className="flex items-center gap-3 rounded-xl border bg-card p-4">
        <span
          className={`size-3 shrink-0 rounded-full ${online ? "bg-emerald-500" : "bg-muted-foreground"}`}
          aria-hidden="true"
        />
        <span className="min-w-0 flex-1">
          <span className="block font-semibold">{online ? "Você está online" : "Offline"}</span>
          <span className="block text-xs text-muted-foreground">
            {entreguesHoje} {entreguesHoje === 1 ? "entrega" : "entregas"} hoje ·{" "}
            {formatarReais(ganhoDeHoje)}
          </span>
        </span>
        <Button
          variant={online ? "outline" : "default"}
          size="sm"
          disabled={enviando}
          onClick={() => rodar(() => mudarDisponibilidade(!online))}
        >
          {online ? "Sair" : "Ficar online"}
        </Button>
      </div>

      {erro ? <p className="text-sm text-destructive">{erro}</p> : null}

      <h2 className="text-sm font-bold uppercase tracking-wide text-muted-foreground">
        Corridas disponíveis
      </h2>

      {fila.length === 0 ? (
        <div className="rounded-xl border border-dashed p-10 text-center">
          <Bike className="mx-auto size-8 text-muted-foreground" aria-hidden="true" />
          <p className="mt-3 font-semibold">Nenhuma corrida agora</p>
          <p className="mt-1 text-sm text-muted-foreground">
            Assim que uma loja despachar um pedido, ele aparece aqui.
          </p>
        </div>
      ) : (
        <ul className="space-y-3">
          {fila.map((c) => (
            <li key={c.id} className="rounded-xl border bg-card p-4">
              <div className="flex items-start justify-between gap-3">
                <div className="min-w-0">
                  <p className="truncate font-semibold">{c.restaurante}</p>
                  <p className="truncate text-xs text-muted-foreground">
                    {c.enderecoDoRestaurante ?? "—"}
                  </p>
                </div>
                <p className="shrink-0 text-lg font-bold text-marca">
                  {formatarReais(c.ganhoCentavos)}
                </p>
              </div>

              <p className="mt-2 flex items-start gap-2 text-sm">
                <MapPin className="mt-0.5 size-4 shrink-0 text-muted-foreground" aria-hidden="true" />
                <span className="min-w-0">
                  {c.enderecoDeEntrega ?? "—"}
                  {c.bairro ? `, ${c.bairro}` : ""}
                </span>
              </p>

              {c.recebeNaPorta ? (
                <p className="mt-2 text-xs font-semibold text-amber-700 dark:text-amber-400">
                  Receber {formatarReais(c.totalDoPedidoCentavos)} na porta
                </p>
              ) : null}

              <Button
                className="mt-3 h-12 w-full"
                disabled={enviando}
                onClick={() => rodar(() => aceitarCorrida(c.id))}
              >
                Aceitar corrida
              </Button>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}
