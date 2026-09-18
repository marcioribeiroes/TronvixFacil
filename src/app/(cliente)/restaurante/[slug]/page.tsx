import type { Metadata } from "next"
import { notFound } from "next/navigation"
import { Clock, Bike, ShoppingBasket, Star } from "lucide-react"

import { CardapioDoCliente } from "@/components/cliente/cardapio-do-cliente"
import { Badge } from "@/components/ui/badge"
import { formatarReais } from "@/lib/dinheiro"
import { criarClienteDoServidor } from "@/lib/supabase/servidor"

export async function generateMetadata({
  params,
}: PageProps<"/restaurante/[slug]">): Promise<Metadata> {
  const { slug } = await params
  return { title: slug }
}

export default async function PaginaDoRestaurante({
  params,
}: PageProps<"/restaurante/[slug]">) {
  const { slug } = await params
  const supabase = await criarClienteDoServidor()

  const { data: restaurante } = await supabase
    .from("restaurants")
    .select(
      "id, slug, name, description, logo_url, cover_url, is_open, aberto_agora, rating_avg, rating_count, delivery_fee_cents, free_delivery_above_cents, min_order_cents, avg_prep_minutes, avg_delivery_minutes",
    )
    .eq("slug", slug)
    .eq("status", "approved")
    .is("deleted_at", null)
    .maybeSingle()

  // A RLS ja esconde quem nao esta aprovado; 404 e a resposta honesta para um
  // endereco que o publico nao deve enxergar.
  if (!restaurante) notFound()

  const [{ data: categorias }, { data: produtos }, { data: grupos }] = await Promise.all([
    supabase
      .from("categories")
      .select("id, name")
      .eq("restaurant_id", restaurante.id)
      .eq("is_active", true)
      .is("deleted_at", null)
      .order("position"),
    supabase
      .from("products")
      .select(
        "id, category_id, name, description, image_url, price_cents, promo_price_cents, promo_starts_at, promo_ends_at, is_available, track_stock, stock_quantity",
      )
      .eq("restaurant_id", restaurante.id)
      .is("deleted_at", null)
      .order("position"),
    supabase
      .from("addon_groups")
      .select(
        "id, product_id, name, is_required, min_select, max_select, addons(id, name, price_cents, is_available, deleted_at)",
      )
      .eq("restaurant_id", restaurante.id)
      .eq("is_active", true)
      .is("deleted_at", null)
      .order("position"),
  ])

  const entrega = restaurante.avg_prep_minutes + restaurante.avg_delivery_minutes

  return (
    <div className="mx-auto max-w-4xl px-4 py-6">
      <header className="flex flex-wrap items-start gap-4">
        <div className="size-16 shrink-0 overflow-hidden rounded-xl bg-muted">
          {restaurante.logo_url ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={restaurante.logo_url} alt="" className="size-full object-cover" />
          ) : null}
        </div>

        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-2">
            <h1 className="text-2xl font-bold tracking-tight">{restaurante.name}</h1>
            {restaurante.aberto_agora ? null : <Badge variant="secondary">Fechado</Badge>}
          </div>
          {restaurante.description ? (
            <p className="mt-1 text-muted-foreground">{restaurante.description}</p>
          ) : null}

          <ul className="mt-3 flex flex-wrap gap-x-5 gap-y-1 text-sm text-muted-foreground">
            {restaurante.rating_count > 0 ? (
              <li className="inline-flex items-center gap-1.5">
                <Star className="size-4 text-status-pronto" aria-hidden="true" />
                {restaurante.rating_avg.toFixed(1)} ({restaurante.rating_count})
              </li>
            ) : null}
            <li className="inline-flex items-center gap-1.5">
              <Clock className="size-4" aria-hidden="true" />
              {entrega}–{entrega + 20} min
            </li>
            <li className="inline-flex items-center gap-1.5">
              <Bike className="size-4" aria-hidden="true" />
              {restaurante.delivery_fee_cents === 0
                ? "Entrega grátis"
                : formatarReais(restaurante.delivery_fee_cents)}
            </li>
            {restaurante.min_order_cents > 0 ? (
              <li className="inline-flex items-center gap-1.5">
                <ShoppingBasket className="size-4" aria-hidden="true" />
                Mínimo {formatarReais(restaurante.min_order_cents)}
              </li>
            ) : null}
          </ul>

          {restaurante.free_delivery_above_cents ? (
            <p className="mt-2 text-sm font-semibold text-status-pronto">
              Entrega grátis acima de {formatarReais(restaurante.free_delivery_above_cents)}
            </p>
          ) : null}
        </div>
      </header>

      {restaurante.aberto_agora ? null : (
        <p className="mt-5 rounded-lg bg-marca-suave px-4 py-3 text-sm text-marca-forte">
          Fechado agora. Você pode olhar o cardápio, mas o pedido só sai quando abrir —
          é o banco que recusa, não a tela.
        </p>
      )}

      <div className="mt-8">
        <CardapioDoCliente
          restauranteId={restaurante.id}
          aberto={restaurante.aberto_agora ?? false}
          secoes={(categorias ?? [])
            .map((c) => ({
              id: c.id,
              nome: c.name,
              produtos: (produtos ?? []).filter((p) => p.category_id === c.id),
            }))
            .filter((s) => s.produtos.length > 0)}
          grupos={(grupos ?? []).map((g) => ({
            id: g.id,
            produtoId: g.product_id,
            nome: g.name,
            obrigatorio: g.is_required,
            minimo: g.min_select,
            maximo: g.max_select,
            adicionais: (g.addons ?? [])
              .filter((a) => a.deleted_at === null && a.is_available)
              .map((a) => ({ id: a.id, nome: a.name, precoCentavos: a.price_cents })),
          }))}
        />
      </div>
    </div>
  )
}
