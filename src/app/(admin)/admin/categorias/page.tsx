import type { Metadata } from "next"

import { CategoriasDaVitrine } from "@/components/admin/categorias-da-vitrine"
import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirAdminDaPlataforma } from "@/modules/auth/sessao"

export const metadata: Metadata = { title: "Categorias" }

export default async function PaginaDeCategorias() {
  await exigirAdminDaPlataforma()
  const supabase = await criarClienteDoServidor()

  const { data: categorias } = await supabase
    .from("platform_categories")
    .select("id, slug, name, position, is_active, restaurant_platform_categories(count)")
    .order("position")

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">Categorias</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Os filtros da vitrine — lanches, pizzas, açaí. Cada estabelecimento
          escolhe em quais aparece.
        </p>
      </div>

      <CategoriasDaVitrine
        categorias={(categorias ?? []).map((c) => ({
          id: c.id,
          nome: c.name,
          slug: c.slug,
          posicao: c.position,
          ativa: c.is_active,
          estabelecimentos: c.restaurant_platform_categories?.[0]?.count ?? 0,
        }))}
      />
    </div>
  )
}
