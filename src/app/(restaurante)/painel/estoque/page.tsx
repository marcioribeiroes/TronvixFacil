import type { Metadata } from "next"
import Link from "next/link"

import { EntradaDeEstoque } from "@/components/painel/entrada-de-estoque"
import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirGestao } from "@/modules/auth/sessao"

export const metadata: Metadata = { title: "Estoque" }

/**
 * A mercadoria que chegou.
 *
 * Le o codigo de barras de cada embalagem (ou procura pelo nome), confere as
 * quantidades e da entrada na nota inteira de uma vez. Embaixo, o que entrou
 * por ultimo - para quem recebeu conferir, e para quem chega depois saber.
 */

function quando(iso: string) {
  return new Date(iso).toLocaleString("pt-BR", {
    day: "2-digit",
    month: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    // O servidor roda em UTC; a loja, nao.
    timeZone: "America/Sao_Paulo",
  })
}

export default async function PaginaDeEstoque() {
  const { vinculo } = await exigirGestao()
  const supabase = await criarClienteDoServidor()

  const [{ data: produtos }, { data: entradas }] = await Promise.all([
    supabase
      .from("products")
      .select("id, name, barcode, track_stock, stock_quantity")
      .eq("restaurant_id", vinculo.restauranteId)
      .is("deleted_at", null)
      .order("name"),
    supabase
      .from("stock_movements")
      .select("id, quantity, balance_after, reason, created_at, products(name), profiles(full_name)")
      .eq("restaurant_id", vinculo.restauranteId)
      .eq("kind", "in")
      // Entrada com pedido e item que voltou de pedido editado, nao mercadoria.
      .is("order_id", null)
      .order("created_at", { ascending: false })
      .limit(30),
  ])

  const lista = produtos ?? []
  const semCodigo = lista.filter((p) => !p.barcode).length

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">Entrada de estoque</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Leia o código de barras de cada produto que chegou, confira as quantidades e
          confirme.
        </p>
      </div>

      {lista.length === 0 ? (
        <div className="rounded-xl border border-dashed p-10 text-center">
          <p className="font-semibold">Nenhum produto cadastrado</p>
          <Link
            href="/painel/produtos"
            className="mt-4 inline-flex h-10 items-center rounded-lg bg-marca px-5 text-sm font-semibold text-white transition-colors hover:bg-marca-forte"
          >
            Cadastrar produtos
          </Link>
        </div>
      ) : (
        <>
          {semCodigo > 0 ? (
            <p className="rounded-lg border bg-card px-4 py-3 text-sm text-muted-foreground">
              {semCodigo === lista.length
                ? "Nenhum produto tem código de barras ainda"
                : `${semCodigo} produto(s) ainda sem código de barras`}
              : dá para procurar pelo nome, ou cadastrar o código em{" "}
              <Link href="/painel/produtos" className="font-medium text-foreground underline">
                Produtos
              </Link>
              .
            </p>
          ) : null}

          <EntradaDeEstoque
            produtos={lista.map((p) => ({
              id: p.id,
              nome: p.name,
              codigoDeBarras: p.barcode,
              saldo: p.track_stock ? p.stock_quantity : 0,
              controlaEstoque: p.track_stock,
            }))}
          />
        </>
      )}

      <section>
        <h2 className="text-sm font-bold uppercase tracking-wide text-muted-foreground">
          Últimas entradas
        </h2>
        {(entradas ?? []).length === 0 ? (
          <p className="mt-2 text-sm text-muted-foreground">Nenhuma entrada registrada ainda.</p>
        ) : (
          <ul className="mt-2 divide-y rounded-xl border bg-card">
            {(entradas ?? []).map((e) => (
              <li key={e.id} className="flex flex-wrap items-center gap-x-3 gap-y-1 p-3 text-sm">
                <span className="min-w-0 flex-1">
                  <span className="block truncate font-medium">
                    {e.products?.name ?? "Produto removido"}
                  </span>
                  <span className="block text-xs text-muted-foreground">
                    {quando(e.created_at)}
                    {e.profiles?.full_name ? ` · ${e.profiles.full_name}` : ""}
                    {e.reason ? ` · ${e.reason}` : ""}
                  </span>
                </span>
                <span className="text-right">
                  <span className="block font-bold text-status-pronto">+{e.quantity}</span>
                  <span className="block text-xs text-muted-foreground">
                    ficou {e.balance_after}
                  </span>
                </span>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  )
}
