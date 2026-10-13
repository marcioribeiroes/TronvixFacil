import type { Metadata } from "next"
import Link from "next/link"
import { ArrowLeft } from "lucide-react"

import { Button } from "@/components/ui/button"
import { ImprimirPagina } from "@/components/painel/imprimir-pagina"
import { formatarReais } from "@/lib/dinheiro"
import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirVinculo } from "@/modules/auth/sessao"
import {
  FORMAS_DE_PAGAMENTO,
  ROTULO_DA_FORMA,
  formaDePagamento,
} from "@/modules/caixa/formas-de-pagamento"
import { ROTULO_DO_LANCAMENTO, hora, lerMovimento, resumir } from "@/modules/caixa/movimento"

export const metadata: Metadata = { title: "Relatório do caixa" }

const DIA = /^\d{4}-\d{2}-\d{2}$/

/** "2026-10-13" -> "13/10/2026", sem passar por Date e sem fuso no caminho. */
function dataPorExtenso(dia: string) {
  const [ano, mes, d] = dia.split("-")
  return `${d}/${mes}/${ano}`
}

/**
 * O relatório de movimento do caixa de um dia.
 *
 * É o papel da conferência: abre com a conta da gaveta (fundo + dinheiro
 * recebido − sangrias), segue com o total de cada forma de pagamento, e termina
 * com cada lançamento, um por linha, com hora e autor. O cancelado aparece
 * riscado — sumir com ele é o que faz o caixa deixar de ser confiável.
 *
 * Imprime limpo: o menu e os controles somem no papel.
 */
