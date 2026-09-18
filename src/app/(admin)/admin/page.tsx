import type { Metadata } from "next"
import Link from "next/link"

import { formatarReais } from "@/lib/dinheiro"
import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirAdminDaPlataforma } from "@/modules/auth/sessao"
import { pedidoEmAndamento, type SituacaoDoPedido } from "@/modules/pedidos/maquina-de-estados"

export const metadata: Metadata = { title: "Administração" }

/**
 * A primeira tela de quem opera a plataforma.
 *
 * O topo e sempre o que tem prazo - cadastro esperando aprovacao. Um
 * restaurante parado na fila e um cliente que nao vende e que, em uma semana,
 * some. Faturamento vem depois; ele nao vai a lugar nenhum.
 */

export default async function DashboardDaPlataforma() {
  await exigirAdminDaPlataforma()
  const supabase = await criarClienteDoServidor()

  const mes = new Date()
  mes.setDate(1)
  mes.setHours(0, 0, 0, 0)

  const hoje = new Date()
  hoje.setHours(0, 0, 0, 0)

  const [
    { data: lojas },
    { data: pedidos },
    { count: entregadoresEsperando },
    { count: pessoas },
  ] = await Promise.all([
    supabase
      .from("restaurants")
      .select("id, name, slug, status, is_open, commission_bps, city, created_at")
      .is("deleted_at", null)
      .order("created_at", { ascending: false }),
    supabase
      .from("orders")
      .select("id, status, total_cents, commission_cents, created_at")
      .gte("created_at", mes.toISOString()),
    supabase
      .from("couriers")
      .select("id", { count: "exact", head: true })
      .eq("status", "pending")
      .is("deleted_at", null),
    supabase.from("profiles").select("id", { count: "exact", head: true }),
  ])

  const todasAsLojas = lojas ?? []
  const esperando = todasAsLojas.filter((r) => r.status === "pending")
  const ativas = todasAsLojas.filter((r) => r.status === "approved")
  const abertas = ativas.filter((r) => r.is_open)

  const todos = pedidos ?? []
  const valendo = todos.filter((p) => p.status !== "cancelled" && p.status !== "rejected")
  const doDia = valendo.filter((p) => new Date(p.created_at) >= hoje)

  const gmv = valendo.reduce((s, p) => s + p.total_cents, 0)
  const comissao = valendo.reduce((s, p) => s + p.commission_cents, 0)
  const emAndamento = todos.filter((p) => pedidoEmAndamento(p.status as SituacaoDoPedido))

  const pendencias = [
    esperando.length > 0
      ? {
          chave: "lojas",
          quantos: esperando.length,
          texto:
            esperando.length === 1
              ? "estabelecimento esperando aprovação"
              : "estabelecimentos esperando aprovação",
          href: "/admin/restaurantes",
        }
      : null,
    (entregadoresEsperando ?? 0) > 0
      ? {
          chave: "entregadores",
          quantos: entregadoresEsperando ?? 0,
          texto:
            entregadoresEsperando === 1
              ? "entregador esperando aprovação"
              : "entregadores esperando aprovação",
          href: "/admin/entregadores",
        }
      : null,
  ].filter((p) => p !== null)

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">Plataforma</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Mês corrente, desde{" "}
          {mes.toLocaleDateString("pt-BR", { day: "2-digit", month: "long" })}.
        </p>
      </div>

      {pendencias.length > 0 ? (
        <ul className="space-y-2">
          {pendencias.map((p) => (
            <li key={p.chave}>
              <Link
                href={p.href}
                className="flex items-center gap-3 rounded-xl border-2 border-marca bg-marca/5 p-4 transition-colors hover:bg-marca/10"
              >
                <span className="flex size-10 shrink-0 items-center justify-center rounded-full bg-marca text-lg font-bold text-white">
                  {p.quantos}
                </span>
                <span className="min-w-0 flex-1 font-bold">{p.texto}</span>
                <span className="shrink-0 text-sm font-semibold text-marca">Resolver →</span>
              </Link>
            </li>
          ))}
        </ul>
      ) : null}

      <dl className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <div className="rounded-xl border bg-card p-4">
          <dt className="text-xs font-semibold uppercase text-muted-foreground">
            Vendido no mês
          </dt>
          <dd className="text-2xl font-bold">{formatarReais(gmv)}</dd>
          <dd className="mt-0.5 text-xs text-muted-foreground">{valendo.length} pedidos</dd>
        </div>
        <div className="rounded-xl border bg-card p-4">
          <dt className="text-xs font-semibold uppercase text-muted-foreground">
            Comissão no mês
          </dt>
          <dd className="text-2xl font-bold text-marca">{formatarReais(comissao)}</dd>
          <dd className="mt-0.5 text-xs text-muted-foreground">
            {gmv > 0 ? `${((comissao / gmv) * 100).toFixed(1).replace(".", ",")}% do vendido` : "—"}
          </dd>
        </div>
        <div className="rounded-xl border bg-card p-4">
          <dt className="text-xs font-semibold uppercase text-muted-foreground">Hoje</dt>
          <dd className="text-2xl font-bold">{doDia.length}</dd>
          <dd className="mt-0.5 text-xs text-muted-foreground">
            {emAndamento.length} em andamento
          </dd>
        </div>
        <div className="rounded-xl border bg-card p-4">
          <dt className="text-xs font-semibold uppercase text-muted-foreground">
            Estabelecimentos
          </dt>
          <dd className="text-2xl font-bold">{ativas.length}</dd>
          <dd className="mt-0.5 text-xs text-muted-foreground">
            {abertas.length} abertos agora · {pessoas ?? 0} pessoas cadastradas
          </dd>
        </div>
      </dl>

      <section>
        <h2 className="text-sm font-bold uppercase tracking-wide text-muted-foreground">
          Últimos cadastros
        </h2>
        <ul className="mt-3 divide-y rounded-xl border bg-card">
          {todasAsLojas.slice(0, 8).map((r) => (
            <li key={r.id} className="flex items-center gap-3 p-3 text-sm">
              <span className="min-w-0 flex-1">
                <span className="block truncate font-medium">{r.name}</span>
                <span className="block text-xs text-muted-foreground">
                  {r.city ?? "—"} · {(r.commission_bps / 100).toFixed(2).replace(".", ",")}% de
                  comissão
                </span>
              </span>
              <span
                className={`shrink-0 rounded-md px-2 py-0.5 text-xs font-semibold ${
                  r.status === "approved"
                    ? "bg-emerald-100 text-emerald-800 dark:bg-emerald-950 dark:text-emerald-300"
                    : r.status === "pending"
                      ? "bg-amber-100 text-amber-800 dark:bg-amber-950 dark:text-amber-300"
                      : "bg-muted text-muted-foreground"
                }`}
              >
                {r.status === "approved"
                  ? "Ativo"
                  : r.status === "pending"
                    ? "Esperando"
                    : r.status === "rejected"
                      ? "Recusado"
                      : "Suspenso"}
              </span>
            </li>
          ))}
          {todasAsLojas.length === 0 ? (
            <li className="p-4 text-sm text-muted-foreground">
              Nenhum estabelecimento cadastrado.
            </li>
          ) : null}
        </ul>
      </section>
    </div>
  )
}
