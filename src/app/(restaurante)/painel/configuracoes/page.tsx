import type { Metadata } from "next"

import { ConfiguracoesDaLoja } from "@/components/painel/configuracoes-da-loja"
import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirGestao } from "@/modules/auth/sessao"

export const metadata: Metadata = { title: "Configurações" }

export default async function PaginaDeConfiguracoes() {
  const { vinculo } = await exigirGestao()
  const supabase = await criarClienteDoServidor()

  const [{ data: loja }, { data: horarios }, { data: formas }] = await Promise.all([
    supabase
      .from("restaurants")
      .select(
        "id, name, description, phone, delivery_fee_cents, free_delivery_above_cents, min_order_cents, avg_prep_minutes, avg_delivery_minutes, delivery_radius_km, accepts_scheduled_orders",
      )
      .eq("id", vinculo.restauranteId)
      .single(),
    supabase
      .from("restaurant_hours")
      .select("id, weekday, opens_at, closes_at")
      .eq("restaurant_id", vinculo.restauranteId)
      .order("weekday")
      .order("opens_at"),
    supabase
      .from("restaurant_payment_methods")
      .select("method, timing, is_active")
      .eq("restaurant_id", vinculo.restauranteId),
  ])

  if (!loja) return null

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">Configurações</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Taxa, pedido mínimo, horário e formas de pagamento. Tudo isto entra na
          conta do pedido — quem aplica é o banco, no fechamento.
        </p>
      </div>

      <ConfiguracoesDaLoja
        loja={loja}
        horarios={horarios ?? []}
        formas={formas ?? []}
      />
    </div>
  )
}
