import type { Metadata } from "next"

import { formatarReais } from "@/lib/dinheiro"
import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirAdminDaPlataforma } from "@/modules/auth/sessao"
import {
  ROTULO_DA_SITUACAO,
  pedidoEmAndamento,
  type SituacaoDoPedido,
} from "@/modules/pedidos/maquina-de-estados"

export const metadata: Metadata = { title: "Pedidos" }

/**
 * Os pedidos de todos os estabelecimentos.
 *
 * Aqui a plataforma nao mexe no pedido - quem aceita, prepara e entrega e a
 * loja. Esta tela existe para o suporte: o cliente liga reclamando, e alguem
 * precisa ver o pedido sem pedir a senha do painel da loja.
 *
 * Por isso e so leitura. Um botao de "cancelar" aqui seria a plataforma
 * decidindo no lugar do restaurante.
 */

function quando(iso: string) {
  const d = new Date(iso)
  const minutos = Math.floor((Date.now() - d.getTime()) / 60_000)
  if (minutos < 60) return `${Math.max(0, minutos)} min`
  return d.toLocaleString("pt-BR", {
    day: "2-digit",
    month: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  })
}

export default async function PaginaDePedidos() {
  await exigirAdminDaPlataforma()
  const supabase = await criarClienteDoServidor()

  const { data: pedidos } = await supabase
    .from("orders")
    .select(
      "id, number, status, fulfillment, customer_name, customer_phone, total_cents, commission_cents, created_at, address_district, address_city, restaurants(name, phone)",
    )
    .order("created_at", { ascending: false })
    .limit(200)

  const lista = pedidos ?? []
  const andando = lista.filter((p) => pedidoEmAndamento(p.status as SituacaoDoPedido))
  const resto = lista.filter((p) => !pedidoEmAndamento(p.status as SituacaoDoPedido))

  function Linha({ p }: { p: (typeof lista)[number] }) {
    const ruim = p.status === "cancelled" || p.status === "rejected"
    return (
      <li className="flex flex-wrap items-center gap-x-3 gap-y-1 p-3 text-sm">
        <span className="shrink-0 font-mono text-xs text-muted-foreground">#{p.number}</span>
        <span className="min-w-0 flex-[2]">
          <span className="block truncate font-medium">{p.restaurants?.name ?? "—"}</span>
          <span className="block truncate text-xs text-muted-foreground">
            {p.customer_name}
            {p.customer_phone ? ` · ${p.customer_phone}` : ""}
          </span>
        </span>
        <span className="min-w-0 flex-1 truncate text-xs text-muted-foreground">
          {p.fulfillment === "pickup"
            ? "retirada"
            : [p.address_district, p.address_city].filter(Boolean).join(", ") || "entrega"}
        </span>
        <span className="shrink-0 text-xs text-muted-foreground">{quando(p.created_at)}</span>
        <span
          className={`shrink-0 rounded-md px-2 py-0.5 text-xs font-semibold ${
            ruim
              ? "bg-red-100 text-red-800 dark:bg-red-950 dark:text-red-300"
              : p.status === "delivered"
                ? "bg-emerald-100 text-emerald-800 dark:bg-emerald-950 dark:text-emerald-300"
                : "bg-muted text-muted-foreground"
          }`}
        >
          {ROTULO_DA_SITUACAO[p.status as SituacaoDoPedido] ?? p.status}
        </span>
        <span className="shrink-0 text-right">
          <span className="block font-bold">{formatarReais(p.total_cents)}</span>
          <span className="block text-xs text-muted-foreground">
            {ruim ? "—" : `${formatarReais(p.commission_cents)} de comissão`}
          </span>
        </span>
      </li>
    )
  }

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">Pedidos</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Os 200 mais recentes, de todos os estabelecimentos. Só leitura: quem conduz o pedido
          é a loja.
        </p>
      </div>

      <section>
        <div className="flex items-center gap-2">
          <h2 className="text-sm font-bold uppercase tracking-wide text-muted-foreground">
            Em andamento
          </h2>
          {andando.length > 0 ? (
            <span className="rounded-full bg-marca px-2 py-0.5 text-xs font-bold text-white">
              {andando.length}
            </span>
          ) : null}
        </div>
        <ul className="mt-2 divide-y rounded-xl border bg-card">
          {andando.map((p) => (
            <Linha key={p.id} p={p} />
          ))}
          {andando.length === 0 ? (
            <li className="p-4 text-sm text-muted-foreground">
              Nenhum pedido correndo agora.
            </li>
          ) : null}
        </ul>
      </section>

      <section>
        <h2 className="text-sm font-bold uppercase tracking-wide text-muted-foreground">
          Encerrados
        </h2>
        <ul className="mt-2 divide-y rounded-xl border bg-card">
          {resto.map((p) => (
            <Linha key={p.id} p={p} />
          ))}
          {resto.length === 0 ? (
            <li className="p-4 text-sm text-muted-foreground">Nenhum pedido ainda.</li>
          ) : null}
        </ul>
      </section>
    </div>
  )
}
