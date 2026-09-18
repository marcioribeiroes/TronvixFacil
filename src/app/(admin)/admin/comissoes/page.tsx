import type { Metadata } from "next"

import { LinhaDoEstabelecimento } from "@/components/admin/linha-do-estabelecimento"
import { formatarReais } from "@/lib/dinheiro"
import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirAdminDaPlataforma } from "@/modules/auth/sessao"

export const metadata: Metadata = { title: "Comissões" }

/**
 * Quanto cada loja paga, e quanto isso deu.
 *
 * A comissao de um pedido e congelada nele, em `commission_cents`, no momento
 * do fechamento. Baixar a comissao hoje nao reescreve o passado - e por isso
 * que esta tela mostra as duas coisas lado a lado: o percentual que vale de
 * agora em diante, e o que de fato foi retido.
 *
 * Mudar o percentual e a mesma acao da tela de restaurantes, e de proposito:
 * duas telas escrevendo o mesmo campo por caminhos diferentes e como duas
 * versoes da mesma regra.
 */
export default async function PaginaDeComissoes() {
  await exigirAdminDaPlataforma()
  const supabase = await criarClienteDoServidor()

  const mes = new Date()
  mes.setDate(1)
  mes.setHours(0, 0, 0, 0)

  const [{ data: estabelecimentos }, { data: pedidos }, { data: padrao }] = await Promise.all([
    supabase
      .from("restaurants")
      .select(
        "id, slug, name, description, logo_url, status, is_open, commission_bps, city, state, district, phone, created_at, approved_at, rating_avg, rating_count",
      )
      .is("deleted_at", null)
      .order("commission_bps", { ascending: false }),
    supabase
      .from("orders")
      .select("restaurant_id, status, total_cents, commission_cents, created_at")
      .gte("created_at", mes.toISOString()),
    supabase.from("platform_settings").select("default_commission_bps").maybeSingle(),
  ])

  const lojas = estabelecimentos ?? []
  const valendo = (pedidos ?? []).filter(
    (p) => p.status !== "cancelled" && p.status !== "rejected",
  )

  const retido = new Map<string, { comissao: number; vendido: number; pedidos: number }>()
  for (const p of valendo) {
    const atual = retido.get(p.restaurant_id) ?? { comissao: 0, vendido: 0, pedidos: 0 }
    atual.comissao += p.commission_cents
    atual.vendido += p.total_cents
    atual.pedidos += 1
    retido.set(p.restaurant_id, atual)
  }

  const totalRetido = valendo.reduce((s, p) => s + p.commission_cents, 0)
  const totalVendido = valendo.reduce((s, p) => s + p.total_cents, 0)

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">Comissões</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          O percentual vale de agora em diante. Cada pedido guarda a comissão que valia quando
          foi fechado.
        </p>
      </div>

      <dl className="grid gap-3 sm:grid-cols-3">
        <div className="rounded-xl border bg-card p-4">
          <dt className="text-xs font-semibold uppercase text-muted-foreground">
            Retido no mês
          </dt>
          <dd className="text-2xl font-bold text-marca">{formatarReais(totalRetido)}</dd>
        </div>
        <div className="rounded-xl border bg-card p-4">
          <dt className="text-xs font-semibold uppercase text-muted-foreground">
            Sobre o vendido
          </dt>
          <dd className="text-2xl font-bold">
            {totalVendido > 0
              ? `${((totalRetido / totalVendido) * 100).toFixed(2).replace(".", ",")}%`
              : "—"}
          </dd>
          <dd className="mt-0.5 text-xs text-muted-foreground">
            {formatarReais(totalVendido)} em {valendo.length} pedidos
          </dd>
        </div>
        <div className="rounded-xl border bg-card p-4">
          <dt className="text-xs font-semibold uppercase text-muted-foreground">
            Comissão padrão
          </dt>
          <dd className="text-2xl font-bold">
            {((padrao?.default_commission_bps ?? 0) / 100).toFixed(2).replace(".", ",")}%
          </dd>
          <dd className="mt-0.5 text-xs text-muted-foreground">
            a que um cadastro novo recebe
          </dd>
        </div>
      </dl>

      <section>
        <h2 className="text-sm font-bold uppercase tracking-wide text-muted-foreground">
          Retido no mês, por estabelecimento
        </h2>
        <ul className="mt-2 divide-y rounded-xl border bg-card">
          {lojas
            .map((r) => ({ r, dados: retido.get(r.id) }))
            .sort((a, b) => (b.dados?.comissao ?? 0) - (a.dados?.comissao ?? 0))
            .map(({ r, dados }) => (
              <li key={r.id} className="flex flex-wrap items-center gap-x-3 gap-y-1 p-3 text-sm">
                <span className="min-w-0 flex-1 truncate font-medium">{r.name}</span>
                <span className="shrink-0 rounded-md bg-muted px-2 py-0.5 text-xs font-semibold">
                  {(r.commission_bps / 100).toFixed(2).replace(".", ",")}%
                </span>
                <span className="shrink-0 text-xs text-muted-foreground">
                  {dados?.pedidos ?? 0} pedidos · {formatarReais(dados?.vendido ?? 0)}
                </span>
                <span className="shrink-0 font-bold text-marca">
                  {formatarReais(dados?.comissao ?? 0)}
                </span>
              </li>
            ))}
          {lojas.length === 0 ? (
            <li className="p-4 text-sm text-muted-foreground">
              Nenhum estabelecimento cadastrado.
            </li>
          ) : null}
        </ul>
      </section>

      <section>
        <h2 className="text-sm font-bold uppercase tracking-wide text-muted-foreground">
          Mudar o percentual
        </h2>
        <p className="mt-1 text-xs text-muted-foreground">
          Vale para os próximos pedidos. Os já fechados guardam o que valia na hora.
        </p>
        <div className="mt-3 space-y-3">
          {lojas.map((r) => (
            <LinhaDoEstabelecimento key={r.id} estabelecimento={r} />
          ))}
        </div>
      </section>
    </div>
  )
}
