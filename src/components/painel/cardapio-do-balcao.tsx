"use client"

import { useState, useTransition } from "react"

import { Badge } from "@/components/ui/badge"
import { formatarReais } from "@/lib/dinheiro"
import { mudarDisponibilidade } from "@/modules/painel/cardapio"

type Produto = {
  id: string
  name: string
  description: string | null
  price_cents: number
  promo_price_cents: number | null
  promo_ends_at: string | null
  is_available: boolean
  track_stock: boolean
  stock_quantity: number
}

export function CardapioDoBalcao({
  secoes,
}: {
  secoes: { id: string; nome: string; produtos: Produto[] }[]
}) {
  const [enviando, iniciar] = useTransition()
  const [erro, setErro] = useState<string | null>(null)

  const foraDoAr = secoes.flatMap((s) => s.produtos).filter((p) => !p.is_available).length

  return (
    <div className="space-y-6">
      {foraDoAr > 0 ? (
        <p className="rounded-lg bg-marca-suave px-4 py-2.5 text-sm text-marca-forte">
          {foraDoAr} item(ns) fora do ar. O cliente não os vê no aplicativo.
        </p>
      ) : null}

      {erro ? (
        <p role="alert" className="text-sm font-medium text-destructive">
          {erro}
        </p>
      ) : null}

      {secoes.map((s) => (
        <section key={s.id}>
          <h2 className="text-sm font-bold uppercase tracking-wide text-muted-foreground">
            {s.nome}
          </h2>
          <ul className="mt-2 divide-y rounded-xl border bg-card">
            {s.produtos.map((p) => {
              const promoValendo =
                p.promo_price_cents !== null &&
                (!p.promo_ends_at || new Date(p.promo_ends_at) > new Date())
              const esgotado = p.track_stock && p.stock_quantity <= 0

              return (
                <li
                  key={p.id}
                  className={`flex items-center gap-3 p-4 ${p.is_available ? "" : "opacity-55"}`}
                >
                  <div className="min-w-0 flex-1">
                    <div className="flex flex-wrap items-center gap-2">
                      <span className="font-semibold">{p.name}</span>
                      {esgotado ? <Badge variant="destructive">Sem estoque</Badge> : null}
                      {promoValendo ? <Badge>Promoção</Badge> : null}
                    </div>
                    {p.description ? (
                      <p className="line-clamp-1 text-sm text-muted-foreground">
                        {p.description}
                      </p>
                    ) : null}
                    <p className="mt-0.5 text-sm font-semibold">
                      {formatarReais(
                        promoValendo ? p.promo_price_cents! : p.price_cents,
                      )}
                    </p>
                  </div>

                  <label className="flex shrink-0 cursor-pointer items-center gap-2 text-sm">
                    <input
                      type="checkbox"
                      checked={p.is_available}
                      disabled={enviando}
                      className="size-4 accent-marca"
                      onChange={(e) =>
                        iniciar(async () => {
                          const r = await mudarDisponibilidade(p.id, e.target.checked)
                          if (!r.ok) setErro(r.erro)
                        })
                      }
                    />
                    {p.is_available ? "No ar" : "Fora do ar"}
                  </label>
                </li>
              )
            })}
          </ul>
        </section>
      ))}
    </div>
  )
}
