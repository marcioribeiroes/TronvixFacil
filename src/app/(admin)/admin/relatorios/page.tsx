import type { Metadata } from "next"

import { formatarReais } from "@/lib/dinheiro"
import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirAdminDaPlataforma } from "@/modules/auth/sessao"
import { ROTULO_DA_SITUACAO, type SituacaoDoPedido } from "@/modules/pedidos/maquina-de-estados"

export const metadata: Metadata = { title: "Relatórios" }

/** Rótulo curto de dia, para o eixo do gráfico. */
function diaCurto(iso: string) {
  return new Date(iso).toLocaleDateString("pt-BR", { day: "2-digit", month: "2-digit" })
}

export default async function PaginaDeRelatorios() {
  await exigirAdminDaPlataforma()
  const supabase = await criarClienteDoServidor()

  const inicio = new Date()
  inicio.setDate(inicio.getDate() - 29)
  inicio.setHours(0, 0, 0, 0)

  const [{ data: pedidos }, { data: itens }] = await Promise.all([
    supabase
      .from("orders")
      .select("id, status, total_cents, created_at, restaurant_id, restaurants(name)")
      .gte("created_at", inicio.toISOString()),
    supabase
      .from("order_items")
      .select("product_name, quantity, total_cents, orders!inner(created_at, status)")
      .gte("orders.created_at", inicio.toISOString()),
  ])

  const valendo = (pedidos ?? []).filter(
    (p) => p.status !== "cancelled" && p.status !== "rejected",
  )

  const faturado = valendo.reduce((s, p) => s + p.total_cents, 0)
  const ticket = valendo.length > 0 ? Math.round(faturado / valendo.length) : 0

  // Vendas por dia. Um dia sem venda continua no eixo — buraco no gráfico é
  // informação; dia omitido vira mentira sobre a constância.
  const porDia = new Map<string, number>()
  for (let d = 0; d < 30; d++) {
    const dia = new Date(inicio)
    dia.setDate(dia.getDate() + d)
    porDia.set(dia.toISOString().slice(0, 10), 0)
  }
  for (const p of valendo) {
    const chave = p.created_at.slice(0, 10)
    if (porDia.has(chave)) porDia.set(chave, (porDia.get(chave) ?? 0) + p.total_cents)
  }
  const dias = [...porDia.entries()]
  const pico = Math.max(1, ...dias.map(([, v]) => v))

  const porSituacao = new Map<string, number>()
  for (const p of pedidos ?? []) {
    porSituacao.set(p.status, (porSituacao.get(p.status) ?? 0) + 1)
  }

  const porLoja = new Map<string, { nome: string; total: number; pedidos: number }>()
  for (const p of valendo) {
    const atual = porLoja.get(p.restaurant_id) ?? {
      nome: p.restaurants?.name ?? "—",
      total: 0,
      pedidos: 0,
    }
    atual.total += p.total_cents
    atual.pedidos += 1
    porLoja.set(p.restaurant_id, atual)
  }

  const maisVendidos = new Map<string, { quantidade: number; total: number }>()
  for (const i of itens ?? []) {
    const pedido = i.orders as { status: string } | null
    if (pedido?.status === "cancelled" || pedido?.status === "rejected") continue
    const atual = maisVendidos.get(i.product_name) ?? { quantidade: 0, total: 0 }
    atual.quantidade += i.quantity
    atual.total += i.total_cents
    maisVendidos.set(i.product_name, atual)
  }

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">Relatórios</h1>
        <p className="mt-1 text-sm text-muted-foreground">Últimos 30 dias.</p>
      </div>

      <dl className="grid gap-3 sm:grid-cols-3">
        <div className="rounded-xl border bg-card p-4">
          <dt className="text-xs font-semibold uppercase text-muted-foreground">Faturado</dt>
          <dd className="text-2xl font-bold">{formatarReais(faturado)}</dd>
        </div>
        <div className="rounded-xl border bg-card p-4">
          <dt className="text-xs font-semibold uppercase text-muted-foreground">Pedidos</dt>
          <dd className="text-2xl font-bold">{valendo.length}</dd>
        </div>
        <div className="rounded-xl border bg-card p-4">
          <dt className="text-xs font-semibold uppercase text-muted-foreground">
            Ticket médio
          </dt>
          <dd className="text-2xl font-bold">{formatarReais(ticket)}</dd>
        </div>
      </dl>

      <section>
        <h2 className="text-sm font-bold uppercase tracking-wide text-muted-foreground">
          Vendas por dia
        </h2>
        {/* Barras em CSS puro: um gráfico de trinta colunas não justifica uma
            biblioteca de gráficos e o peso que ela traz. */}
        <div className="mt-3 flex h-40 items-end gap-1 rounded-xl border bg-card p-4">
          {dias.map(([dia, valor]) => (
            <div key={dia} className="group relative flex h-full flex-1 items-end" title={`${diaCurto(dia)}: ${formatarReais(valor)}`}>
              <div
                className="w-full rounded-t bg-marca transition-colors group-hover:bg-marca-forte"
                style={{ height: `${Math.max(2, (valor / pico) * 100)}%` }}
              />
            </div>
          ))}
        </div>
        <p className="mt-1 flex justify-between text-xs text-muted-foreground">
          <span>{diaCurto(dias[0][0])}</span>
          <span>pico {formatarReais(pico)}</span>
          <span>{diaCurto(dias.at(-1)![0])}</span>
        </p>
      </section>

      <div className="grid gap-6 lg:grid-cols-2">
        <section>
          <h2 className="text-sm font-bold uppercase tracking-wide text-muted-foreground">
            Por estabelecimento
          </h2>
          <ul className="mt-2 divide-y rounded-xl border bg-card">
            {[...porLoja.values()]
              .sort((a, b) => b.total - a.total)
              .map((r) => (
                <li key={r.nome} className="flex items-center gap-3 p-3 text-sm">
                  <span className="flex-1 font-medium">{r.nome}</span>
                  <span className="text-muted-foreground">{r.pedidos} pedidos</span>
                  <span className="font-bold">{formatarReais(r.total)}</span>
                </li>
              ))}
            {porLoja.size === 0 ? (
              <li className="p-4 text-sm text-muted-foreground">Nenhuma venda no período.</li>
            ) : null}
          </ul>
        </section>

        <section>
          <h2 className="text-sm font-bold uppercase tracking-wide text-muted-foreground">
            Mais vendidos
          </h2>
          <ul className="mt-2 divide-y rounded-xl border bg-card">
            {[...maisVendidos.entries()]
              .sort((a, b) => b[1].quantidade - a[1].quantidade)
              .slice(0, 8)
              .map(([nome, dados]) => (
                <li key={nome} className="flex items-center gap-3 p-3 text-sm">
                  <span className="flex-1 font-medium">{nome}</span>
                  <span className="text-muted-foreground">{dados.quantidade}×</span>
                  <span className="font-bold">{formatarReais(dados.total)}</span>
                </li>
              ))}
            {maisVendidos.size === 0 ? (
              <li className="p-4 text-sm text-muted-foreground">Nada vendido no período.</li>
            ) : null}
          </ul>
        </section>
      </div>

      <section>
        <h2 className="text-sm font-bold uppercase tracking-wide text-muted-foreground">
          Como os pedidos terminaram
        </h2>
        <ul className="mt-2 flex flex-wrap gap-3">
          {[...porSituacao.entries()].map(([situacao, quantos]) => (
            <li key={situacao} className="rounded-lg border bg-card px-3 py-2 text-sm">
              <span className="font-bold">{quantos}</span>{" "}
              <span className="text-muted-foreground">
                {ROTULO_DA_SITUACAO[situacao as SituacaoDoPedido] ?? situacao}
              </span>
            </li>
          ))}
        </ul>
      </section>
    </div>
  )
}
