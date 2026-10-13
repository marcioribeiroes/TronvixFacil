import type { Metadata } from "next"
import Link from "next/link"
import { FileText } from "lucide-react"

import { Button } from "@/components/ui/button"
import { CaixaAoVivo } from "@/components/painel/caixa-ao-vivo"
import {
  CancelarLancamento,
  RegistrarFundo,
  RegistrarSangria,
} from "@/components/painel/lancamentos-do-caixa"
import { ReceberPagamento } from "@/components/painel/receber-pagamento"
import { formatarReais } from "@/lib/dinheiro"
import { exigirVinculo } from "@/modules/auth/sessao"
import {
  FORMAS_DE_PAGAMENTO,
  ROTULO_DA_FORMA,
  formaDePagamento,
} from "@/modules/caixa/formas-de-pagamento"
import {
  ROTULO_DO_LANCAMENTO,
  hora,
  lerMovimento,
  resumir,
} from "@/modules/caixa/movimento"
import { ROTULO_DO_TIPO, type TipoDeEntrega } from "@/modules/pedidos/maquina-de-estados"

export const metadata: Metadata = { title: "Caixa" }

function destino(tipo: string, mesa: string | null) {
  return tipo === "dine_in"
    ? (mesa ?? "Mesa")
    : (ROTULO_DO_TIPO[tipo as TipoDeEntrega] ?? tipo)
}

/** Uma linha do movimento: fundo, recebimento ou sangria, na ordem do relógio. */
type Linha = {
  chave: string
  quando: string
  descricao: string
  detalhe: string
  /** Positivo entra na gaveta ou na conta; negativo sai. */
  valor: number
  cancelado: boolean
  lancamentoId?: string
}

/**
 * O caixa do dia.
 *
 * Em cima, o número que importa na conferência: quanto dinheiro tem de estar na
 * gaveta. Embaixo, de onde ele veio — fundo, cada recebimento, cada sangria —,
 * para que a diferença, quando houver, se ache olhando a lista.
 */
