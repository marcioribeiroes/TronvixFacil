import type { Metadata } from "next"

import { Badge } from "@/components/ui/badge"
import { formatarReais } from "@/lib/dinheiro"
import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirAdminDaPlataforma } from "@/modules/auth/sessao"

export const metadata: Metadata = { title: "Financeiro" }

/**
 * Quanto cada estabelecimento vendeu, quanto a plataforma reteve e quanto
 * sobra para repassar.
 *
 * A comissao nao e recalculada aqui: ela foi congelada em `commission_cents`
 * no fechamento de cada pedido. Mudar a comissao de um estabelecimento hoje
 * nao reescreve o que ja foi acertado — e este relatorio conta a verdade
 * daquele momento, nao a de agora.
 *
 * Cancelados e recusados ficam de fora: pedido que nao aconteceu nao gera
 * repasse nem comissao.
 */
export default async function PaginaFinanceira() {
  await exigirAdminDaPlataforma()
  const supabase = await criarClienteDoServidor()

  const trintaDias = new Date()
  trintaDias.setDate(trintaDias.getDate() - 30)

  const [{ data: pedidos }, { data: estabelecimentos }] = await Promise.all([
    supabase
      .from("orders")
      .select("restaurant_id, subtotal_cents, delivery_fee_cents, commission_cents, total_cents, status, created_at")
      .gte("created_at", trintaDias.toISOString()),
    supabase
      .from("restaurants")
      .select("id, name, commission_bps")
      .is("deleted_at", null)
      .order("name"),
  ])

  const valendo = (pedidos ?? []).filter(
    (p) => p.status !== "cancelled" && p.status !== "rejected",
  )

  const porLoja = new Map<
    string,
    { pedidos: number; mercadoria: number; entrega: number; comissao: number; total: number }
  >()

  for (const p of valendo) {
    const atual = porLoja.get(p.restaurant_id) ?? {
      pedidos: 0,
      mercadoria: 0,
      entrega: 0,
      comissao: 0,
      total: 0,
    }
    atual.pedidos += 1
    atual.mercadoria += p.subtotal_cents
    atual.entrega += p.delivery_fee_cents
    atual.comissao += p.commission_cents
    atual.total += p.total_cents
    porLoja.set(p.restaurant_id, atual)
  }

  const linhas = (estabelecimentos ?? [])
    .map((r) => ({ ...r, ...(porLoja.get(r.id) ?? null) }))
    .filter((r) => "pedidos" in r && r.pedidos)
    .sort((a, b) => (b.total ?? 0) - (a.total ?? 0))

  const totalVendido = valendo.reduce((s, p) => s + p.total_cents, 0)
  const totalComissao = valendo.reduce((s, p) => s + p.commission_cents, 0)

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">Financeiro</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Últimos 30 dias. A comissão vem congelada de cada pedido, não recalculada
          agora.
        </p>
      </div>

      <dl className="grid gap-3 sm:grid-cols-3">
        <div className="rounded-xl border bg-card p-4">
          <dt className="text-xs font-semibold uppercase text-muted-foreground">Vendido</dt>
          <dd className="text-2xl font-bold">{formatarReais(totalVendido)}</dd>
        </div>
        <div className="rounded-xl border bg-card p-4">
          <dt className="text-xs font-semibold uppercase text-muted-foreground">
            Comissão retida
          </dt>
          <dd className="text-2xl font-bold">{formatarReais(totalComissao)}</dd>
        </div>
        <div className="rounded-xl border bg-card p-4">
          <dt className="text-xs font-semibold uppercase text-muted-foreground">Pedidos</dt>
          <dd className="text-2xl font-bold">{valendo.length}</dd>
        </div>
      </dl>

      {linhas.length === 0 ? (
        <div className="rounded-xl border border-dashed p-10 text-center">
          <p className="font-semibold">Nenhuma venda nos últimos 30 dias</p>
        </div>
      ) : (
        <div className="overflow-x-auto rounded-xl border bg-card">
          <table className="w-full text-sm">
            <thead className="border-b bg-muted/40 text-left">
              <tr>
                <th className="p-3 font-semibold">Estabelecimento</th>
                <th className="p-3 text-right font-semibold">Pedidos</th>
                <th className="p-3 text-right font-semibold">Mercadoria</th>
                <th className="p-3 text-right font-semibold">Entrega</th>
                <th className="p-3 text-right font-semibold">Comissão</th>
                <th className="p-3 text-right font-semibold">A repassar</th>
              </tr>
            </thead>
            <tbody className="divide-y">
              {linhas.map((r) => (
                <tr key={r.id}>
                  <td className="p-3">
                    <span className="font-semibold">{r.name}</span>{" "}
                    <Badge variant="secondary">
                      {(r.commission_bps / 100).toLocaleString("pt-BR")}%
                    </Badge>
                  </td>
                  <td className="p-3 text-right">{r.pedidos}</td>
                  <td className="p-3 text-right">{formatarReais(r.mercadoria ?? 0)}</td>
                  <td className="p-3 text-right">{formatarReais(r.entrega ?? 0)}</td>
                  <td className="p-3 text-right">{formatarReais(r.comissao ?? 0)}</td>
                  <td className="p-3 text-right font-bold">
                    {/* O que sobra para o estabelecimento: a mercadoria menos a
                        comissão. A entrega é outro bolso — é do entregador. */}
                    {formatarReais((r.mercadoria ?? 0) - (r.comissao ?? 0))}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      <p className="text-xs text-muted-foreground">
        A taxa de entrega aparece separada porque não é receita do
        estabelecimento nem da plataforma: é o que remunera quem leva.
      </p>
    </div>
  )
}
