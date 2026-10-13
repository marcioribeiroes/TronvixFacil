import "server-only"

import type { Grupo, Secao } from "@/components/pedido/cardapio-para-escolher"
import { criarClienteDoServidor } from "@/lib/supabase/servidor"

/**
 * O cardapio de uma loja, no formato da escolha de produto.
 *
 * A vitrine do cliente, a edicao do pedido no balcao e o "pedir mais" da mesa
 * leem daqui. Tres consultas iguais espalhadas virariam tres cardapios
 * diferentes no primeiro ajuste.
 */
export async function carregarCardapio(
  restauranteId: string,
): Promise<{ secoes: Secao[]; grupos: Grupo[] }> {
  const supabase = await criarClienteDoServidor()

  const [{ data: categorias }, { data: produtos }, { data: grupos }] = await Promise.all([
    supabase
      .from("categories")
      .select("id, name")
      .eq("restaurant_id", restauranteId)
      .eq("is_active", true)
      .is("deleted_at", null)
      .order("position"),
    supabase
      .from("products")
      .select(
        "id, category_id, name, description, image_url, price_cents, promo_price_cents, promo_starts_at, promo_ends_at, is_available, track_stock, stock_quantity",
      )
      .eq("restaurant_id", restauranteId)
      .is("deleted_at", null)
      .order("position"),
    supabase
      .from("addon_groups")
      .select(
        "id, product_id, name, is_required, min_select, max_select, addons(id, name, price_cents, is_available, deleted_at)",
      )
      .eq("restaurant_id", restauranteId)
      .eq("is_active", true)
      .is("deleted_at", null)
      .order("position"),
  ])

  return {
    secoes: (categorias ?? [])
      .map((c) => ({
        id: c.id,
        nome: c.name,
        produtos: (produtos ?? []).filter((p) => p.category_id === c.id),
      }))
      .filter((s) => s.produtos.length > 0),
    grupos: (grupos ?? []).map((g) => ({
      id: g.id,
      produtoId: g.product_id,
      nome: g.name,
      obrigatorio: g.is_required,
      minimo: g.min_select,
      maximo: g.max_select,
      adicionais: (g.addons ?? [])
        .filter((a) => a.deleted_at === null && a.is_available)
        .map((a) => ({ id: a.id, nome: a.name, precoCentavos: a.price_cents })),
    })),
  }
}
