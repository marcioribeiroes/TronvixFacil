import Link from "next/link"
import { Clock, Star, Store } from "lucide-react"

import { AvisoDeConfiguracao } from "@/components/aviso-de-configuracao"
import { Badge } from "@/components/ui/badge"
import { supabaseConfigurado } from "@/lib/ambiente"
import { formatarReais } from "@/lib/dinheiro"
import { criarClienteDoServidor } from "@/lib/supabase/servidor"

/**
 * Home do aplicativo do cliente.
 *
 * Esta pagina ja le o banco de verdade: categorias e estabelecimentos
 * aprovados vem pelo cliente anonimo, atravessando as politicas de RLS. E o
 * teste de ponta a ponta da fundacao - se a vitrine aparece sem login, a
 * politica "vitrine publica de restaurantes aprovados" esta no ar.
 *
 * A vitrine completa (busca, filtros, ofertas, mais vendidos) entra na Etapa 2.
 */
export default async function PaginaInicial() {
  if (!supabaseConfigurado()) {
    return (
      <div className="space-y-6 py-6">
        <div>
          <h1 className="text-2xl font-bold tracking-tight">Bem-vindo ao Tronvix Fácil</h1>
          <p className="mt-1 text-muted-foreground">
            Falta um passo para a vitrine carregar.
          </p>
        </div>
        <AvisoDeConfiguracao />
      </div>
    )
  }

  const supabase = await criarClienteDoServidor()

  const [{ data: categorias }, { data: restaurantes }] = await Promise.all([
    supabase
      .from("platform_categories")
      .select("id, slug, name")
      .eq("is_active", true)
      .order("position"),
    supabase
      .from("restaurants")
      .select(
        "id, slug, name, description, logo_url, rating_avg, rating_count, delivery_fee_cents, avg_prep_minutes, avg_delivery_minutes, is_open",
      )
      .eq("status", "approved")
      .is("deleted_at", null)
      .order("rating_avg", { ascending: false })
      .limit(20),
  ])

  return (
    <div className="space-y-8 py-2">
      {categorias && categorias.length > 0 ? (
        <section aria-labelledby="titulo-categorias">
          <h2 id="titulo-categorias" className="sr-only">
            Categorias
          </h2>
          <ul className="rolagem-invisivel flex gap-3 overflow-x-auto pb-1">
            {categorias.map((categoria) => (
              <li key={categoria.id}>
                <Link
                  href={`/categoria/${categoria.slug}`}
                  className="flex w-20 flex-col items-center gap-2 rounded-lg p-2 transition-colors hover:bg-muted"
                >
                  <span className="grid size-14 place-items-center rounded-full bg-marca-suave text-marca">
                    <Store className="size-6" aria-hidden="true" />
                  </span>
                  <span className="text-center text-xs font-medium leading-tight">
                    {categoria.name}
                  </span>
                </Link>
              </li>
            ))}
          </ul>
        </section>
      ) : null}

      <section aria-labelledby="titulo-restaurantes">
        <h2 id="titulo-restaurantes" className="text-lg font-bold tracking-tight">
          Restaurantes
        </h2>

        {!restaurantes || restaurantes.length === 0 ? (
          <div className="mt-4 rounded-lg border border-dashed p-10 text-center">
            <Store className="mx-auto size-8 text-muted-foreground" aria-hidden="true" />
            <p className="mt-3 font-medium">Nenhum estabelecimento por aqui ainda</p>
            <p className="mt-1 text-sm text-muted-foreground">
              Assim que um restaurante for aprovado, ele aparece nesta lista.
            </p>
          </div>
        ) : (
          <ul className="mt-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
            {restaurantes.map((restaurante) => (
              <li key={restaurante.id}>
                <Link
                  href={`/restaurante/${restaurante.slug}`}
                  className="flex h-full gap-3 rounded-xl border bg-card p-3 transition-shadow hover:shadow-md"
                >
                  <span className="grid size-16 shrink-0 place-items-center overflow-hidden rounded-lg bg-muted">
                    {restaurante.logo_url ? (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img
                        src={restaurante.logo_url}
                        alt=""
                        className="size-full object-cover"
                      />
                    ) : (
                      <Store className="size-6 text-muted-foreground" aria-hidden="true" />
                    )}
                  </span>

                  <span className="min-w-0 flex-1">
                    <span className="flex items-start justify-between gap-2">
                      <span className="truncate font-semibold">{restaurante.name}</span>
                      {restaurante.is_open ? null : (
                        <Badge variant="secondary" className="shrink-0 text-[10px]">
                          Fechado
                        </Badge>
                      )}
                    </span>

                    <span className="mt-0.5 flex flex-wrap items-center gap-x-2 gap-y-0.5 text-xs text-muted-foreground">
                      <span className="flex items-center gap-1">
                        <Star
                          className="size-3 fill-status-preparo text-status-preparo"
                          aria-hidden="true"
                        />
                        {restaurante.rating_count > 0
                          ? restaurante.rating_avg.toFixed(1)
                          : "Novo"}
                      </span>
                      <span aria-hidden="true">•</span>
                      <span className="flex items-center gap-1">
                        <Clock className="size-3" aria-hidden="true" />
                        {restaurante.avg_prep_minutes}–
                        {restaurante.avg_prep_minutes + restaurante.avg_delivery_minutes} min
                      </span>
                      <span aria-hidden="true">•</span>
                      <span>
                        {restaurante.delivery_fee_cents === 0
                          ? "Entrega grátis"
                          : formatarReais(restaurante.delivery_fee_cents)}
                      </span>
                    </span>

                    {restaurante.description ? (
                      <span className="mt-1 line-clamp-2 block text-xs text-muted-foreground">
                        {restaurante.description}
                      </span>
                    ) : null}
                  </span>
                </Link>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  )
}
