import type { Metadata } from "next"

import { SecoesDoCardapio } from "@/components/painel/secoes-do-cardapio"
import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirGestao } from "@/modules/auth/sessao"

export const metadata: Metadata = { title: "Categorias" }

/**
 * As secoes do cardapio.
 *
 * Vem antes de Produtos na navegacao porque produto exige categoria: o banco
 * tem `category_id` obrigatorio, e nao ha como cadastrar o primeiro lanche sem
 * ter a secao "Lanches".
 */
export default async function PaginaDeCategorias() {
  const { vinculo } = await exigirGestao()
  const supabase = await criarClienteDoServidor()

  const { data: categorias } = await supabase
    .from("categories")
    .select("id, name, description, position, products(count)")
    .eq("restaurant_id", vinculo.restauranteId)
    .is("deleted_at", null)
    .order("position")

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">Categorias</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          As seções do seu cardápio, na ordem em que o cliente vê.
        </p>
      </div>

      <SecoesDoCardapio
        categorias={(categorias ?? []).map((c) => ({
          id: c.id,
          nome: c.name,
          descricao: c.description,
          posicao: c.position,
          produtos: c.products?.[0]?.count ?? 0,
        }))}
      />
    </div>
  )
}
