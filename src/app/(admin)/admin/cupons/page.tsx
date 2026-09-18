import type { Metadata } from "next"

import { ListaDeCupons } from "@/components/admin/lista-de-cupons"
import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirAdminDaPlataforma } from "@/modules/auth/sessao"

export const metadata: Metadata = { title: "Cupons" }

export default async function PaginaDeCupons() {
  await exigirAdminDaPlataforma()
  const supabase = await criarClienteDoServidor()

  const [{ data: cupons }, { data: estabelecimentos }] = await Promise.all([
    supabase
      .from("coupons")
      .select(
        "id, code, description, scope, restaurant_id, discount, value, min_order_cents, max_discount_cents, ends_at, max_uses, max_uses_per_customer, used_count, first_order_only, is_active, restaurants(name)",
      )
      .is("deleted_at", null)
      .order("created_at", { ascending: false }),
    supabase
      .from("restaurants")
      .select("id, name")
      .eq("status", "approved")
      .is("deleted_at", null)
      .order("name"),
  ])

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">Cupons</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Desconto da plataforma ou de um estabelecimento. Quem valida é o banco:
          janela, limite por cliente e primeiro pedido.
        </p>
      </div>

      <ListaDeCupons
        cupons={cupons ?? []}
        estabelecimentos={(estabelecimentos ?? []).map((r) => ({ id: r.id, nome: r.name }))}
      />
    </div>
  )
}
