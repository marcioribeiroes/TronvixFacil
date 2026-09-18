import type { Metadata } from "next"

import { GruposDeAdicionais } from "@/components/painel/grupos-de-adicionais"
import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirGestao } from "@/modules/auth/sessao"

export const metadata: Metadata = { title: "Adicionais" }

/**
 * Os grupos de adicionais, por produto.
 *
 * As regras (obrigatorio, minimo, maximo) valem de verdade: e
 * `public.fechar_pedido` que as exige na hora de fechar, no banco. A tela
 * ajusta o que seria recusado la — grupo obrigatorio com minimo zero, por
 * exemplo — em vez de deixar o cadastro falhar depois.
 */
export default async function PaginaDeAdicionais() {
  const { vinculo } = await exigirGestao()
  const supabase = await criarClienteDoServidor()

  const [{ data: produtos }, { data: grupos }] = await Promise.all([
    supabase
      .from("products")
      .select("id, name, category_id, categories(name)")
      .eq("restaurant_id", vinculo.restauranteId)
      .is("deleted_at", null)
      .order("position"),
    supabase
      .from("addon_groups")
      .select("id, product_id, name, is_required, min_select, max_select, addons(id, name, price_cents, is_available, deleted_at)")
      .eq("restaurant_id", vinculo.restauranteId)
      .is("deleted_at", null)
      .order("position"),
  ])

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">Adicionais</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          O que o cliente escolhe junto do produto — ponto da carne, extras,
          tamanho.
        </p>
      </div>

      <GruposDeAdicionais
        produtos={(produtos ?? []).map((p) => ({
          id: p.id,
          nome: p.name,
          secao: p.categories?.name ?? "",
        }))}
        grupos={(grupos ?? []).map((g) => ({
          id: g.id,
          produtoId: g.product_id,
          nome: g.name,
          obrigatorio: g.is_required,
          minimo: g.min_select,
          maximo: g.max_select,
          adicionais: (g.addons ?? [])
            .filter((a) => a.deleted_at === null)
            .map((a) => ({
              id: a.id,
              nome: a.name,
              precoCentavos: a.price_cents,
            })),
        }))}
      />
    </div>
  )
}
