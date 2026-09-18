import type { Metadata } from "next"
import Link from "next/link"

import { formatarReais } from "@/lib/dinheiro"
import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirGestao } from "@/modules/auth/sessao"

export const metadata: Metadata = { title: "Promoções" }

/**
 * As promocoes da loja, num lugar so.
 *
 * O preco promocional se edita no produto, e nao aqui - duplicar o editor
 * criaria dois caminhos para o mesmo campo e, com eles, a chance de divergir.
 * Esta tela e a visao que o produto sozinho nao da: o que esta valendo agora,
 * o que vence hoje, e o que ja venceu e ninguem percebeu.
 */

function quandoVence(iso: string | null) {
  if (!iso) return { texto: "sem prazo", urgente: false, vencida: false }
  const fim = new Date(iso)
  const horas = (fim.getTime() - Date.now()) / 3_600_000
  if (horas < 0) return { texto: "vencida", urgente: false, vencida: true }
  if (horas < 24) return { texto: `vence em ${Math.max(1, Math.round(horas))}h`, urgente: true, vencida: false }
  return {
    texto: `até ${fim.toLocaleDateString("pt-BR", { day: "2-digit", month: "2-digit" })}`,
    urgente: false,
    vencida: false,
  }
}

export default async function PromocoesDoRestaurante() {
  const { vinculo } = await exigirGestao()
  const supabase = await criarClienteDoServidor()

  const [{ data: produtos }, { data: cupons }] = await Promise.all([
    supabase
      .from("products")
      .select("id, name, price_cents, promo_price_cents, promo_ends_at, is_available, sold_count")
      .eq("restaurant_id", vinculo.restauranteId)
      .not("promo_price_cents", "is", null)
      .is("deleted_at", null)
      .order("promo_ends_at", { nullsFirst: false }),
    // Cupom e da plataforma, mas pode ser amarrado a uma loja. O dono ve os
    // que valem para ele; criar continua sendo da plataforma, porque quem
    // paga o desconto de um cupom geral e ela.
    supabase
      .from("coupons")
      .select("code, description, discount, value, min_order_cents, ends_at, is_active, restaurant_id")
      .or(`restaurant_id.eq.${vinculo.restauranteId},restaurant_id.is.null`)
      .eq("is_active", true),
  ])

  const lista = produtos ?? []
  const valendo = lista.filter((p) => !quandoVence(p.promo_ends_at).vencida)
  const vencidas = lista.filter((p) => quandoVence(p.promo_ends_at).vencida)

  return (
    <div className="space-y-8">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold tracking-tight">Promoções</h1>
          <p className="mt-1 text-sm text-muted-foreground">
            O preço promocional fica no produto. Aqui você vê tudo junto.
          </p>
        </div>
        <Link
          href="/painel/produtos"
          className="rounded-md bg-marca px-4 py-2 text-sm font-semibold text-white transition-colors hover:bg-marca-forte"
        >
          Criar promoção num produto
        </Link>
      </div>

      <section>
        <h2 className="text-sm font-bold uppercase tracking-wide text-muted-foreground">
          Valendo agora
        </h2>
        <ul className="mt-2 divide-y rounded-xl border bg-card">
          {valendo.map((p) => {
            const prazo = quandoVence(p.promo_ends_at)
            const desconto = Math.round(
              ((p.price_cents - p.promo_price_cents!) / p.price_cents) * 100,
            )
            return (
              <li key={p.id} className="flex flex-wrap items-center gap-x-3 gap-y-1 p-3 text-sm">
                <span className="min-w-0 flex-1 truncate font-medium">{p.name}</span>
                {!p.is_available ? (
                  <span className="shrink-0 rounded-md bg-muted px-2 py-0.5 text-xs font-semibold text-muted-foreground">
                    indisponível
                  </span>
                ) : null}
                <span
                  className={`shrink-0 rounded-md px-2 py-0.5 text-xs font-semibold ${
                    prazo.urgente
                      ? "bg-amber-100 text-amber-800 dark:bg-amber-950 dark:text-amber-300"
                      : "bg-muted text-muted-foreground"
                  }`}
                >
                  {prazo.texto}
                </span>
                <span className="shrink-0 text-xs text-muted-foreground line-through">
                  {formatarReais(p.price_cents)}
                </span>
                <span className="shrink-0 font-bold text-marca">
                  {formatarReais(p.promo_price_cents!)}
                </span>
                <span className="shrink-0 text-xs font-semibold text-emerald-600">
                  −{desconto}%
                </span>
              </li>
            )
          })}
          {valendo.length === 0 ? (
            <li className="p-4 text-sm text-muted-foreground">
              Nenhuma promoção no ar. Um preço promocional com prazo puxa pedido em dia parado.
            </li>
          ) : null}
        </ul>
      </section>

      {vencidas.length > 0 ? (
        <section>
          <h2 className="text-sm font-bold uppercase tracking-wide text-muted-foreground">
            Vencidas
          </h2>
          <p className="mt-1 text-xs text-muted-foreground">
            O produto já voltou ao preço cheio sozinho. Limpar aqui é só arrumação.
          </p>
          <ul className="mt-2 divide-y rounded-xl border bg-card">
            {vencidas.map((p) => (
              <li key={p.id} className="flex items-center gap-3 p-3 text-sm">
                <span className="min-w-0 flex-1 truncate text-muted-foreground">{p.name}</span>
                <span className="shrink-0 font-bold">{formatarReais(p.price_cents)}</span>
              </li>
            ))}
          </ul>
        </section>
      ) : null}

      <section>
        <h2 className="text-sm font-bold uppercase tracking-wide text-muted-foreground">
          Cupons que valem nesta loja
        </h2>
        <ul className="mt-2 divide-y rounded-xl border bg-card">
          {(cupons ?? []).map((c) => (
            <li key={c.code} className="flex flex-wrap items-center gap-x-3 gap-y-1 p-3 text-sm">
              <span className="shrink-0 rounded-md bg-muted px-2 py-1 font-mono text-xs font-bold">
                {c.code}
              </span>
              <span className="min-w-0 flex-1 truncate text-muted-foreground">
                {c.description ?? "—"}
              </span>
              <span className="shrink-0 text-xs text-muted-foreground">
                {c.restaurant_id === null ? "da plataforma" : "só desta loja"}
              </span>
              <span className="shrink-0 font-bold">
                {c.discount === "percentage"
                  ? `${(c.value / 100).toFixed(0)}%`
                  : c.discount === "fixed"
                    ? formatarReais(c.value)
                    : "frete grátis"}
              </span>
            </li>
          ))}
          {(cupons ?? []).length === 0 ? (
            <li className="p-4 text-sm text-muted-foreground">
              Nenhum cupom ativo. Quem cria cupom é a plataforma.
            </li>
          ) : null}
        </ul>
      </section>
    </div>
  )
}