export default async function RelatorioDoCaixa({
  searchParams,
}: PageProps<"/painel/caixa/relatorio">) {
  const { vinculo } = await exigirVinculo()
  const parametros = await searchParams
  const pedido = typeof parametros.dia === "string" && DIA.test(parametros.dia) ? parametros.dia : undefined

  const supabase = await criarClienteDoServidor()
  const [movimento, { data: loja }] = await Promise.all([
    lerMovimento(vinculo.restauranteId, pedido),
    supabase.from("restaurants").select("name").eq("id", vinculo.restauranteId).single(),
  ])

  const resumo = resumir(movimento)
  const fuso = movimento.fuso
  const dinheiroRecebido = resumo.porForma.cash
  const geradoEm = new Date().toLocaleString("pt-BR", {
    timeZone: fuso,
    dateStyle: "short",
    timeStyle: "short",
  })

  return (
    <div className="mx-auto max-w-3xl space-y-6 print:max-w-none print:space-y-4 print:text-[11pt]">
      <div className="flex flex-wrap items-end justify-between gap-3 print:hidden">
        <Button variant="ghost" render={<Link href="/painel/caixa" />}>
          <ArrowLeft className="size-4" aria-hidden="true" />
          Voltar ao caixa
        </Button>
        <div className="flex flex-wrap items-end gap-2">
          <form className="flex items-end gap-2">
            <label className="text-sm">
              <span className="block text-xs text-muted-foreground">Dia</span>
              <input
                type="date"
                name="dia"
                defaultValue={movimento.dia}
                className="h-9 rounded-lg border bg-background px-2 text-sm"
              />
            </label>
            <Button type="submit" variant="outline">
              Ver
            </Button>
          </form>
          <ImprimirPagina />
        </div>
      </div>

      <header className="border-b pb-4">
        <p className="text-sm text-muted-foreground">{loja?.name}</p>
        <h1 className="text-2xl font-bold tracking-tight">Movimento do caixa</h1>
        <p className="mt-1 text-sm">
          {dataPorExtenso(movimento.dia)}
          {movimento.hoje ? " · caixa de hoje, ainda em movimento" : ""}
          <span className="text-muted-foreground"> · gerado em {geradoEm}</span>
        </p>
      </header>

      <section className="space-y-2">
        <h2 className="text-sm font-bold uppercase tracking-wide">Conferência da gaveta</h2>
        <table className="w-full text-sm">
          <tbody className="divide-y">
            <tr>
              <td className="py-1.5">Fundo de caixa</td>
              <td className="py-1.5 text-right tabular-nums">{formatarReais(resumo.fundo)}</td>
            </tr>
            <tr>
              <td className="py-1.5">(+) Recebido em dinheiro</td>
              <td className="py-1.5 text-right tabular-nums">{formatarReais(dinheiroRecebido)}</td>
            </tr>
            <tr>
              <td className="py-1.5">(−) Sangrias</td>
              <td className="py-1.5 text-right tabular-nums">{formatarReais(resumo.sangrias)}</td>
            </tr>
            <tr className="font-bold">
              <td className="py-2">(=) Dinheiro que deve estar na gaveta</td>
              <td className="py-2 text-right tabular-nums">
                {formatarReais(movimento.dinheiro_na_gaveta_cents)}
              </td>
            </tr>
          </tbody>
        </table>
      </section>

      <section className="space-y-2">
        <h2 className="text-sm font-bold uppercase tracking-wide">Recebimentos por forma</h2>
        <table className="w-full text-sm">
          <tbody className="divide-y">
            {FORMAS_DE_PAGAMENTO.map((f) => (
              <tr key={f}>
                <td className="py-1.5">{ROTULO_DA_FORMA[f]}</td>
                <td className="py-1.5 text-right tabular-nums">{formatarReais(resumo.porForma[f])}</td>
              </tr>
            ))}
            <tr className="font-bold">
              <td className="py-2">
                Total recebido · {movimento.recebimentos.length} pedido(s)
              </td>
              <td className="py-2 text-right tabular-nums">{formatarReais(resumo.recebido)}</td>
            </tr>
            {resumo.aReceber > 0 ? (
              <tr className="text-muted-foreground">
                <td className="py-1.5">
                  Ainda a receber · {movimento.a_receber.length} pedido(s)
                </td>
                <td className="py-1.5 text-right tabular-nums">{formatarReais(resumo.aReceber)}</td>
              </tr>
            ) : null}
          </tbody>
        </table>
      </section>

      <section className="space-y-2 print:break-inside-avoid">
        <h2 className="text-sm font-bold uppercase tracking-wide">Fundo e sangrias</h2>
        {movimento.lancamentos.length === 0 ? (
          <p className="text-sm text-muted-foreground">Nenhum lançamento neste dia.</p>
        ) : (
          <table className="w-full text-sm">
            <thead className="text-left text-xs uppercase text-muted-foreground">
              <tr>
                <th className="py-1 font-semibold">Hora</th>
                <th className="py-1 font-semibold">Lançamento</th>
                <th className="py-1 font-semibold">Por</th>
                <th className="py-1 text-right font-semibold">Valor</th>
              </tr>
            </thead>
            <tbody className="divide-y">
              {movimento.lancamentos.map((l) => (
                <tr key={l.id} className={l.cancelado_em ? "text-muted-foreground" : ""}>
                  <td className="py-1.5 align-top tabular-nums">{hora(l.feito_em, fuso)}</td>
                  <td className="py-1.5 align-top">
                    <span className={l.cancelado_em ? "line-through" : ""}>
                      {ROTULO_DO_LANCAMENTO[l.tipo]}
                      {l.observacao ? ` — ${l.observacao}` : ""}
                    </span>
                    {l.cancelado_em ? (
                      <span className="block text-xs">
                        Cancelado às {hora(l.cancelado_em, fuso)}
                        {l.cancelado_por ? ` por ${l.cancelado_por}` : ""}
                      </span>
                    ) : null}
                  </td>
                  <td className="py-1.5 align-top">{l.feito_por ?? "—"}</td>
                  <td
                    className={`py-1.5 text-right align-top tabular-nums ${
                      l.cancelado_em ? "line-through" : ""
                    }`}
                  >
                    {l.tipo === "withdrawal" ? "− " : ""}
                    {formatarReais(l.valor_cents)}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </section>

      <section className="space-y-2">
        <h2 className="text-sm font-bold uppercase tracking-wide">Recebimentos</h2>
        {movimento.recebimentos.length === 0 ? (
          <p className="text-sm text-muted-foreground">Nenhum pagamento recebido neste dia.</p>
        ) : (
          <table className="w-full text-sm">
            <thead className="text-left text-xs uppercase text-muted-foreground">
              <tr>
                <th className="py-1 font-semibold">Hora</th>
                <th className="py-1 font-semibold">Pedido</th>
                <th className="py-1 font-semibold">Forma</th>
                <th className="py-1 text-right font-semibold">Valor</th>
              </tr>
            </thead>
            <tbody className="divide-y">
              {movimento.recebimentos.map((r) => {
                const forma = formaDePagamento(r.forma)
                return (
                  <tr key={r.pedido_id} className="print:break-inside-avoid">
                    <td className="py-1.5 tabular-nums">{hora(r.pago_em, fuso)}</td>
                    <td className="py-1.5">
                      nº {r.numero} · {r.cliente}
                    </td>
                    <td className="py-1.5">
                      {forma ? ROTULO_DA_FORMA[forma] : r.forma}
                      {r.momento === "online" ? " (site)" : ""}
                    </td>
                    <td className="py-1.5 text-right tabular-nums">{formatarReais(r.valor_cents)}</td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        )}
      </section>

      {/* A assinatura é o que transforma a folha em conferência. */}
      <footer className="grid grid-cols-2 gap-10 pt-12 text-center text-xs text-muted-foreground print:break-inside-avoid">
        <div className="border-t pt-2">Responsável pelo caixa</div>
        <div className="border-t pt-2">Conferido por</div>
      </footer>
    </div>
  )
}
