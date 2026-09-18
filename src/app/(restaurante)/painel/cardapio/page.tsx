import type { Metadata } from "next"
import Link from "next/link"
import { UtensilsCrossed } from "lucide-react"

import { CardapioDoBalcao } from "@/components/painel/cardapio-do-balcao"
import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirVinculo } from "@/modules/auth/sessao"

export const metadata: Metadata = { title: "Cardápio" }

/**
 * O cardapio como o cliente o ve — e com uma chave por item.
 *
 * Diferente de Produtos, que e cadastro: aqui a unica operacao e tirar e repor
 * item do ar, que e o que se faz no meio do movimento. Por isso abre para o
 * atendente tambem.
 */
export default async function PaginaDoCardapio() {
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
        "id, category_id, name, description, price_cents, promo_price_cents, promo_ends_at, is_available, track_stock, stock_quantity",
      )
      .eq("restaurant_id", vinculo.restauranteId)
      .is("deleted_at", null)
      .order("position"),
  ])

  const secoes = (categorias ?? [])
    .map((c) => ({
      id: c.id,
      nome: c.name,
      produtos: (produtos ?? []).filter((p) => p.category_id === c.id),
    }))
    .filter((s) => s.produtos.length > 0)

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold tracking-tight">Cardápio</h1>
          <p className="mt-1 text-sm text-muted-foreground">
            O que o cliente vê agora. Acabou um item? Tire do ar aqui mesmo.
          </p>
        </div>
        {/* O Button do projeto nao tem asChild; o link recebe o estilo direto. */}
        <Link
          href="/painel/produtos"
          className="inline-flex h-10 items-center rounded-lg border px-4 text-sm font-medium transition-colors hover:bg-muted"
        >
          Cadastrar produtos
        </Link>
      </div>

      {secoes.length === 0 ? (
        <div className="rounded-xl border border-dashed p-10 text-center">
          <UtensilsCrossed className="mx-auto size-8 text-muted-foreground" aria-hidden="true" />
          <p className="mt-3 font-semibold">Cardápio vazio</p>
          <p className="mt-1 text-sm text-muted-foreground">
            Sem produto no ar, sua loja não recebe pedido.
          </p>
        </div>
      ) : (
        <CardapioDoBalcao secoes={secoes} />
      )}
    </div>
  )
}
