import type { Metadata } from "next"

import { ListaDeProdutos } from "@/components/painel/lista-de-produtos"
import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirVinculo } from "@/modules/auth/sessao"

export const metadata: Metadata = { title: "Produtos" }

export default async function PaginaDeProdutos() {
  const { vinculo } = await exigirVinculo()
  const supabase = await criarClienteDoServidor()

  const [{ data: categorias }, { data: produtos }] = await Promise.all([
    supabase
      .from("categories")
      .select("id, name")
      .eq("restaurant_id", vinculo.restauranteId)
      .is("deleted_at", null)
      .order("position"),
    supabase
      .from("products")
      .select(
        "id, category_id, name, description, image_url, price_cents, promo_price_cents, promo_ends_at, is_available, is_featured, track_stock, stock_quantity, sold_count",
      )
      .eq("restaurant_id", vinculo.restauranteId)
      .is("deleted_at", null)
      .order("position"),
  ])

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">Produtos</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          O que você vende, por quanto, e o que está no ar agora.
        </p>
      </div>

      <ListaDeProdutos
        restauranteId={vinculo.restauranteId}
        categorias={(categorias ?? []).map((c) => ({ id: c.id, nome: c.name }))}
        produtos={produtos ?? []}
        podeGerenciar={vinculo.cargo !== "staff"}
      />
    </div>
  )
}
