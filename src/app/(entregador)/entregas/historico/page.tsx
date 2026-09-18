import type { Metadata } from "next"
import { History } from "lucide-react"

import { formatarReais } from "@/lib/dinheiro"
import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirEntregador } from "@/modules/auth/sessao"

export const metadata: Metadata = { title: "Histórico" }

/**
 * O que este entregador ja levou, e quanto rendeu.
 *
 * Os ganhos vem de `courier_fee_cents` da propria corrida, congelado quando a
 * entrega foi criada - e nao de multiplicar entregas por uma taxa de hoje. Quem
 * trabalhou na semana passada recebeu o valor da semana passada, e a tela tem
 * de concordar com o extrato.
 */

function dia(iso: string) {
  return new Date(iso).toLocaleDateString("pt-BR", {
    day: "2-digit",
    month: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  })
}

export default async function HistoricoDoEntregador() {
  const { entregadorId } = await exigirEntregador()
  const supabase = await criarClienteDoServidor()

  const trintaDias = new Date()
  trintaDias.setDate(trintaDias.getDate() - 29)
  trintaDias.setHours(0, 0, 0, 0)

  const hoje = new Date()
  hoje.setHours(0, 0, 0, 0)

  const semana = new Date()
  semana.setDate(semana.getDate() - 6)
  semana.setHours(0, 0, 0, 0)

  const { data: entregas } = await supabase
    .from("deliveries")
    .select("id, courier_fee_cents, delivered_at, orders(number, customer_name, address_district, restaurants(name))")
    .eq("courier_id", entregadorId)
    .eq("status", "delivered")
    .gte("delivered_at", trintaDias.toISOString())
    .order("delivered_at", { ascending: false })

  const lista = entregas ?? []
  const somar = (desde: Date) =>
    lista
      .filter((d) => d.delivered_at && new Date(d.delivered_at) >= desde)
      .reduce((s, d) => s + d.courier_fee_cents, 0)

  const doDia = somar(hoje)
  const daSemana = somar(semana)
  const doMes = lista.reduce((s, d) => s + d.courier_fee_cents, 0)

  return (
    <div className="mx-auto max-w-lg space-y-4">
      <h1 className="text-xl font-bold tracking-tight">Histórico</h1>

      <dl className="grid grid-cols-3 gap-2">
        {[
          ["Hoje", doDia],
          ["7 dias", daSemana],
          ["30 dias", doMes],
        ].map(([rotulo, valor]) => (
          <div key={rotulo as string} className="rounded-xl border bg-card p-3 text-center">
            <dt className="text-[11px] font-semibold uppercase text-muted-foreground">
              {rotulo}
            </dt>
            <dd className="text-lg font-bold">{formatarReais(valor as number)}</dd>
          </div>
        ))}
      </dl>

      <p className="text-xs text-muted-foreground">
        {lista.length} {lista.length === 1 ? "entrega" : "entregas"} nos últimos 30 dias.
      </p>

      {lista.length === 0 ? (
        <div className="rounded-xl border border-dashed p-10 text-center">
          <History className="mx-auto size-8 text-muted-foreground" aria-hidden="true" />
          <p className="mt-3 font-semibold">Nenhuma entrega ainda</p>
          <p className="mt-1 text-sm text-muted-foreground">
            As corridas concluídas aparecem aqui, com o que cada uma rendeu.
          </p>
        </div>
      ) : (
        <ul className="divide-y rounded-xl border bg-card">
          {lista.map((d) => (
            <li key={d.id} className="flex items-center gap-3 p-3 text-sm">
              <span className="min-w-0 flex-1">
                <span className="block truncate font-medium">
                  {d.orders?.restaurants?.name ?? "—"}
                </span>
                <span className="block truncate text-xs text-muted-foreground">
                  #{d.orders?.number ?? 0} · {d.orders?.customer_name ?? ""}
                  {d.orders?.address_district ? ` · ${d.orders.address_district}` : ""}
                </span>
              </span>
              <span className="shrink-0 text-right">
                <span className="block font-bold">{formatarReais(d.courier_fee_cents)}</span>
                <span className="block text-[11px] text-muted-foreground">
                  {d.delivered_at ? dia(d.delivered_at) : "—"}
                </span>
              </span>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}
