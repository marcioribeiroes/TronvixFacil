import type { Metadata } from "next"

import { formatarReais } from "@/lib/dinheiro"
import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirGestao } from "@/modules/auth/sessao"
import { ROTULO_DA_SITUACAO, type SituacaoDoPedido } from "@/modules/pedidos/maquina-de-estados"

export const metadata: Metadata = { title: "Relatórios" }

/**
 * Os numeros da loja em 30 dias.
 *
 * O relatorio do dono e diferente do relatorio da plataforma em uma coisa: ele
 * mostra o que a plataforma reteve. Comissao escondida vira desconfianca, e
 * desconfianca cancela contrato.
 */

function diaCurto(iso: string) {
  return new Date(iso).toLocaleDateString("pt-BR", { day: "2-digit", month: "2-digit" })
}

export default async function RelatoriosDoRestaurante() {
  const { vinculo } = await exigirGestao()
  const supabase = await criarClienteDoServidor()

  const inicio = new Date()
  inicio.setDate(inicio.getDate() - 29)
  inicio.setHours(0, 0, 0, 0)

  const [{ data: pedidos }, { data: itens }] = await Promise.all([
    supabase
      .from("orders")
      .select("id, status, fulfillment, subtotal_cents, delivery_fee_cents, discount_cents, total_cents, commission_cents, created_at")
      .eq("restaurant_id", vinculo.restauranteId)
      .gte("created_at", inicio.toISOString()),
    supabase
      .from("order_items")
      .select("product_name, quantity, total_cents, orders!inner(created_at, status, restaurant_id)")
      .eq("orders.restaurant_id", vinculo.restauranteId)
      .gte("orders.created_at", inicio.toISOString()),
  ])

  const todos = pedidos ?? []
  const valendo = todos.filter((p) => p.status !== "cancelled" && p.status !== "rejected")

  const bruto = valendo.reduce((s, p) => s + p.total_cents, 0)
  const comissao = valendo.reduce((s, p) => s + p.commission_cents, 0)
  const taxas = valendo.reduce((s, p) => s + p.delivery_fee_cents, 0)
  const descontos = valendo.reduce((s, p) => s + p.discount_cents, 0)
  const ticket = valendo.length > 0 ? Math.round(bruto / valendo.length) : 0

  const entregas = valendo.filter((p) => p.fulfillment === "delivery").length
  const retiradas = valendo.length - entregas
  const perdidos = todos.length - valendo.length

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

  // Hora do dia: e o numero que muda escala de cozinha. Saber que 60% do
  // movimento cai entre 19h e 21h vale mais do que o total do mes.
  const porHora = new Array<number>(24).fill(0)
  for (const p of valendo) porHora[new Date(p.created_at).getHours()] += 1
  const picoDaHora = Math.max(1, ...porHora)

  const porSituacao = new Map<string, number>()
  for (const p of todos) porSituacao.set(p.status, (porSituacao.get(p.status) ?? 0) + 1)

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

      <dl className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <div className="rounded-xl border bg-card p-4">
          <dt className="text-xs font-semibold uppercase text-muted-foreground">Vendido</dt>
          <dd className="text-2xl font-bold">{formatarReais(bruto)}</dd>
          <dd className="mt-0.5 text-xs text-muted-foreground">{valendo.length} pedidos</dd>
        </div>
        <div className="rounded-xl border bg-card p-4">
          <dt className="text-xs font-semibold uppercase text-muted-foreground">
            Comissão retida
          </dt>
          <dd className="text-2xl font-bold">−{formatarReais(comissao)}</dd>
          <dd className="mt-0.5 text-xs text-muted-foreground">
            {bruto > 0 ? `${((comissao / bruto) * 100).toFixed(1).replace(".", ",")}% do vendido` : "—"}
          </dd>
        </div>
        <div className="rounded-xl border bg-card p-4">
          <dt className="text-xs font-semibold uppercase text-muted-foreground">
            Fica com a loja
          </dt>
          <dd className="text-2xl font-bold text-emerald-600">
            {formatarReais(bruto - comissao)}
          </dd>
          <dd className="mt-0.5 text-xs text-muted-foreground">
            já descontada a comissão
          </dd>
        </div>
        <div className="rounded-xl border bg-card p-4">
          <dt className="text-xs font-semibold uppercase text-muted-foreground">
            Ticket médio
          </dt>
          <dd className="text-2xl font-bold">{formatarReais(ticket)}</dd>
          <dd className="mt-0.5 text-xs text-muted-foreground">
            {entregas} entregas · {retiradas} retiradas
          </dd>
        </div>
      </dl>

      <section>
        <h2 className="text-sm font-bold uppercase tracking-wide text-muted-foreground">
          Vendas por dia
        </h2>
        <div className="mt-3 flex h-40 items-end gap-1 rounded-xl border bg-card p-4">
          {dias.map(([dia, valor]) => (
            <div
              key={dia}
              className="group relative flex h-full flex-1 items-end"
              title={`${diaCurto(dia)}: ${formatarReais(valor)}`}
            >
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

      <section>
        <h2 className="text-sm font-bold uppercase tracking-wide text-muted-foreground">
          Movimento por hora
        </h2>
        <div className="mt-3 flex h-28 items-end gap-1 rounded-xl border bg-card p-4">
          {porHora.map((quantos, hora) => (
            <div
              key={hora}
              className="flex h-full flex-1 items-end"
              title={`${String(hora).padStart(2, "0")}h: ${quantos} pedidos`}
            >
              <div
                className="w-full rounded-t bg-marca/60"
                style={{ height: `${Math.max(2, (quantos / picoDaHora) * 100)}%` }}
              />
            </div>
          ))}
        </div>
        <p className="mt-1 flex justify-between text-xs text-muted-foreground">
          <span>00h</span>
          <span>12h</span>
          <span>23h</span>
        </p>
      </section>

      <div className="grid gap-6 lg:grid-cols-2">
        <section>
          <h2 className="text-sm font-bold uppercase tracking-wide text-muted-foreground">
            Mais vendidos
          </h2>
          <ul className="mt-2 divide-y rounded-xl border bg-card">
            {[...maisVendidos.entries()]
              .sort((a, b) => b[1].quantidade - a[1].quantidade)
              .slice(0, 10)
              .map(([nome, dados]) => (
                <li key={nome} className="flex items-center gap-3 p-3 text-sm">
                  <span className="min-w-0 flex-1 truncate font-medium">{nome}</span>
                  <span className="shrink-0 text-muted-foreground">{dados.quantidade}×</span>
                  <span className="shrink-0 font-bold">{formatarReais(dados.total)}</span>
                </li>
              ))}
            {maisVendidos.size === 0 ? (
              <li className="p-4 text-sm text-muted-foreground">Nada vendido no período.</li>
            ) : null}
          </ul>
        </section>

        <section className="space-y-6">
          <div>
            <h2 className="text-sm font-bold uppercase tracking-wide text-muted-foreground">
              Como os pedidos terminaram
            </h2>
            <ul className="mt-2 flex flex-wrap gap-2">
              {[...porSituacao.entries()].map(([situacao, quantos]) => (
                <li key={situacao} className="rounded-lg border bg-card px-3 py-2 text-sm">
                  <span className="font-bold">{quantos}</span>{" "}
                  <span className="text-muted-foreground">
                    {ROTULO_DA_SITUACAO[situacao as SituacaoDoPedido] ?? situacao}
                  </span>
                </li>
              ))}
              {porSituacao.size === 0 ? (
                <li className="text-sm text-muted-foreground">Nenhum pedido no período.</li>
              ) : null}
            </ul>
          </div>

          <div>
            <h2 className="text-sm font-bold uppercase tracking-wide text-muted-foreground">
              O que saiu do bolso
            </h2>
            <ul className="mt-2 divide-y rounded-xl border bg-card text-sm">
              <li className="flex justify-between p-3">
                <span className="text-muted-foreground">Taxas de entrega cobradas</span>
                <span className="font-bold">{formatarReais(taxas)}</span>
              </li>
              <li className="flex justify-between p-3">
                <span className="text-muted-foreground">Descontos de cupom</span>
                <span className="font-bold">−{formatarReais(descontos)}</span>
              </li>
              <li className="flex justify-between p-3">
                <span className="text-muted-foreground">Pedidos perdidos</span>
                <span className="font-bold">{perdidos}</span>
              </li>
            </ul>
          </div>
        </section>
      </div>
    </div>
  )
}
