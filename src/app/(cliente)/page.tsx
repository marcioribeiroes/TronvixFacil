import Link from "next/link"
import { Clock, Star, Store, Tag } from "lucide-react"

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
export default async function PaginaInicial({ searchParams }: PageProps<"/">) {
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

  // No Next 16 searchParams chega como Promise.
  const parametros = await searchParams
  const categoriaEscolhida =
    typeof parametros.categoria === "string" ? parametros.categoria : null
  const somentePromocoes = parametros.promocoes === "1"

  const supabase = await criarClienteDoServidor()

  // Quem está na categoria escolhida, em duas etapas de propósito: o cliente
  // tipado do Supabase infere as colunas de um select LITERAL, e um ternário
  // dentro dele apaga a inferência — a consulta inteira vira ParserError e o
  // TypeScript perde o tipo do resultado.
  let idsDaCategoria: string[] | null = null
  if (categoriaEscolhida) {
    const { data } = await supabase
      .from("restaurant_platform_categories")
      .select("restaurant_id, platform_categories!inner(slug)")
      .eq("platform_categories.slug", categoriaEscolhida)

    idsDaCategoria = (data ?? []).map((v) => v.restaurant_id)
  }

  let consulta = supabase
    .from("restaurants")
    .select(
      "id, slug, name, description, logo_url, rating_avg, rating_count, delivery_fee_cents, avg_prep_minutes, avg_delivery_minutes, is_open, aberto_agora, tem_promocao",
    )
    .eq("status", "approved")
    .is("deleted_at", null)

  if (idsDaCategoria !== null) {
    consulta = consulta.in("id", idsDaCategoria)
  }
  if (somentePromocoes) {
    consulta = consulta.eq("tem_promocao", true)
  }

  const [{ data: categorias }, { data: restaurantes }] = await Promise.all([
    supabase
      .from("platform_categories")
      .select("id, slug, name")
      .eq("is_active", true)
      .order("position"),
    // Loja aberta na frente: ordenar só por nota põe o melhor restaurante da
    // cidade, fechado, no topo da tela de quem quer comer agora.
    consulta.order("is_open", { ascending: false }).order("rating_avg", { ascending: false }).limit(20),
  ])

  return (
    <div className="space-y-8 py-2">
      {/* Os filtros levavam a /categoria/<slug>, uma rota que nunca existiu:
          todo clique dava 404. Agora recortam a própria vitrine pela query
          string, que é uma tela a menos e um endereço que dá para mandar por
          mensagem. */}
      <section aria-labelledby="titulo-filtros">
        <h2 id="titulo-filtros" className="sr-only">
          Filtros
        </h2>
        <ul className="rolagem-invisivel flex gap-2 overflow-x-auto pb-1">
          <li>
            <Link href="/" className={aparenciaDoFiltro(!categoriaEscolhida && !somentePromocoes)}>
              Tudo
            </Link>
          </li>
          <li>
            <Link
              href={somentePromocoes ? "/" : "/?promocoes=1"}
              className={aparenciaDoFiltro(somentePromocoes)}
            >
              <Tag className="size-3.5" aria-hidden="true" />
              Promoções
            </Link>
          </li>
          {(categorias ?? []).map((categoria) => (
            <li key={categoria.id}>
              <Link
                href={
                  categoriaEscolhida === categoria.slug
                    ? "/"
                    : `/?categoria=${categoria.slug}`
                }
                className={aparenciaDoFiltro(categoriaEscolhida === categoria.slug)}
              >
                {categoria.name}
              </Link>
            </li>
          ))}
        </ul>
      </section>

      <section aria-labelledby="titulo-restaurantes">
        <h2 id="titulo-restaurantes" className="text-lg font-bold tracking-tight">
          {somentePromocoes ? "Com promoção agora" : "Restaurantes"}
        </h2>

        {!restaurantes || restaurantes.length === 0 ? (
          <div className="mt-4 rounded-lg border border-dashed p-10 text-center">
            <Store className="mx-auto size-8 text-muted-foreground" aria-hidden="true" />
            <p className="mt-3 font-medium">
              {somentePromocoes
                ? "Nenhuma promoção agora"
                : categoriaEscolhida
                  ? "Nada nesta categoria"
                  : "Nenhum estabelecimento por aqui ainda"}
            </p>
            <p className="mt-1 text-sm text-muted-foreground">
              {somentePromocoes || categoriaEscolhida ? (
                <Link href="/" className="font-semibold text-marca hover:underline">
                  Ver todos os restaurantes
                </Link>
              ) : (
                "Assim que um restaurante for aprovado, ele aparece nesta lista."
              )}
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
                      {restaurante.tem_promocao ? (
                        <Badge className="shrink-0 text-[10px]">Promoção</Badge>
                      ) : null}
                      {restaurante.aberto_agora ? null : (
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

/** A aparência de um filtro, ligado ou desligado. */
function aparenciaDoFiltro(ligado: boolean) {
  return [
    "inline-flex shrink-0 items-center gap-1.5 whitespace-nowrap rounded-full border px-4 py-2 text-sm font-medium transition-colors",
    ligado ? "border-marca bg-marca-suave text-marca-forte" : "hover:bg-muted",
  ].join(" ")
}
