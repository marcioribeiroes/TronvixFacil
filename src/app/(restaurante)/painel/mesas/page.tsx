import type { Metadata } from "next"

import { MesasDoSalao, type MesaNaTela } from "@/components/painel/mesas-do-salao"
import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirGestao } from "@/modules/auth/sessao"

export const metadata: Metadata = { title: "Mesas" }

/** Pedido que ainda está na conta da mesa — nem pago, nem cancelado. */
const EM_ABERTO = ["received", "confirmed", "preparing", "ready", "delivered"] as const

export default async function PaginaDeMesas() {
  const { vinculo } = await exigirGestao()
  const supabase = await criarClienteDoServidor()

  const [{ data: mesas }, { data: pedidos }] = await Promise.all([
    supabase
      .from("restaurant_tables")
      .select("id, label, code, is_active")
      .eq("restaurant_id", vinculo.restauranteId)
      .is("deleted_at", null)
      .order("label"),
    // A conta da mesa é a soma dos pedidos dela no dia. Não há entidade
    // "comanda": uma mesa acumula pedidos, e a conta é essa soma.
    supabase
      .from("orders")
      .select("table_id, total_cents")
      .eq("restaurant_id", vinculo.restauranteId)
      .eq("fulfillment", "dine_in")
      .in("status", EM_ABERTO)
      .not("table_id", "is", null),
  ])

  const porMesa = new Map<string, { quantos: number; total: number }>()
  for (const p of pedidos ?? []) {
    if (!p.table_id) continue
    const atual = porMesa.get(p.table_id) ?? { quantos: 0, total: 0 }
    atual.quantos += 1
    atual.total += p.total_cents
    porMesa.set(p.table_id, atual)
  }

  const lista: MesaNaTela[] = (mesas ?? []).map((m) => ({
    id: m.id,
    rotulo: m.label,
    codigo: m.code,
    emUso: m.is_active,
    pedidosAbertos: porMesa.get(m.id)?.quantos ?? 0,
    contaAbertaCentavos: porMesa.get(m.id)?.total ?? 0,
  }))

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">Mesas</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          O cliente lê o QR da mesa, pede pelo próprio celular, e o pedido cai na cozinha com o
          número da mesa. Sem garçom anotando, sem comanda de papel.
        </p>
      </div>

      <MesasDoSalao
        mesas={lista}
        enderecoDoSite={process.env.NEXT_PUBLIC_URL_DO_SITE ?? "http://localhost:3000"}
      />
    </div>
  )
}