export default async function PaginaDoCaixa() {
  const { vinculo } = await exigirVinculo()
  const ehGestao = vinculo.cargo === "owner" || vinculo.cargo === "manager"

  const movimento = await lerMovimento(vinculo.restauranteId)
  const resumo = resumir(movimento)
  const fuso = movimento.fuso

  const fundo = movimento.lancamentos.find((l) => l.tipo === "opening_float" && !l.cancelado_em)

  const linhas: Linha[] = [
    ...movimento.lancamentos.map((l) => ({
      chave: l.id,
      quando: l.feito_em,
      descricao: ROTULO_DO_LANCAMENTO[l.tipo],
      detalhe: [l.observacao, l.feito_por].filter(Boolean).join(" · "),
      valor: l.tipo === "withdrawal" ? -l.valor_cents : l.valor_cents,
      cancelado: Boolean(l.cancelado_em),
      lancamentoId: l.id,
    })),
    ...movimento.recebimentos.map((r) => {
      const forma = formaDePagamento(r.forma)
      return {
        chave: `${r.pedido_id}-recebido`,
        quando: r.pago_em,
        descricao: `Pedido nº ${r.numero}`,
        detalhe: `${r.cliente} · ${forma ? ROTULO_DA_FORMA[forma] : r.forma}${
          r.momento === "online" ? " pelo site" : ""
        }`,
        valor: r.valor_cents,
        cancelado: false,
      }
    }),
  ].sort((a, b) => b.quando.localeCompare(a.quando))

  return (
    <div className="space-y-6">
      <CaixaAoVivo restauranteId={vinculo.restauranteId} />

      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold tracking-tight">Caixa</h1>
          <p className="mt-1 text-sm text-muted-foreground">
            Fundo, recebimentos e sangrias de hoje. O que é recebido na fila aparece aqui sozinho.
          </p>
        </div>
        <Button variant="outline" render={<Link href="/painel/caixa/relatorio" />}>
          <FileText className="size-4" aria-hidden="true" />
          Relatório do caixa
        </Button>
      </div>

      <dl className="grid grid-cols-2 gap-3 sm:grid-cols-5">
        <div className="col-span-2 rounded-xl border bg-marca-suave p-4 sm:col-span-1">
          <dt className="text-xs font-semibold uppercase text-marca-forte">Dinheiro na gaveta</dt>
          <dd className="text-2xl font-bold">{formatarReais(movimento.dinheiro_na_gaveta_cents)}</dd>
        </div>
        <div className="rounded-xl border bg-muted/40 p-4">
          <dt className="text-xs font-semibold uppercase text-muted-foreground">Fundo</dt>
          <dd className="text-lg font-bold">{formatarReais(resumo.fundo)}</dd>
        </div>
        <div className="rounded-xl border bg-muted/40 p-4">
          <dt className="text-xs font-semibold uppercase text-muted-foreground">Recebido</dt>
          <dd className="text-lg font-bold">{formatarReais(resumo.recebido)}</dd>
        </div>
        <div className="rounded-xl border bg-muted/40 p-4">
          <dt className="text-xs font-semibold uppercase text-muted-foreground">Sangrias</dt>
          <dd className="text-lg font-bold">{formatarReais(resumo.sangrias)}</dd>
        </div>
        <div className="rounded-xl border bg-muted/40 p-4">
          <dt className="text-xs font-semibold uppercase text-muted-foreground">A receber</dt>
          <dd className="text-lg font-bold">{formatarReais(resumo.aReceber)}</dd>
        </div>
      </dl>

      <dl className="flex flex-wrap gap-x-6 gap-y-2 rounded-xl border px-4 py-3 text-sm">
        {FORMAS_DE_PAGAMENTO.map((f) => (
          <div key={f} className="flex gap-2">
            <dt className="text-muted-foreground">{ROTULO_DA_FORMA[f]}</dt>
            <dd className="font-semibold">{formatarReais(resumo.porForma[f])}</dd>
          </div>
        ))}
      </dl>

      <div className="grid gap-4 lg:grid-cols-2">
        {fundo ? (
          <div className="rounded-xl border bg-card p-4">
            <h2 className="font-semibold">Fundo de caixa</h2>
            <p className="mt-1 text-sm text-muted-foreground">
              <strong className="text-foreground">{formatarReais(fundo.valor_cents)}</strong>{" "}
              registrado às {hora(fundo.feito_em, fuso)}
              {fundo.feito_por ? ` por ${fundo.feito_por}` : ""}.
            </p>
          </div>
        ) : (
          <RegistrarFundo />
        )}
        <RegistrarSangria />
      </div>

      <div className="grid gap-6 lg:grid-cols-2">
        <section className="space-y-3">
          <h2 className="text-sm font-bold uppercase tracking-wide">
            A receber <span className="text-muted-foreground">· {movimento.a_receber.length}</span>
          </h2>
          {movimento.a_receber.length === 0 ? (
            <p className="rounded-xl border border-dashed p-6 text-center text-sm text-muted-foreground">
              Nada pendente. Todo pedido de hoje já foi recebido.
            </p>
          ) : (
            <ul className="space-y-2">
              {movimento.a_receber.map((r) => (
                <li key={r.pedido_id} className="space-y-2 rounded-xl border bg-card p-3">
                  <p className="flex flex-wrap items-baseline gap-x-2 text-sm">
                    <span className="font-bold">nº {r.numero}</span>
                    <span className="flex-1 truncate">{r.cliente}</span>
                    <span className="text-muted-foreground">{destino(r.tipo_de_entrega, r.mesa)}</span>
                  </p>
                  <ReceberPagamento
                    pedidoId={r.pedido_id}
                    numero={r.numero}
                    totalCents={r.valor_cents}
                    formaPedida={r.forma}
                  />
                </li>
              ))}
            </ul>
          )}
        </section>

        <section className="space-y-3">
          <h2 className="text-sm font-bold uppercase tracking-wide">
            Movimento <span className="text-muted-foreground">· {linhas.length}</span>
          </h2>
          {linhas.length === 0 ? (
            <p className="rounded-xl border border-dashed p-6 text-center text-sm text-muted-foreground">
              Nada lançado hoje. Comece pelo fundo de caixa.
            </p>
          ) : (
            <ul className="divide-y rounded-xl border bg-card">
              {linhas.map((l) => (
                <li
                  key={l.chave}
                  className={`flex flex-wrap items-center gap-x-3 px-3 py-2.5 text-sm ${
                    l.cancelado ? "text-muted-foreground line-through" : ""
                  }`}
                >
                  <span className="w-12 text-muted-foreground">{hora(l.quando, fuso)}</span>
                  <span className="min-w-0 flex-1">
                    <span className="font-semibold">{l.descricao}</span>
                    {l.detalhe ? (
                      <span className="block truncate text-xs text-muted-foreground">{l.detalhe}</span>
                    ) : null}
                  </span>
                  <span
                    className={`font-semibold tabular-nums ${
                      l.valor < 0 && !l.cancelado ? "text-destructive" : ""
                    }`}
                  >
                    {l.valor < 0 ? "− " : ""}
                    {formatarReais(Math.abs(l.valor))}
                  </span>
                  {ehGestao && l.lancamentoId && !l.cancelado ? (
                    <CancelarLancamento
                      id={l.lancamentoId}
                      descricao={`${l.descricao.toLowerCase()} de ${formatarReais(Math.abs(l.valor))}`}
                    />
                  ) : null}
                </li>
              ))}
            </ul>
          )}
        </section>
      </div>
    </div>
  )
}
