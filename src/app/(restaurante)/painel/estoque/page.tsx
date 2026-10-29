import type { Metadata } from "next"
import Link from "next/link"

import { EntradaDeEstoque } from "@/components/painel/entrada-de-estoque"
import {
  IngredientesDoEstoque,
  type IngredienteDoEstoque,
} from "@/components/painel/ingredientes-do-estoque"
import { FichaTecnica, MovimentoDeIngredientes } from "@/components/painel/movimento-de-ingredientes"
import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirGestao } from "@/modules/auth/sessao"
import { emQuantidade } from "@/modules/painel/unidades"

export const metadata: Metadata = { title: "Estoque" }

/**
 * O estoque, em quatro abas:
 *
 *   Produtos        a mercadoria vendavel que chegou (lata, porcao)
 *   Ingredientes    o cadastro da cozinha, o saldo e a entrada
 *   Saida           a saida avulsa e o livro de tudo que saiu - do preparo,
 *                   do pedido pronto e a mao
 *   Ficha tecnica   quanto cada produto gasta, para o pedido pronto dar baixa
 *
 * A aba vive na URL (?aba=), como os filtros da cozinha: o link leva direto.
 *
 * Na aba Produtos: le o codigo de barras de cada embalagem (ou procura pelo nome), confere as
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

async function AbaDeProdutos({ restauranteId }: { restauranteId: string }) {
  const supabase = await criarClienteDoServidor()

  const [{ data: produtos }, { data: entradas }] = await Promise.all([
    supabase
      .from("products")
      .select("id, name, barcode, track_stock, stock_quantity")
      .eq("restaurant_id", restauranteId)
      .is("deleted_at", null)
      .order("name"),
    supabase
      .from("stock_movements")
      .select("id, quantity, balance_after, reason, created_at, products(name), profiles(full_name)")
      .eq("restaurant_id", restauranteId)
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
      <p className="text-sm text-muted-foreground">
        Leia o código de barras de cada produto que chegou, confira as quantidades e confirme.
      </p>

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

const ABAS = [
  { chave: "produtos", rotulo: "Produtos" },
  { chave: "ingredientes", rotulo: "Ingredientes" },
  { chave: "saida", rotulo: "Saída" },
  { chave: "ficha", rotulo: "Ficha técnica" },
] as const

type Aba = (typeof ABAS)[number]["chave"]

const ORIGEM: Record<string, string> = {
  manual: "Avulsa",
  prep: "Preparo",
  order: "Pedido pronto",
}

async function lerIngredientes(restauranteId: string): Promise<IngredienteDoEstoque[]> {
  const supabase = await criarClienteDoServidor()
  const { data } = await supabase
    .from("ingredients")
    .select("id, name, unit, stock_quantity")
    .eq("restaurant_id", restauranteId)
    .is("deleted_at", null)
    .order("name")
  return (data ?? []).map((i) => ({
    id: i.id,
    nome: i.name,
    unidade: i.unit,
    saldo: Number(i.stock_quantity),
  }))
}

/** O livro de ingredientes, de um lado so: o que entrou, ou o que saiu. */
async function Livro({ restauranteId, tipo }: { restauranteId: string; tipo: "in" | "out" }) {
  const supabase = await criarClienteDoServidor()
  const { data: linhas } = await supabase
    .from("ingredient_movements")
    .select(
      "id, source, quantity, balance_after, reason, created_at, ingredients(name, unit), profiles(full_name)",
    )
    .eq("restaurant_id", restauranteId)
    .eq("kind", tipo)
    .order("created_at", { ascending: false })
    .limit(50)

  return (
    <section>
      <h2 className="text-sm font-bold uppercase tracking-wide text-muted-foreground">
        {tipo === "in" ? "Últimas entradas de ingredientes" : "Últimas saídas"}
      </h2>
      {(linhas ?? []).length === 0 ? (
        <p className="mt-2 text-sm text-muted-foreground">Nada lançado ainda.</p>
      ) : (
        <ul className="mt-2 divide-y rounded-xl border bg-card">
          {(linhas ?? []).map((m) => (
            <li key={m.id} className="flex flex-wrap items-center gap-x-3 gap-y-1 p-3 text-sm">
              <span className="min-w-0 flex-1">
                <span className="block truncate font-medium">
                  {m.ingredients?.name ?? "Ingrediente removido"}
                  {tipo === "out" ? (
                    <span className="ml-2 rounded-full bg-muted px-2 py-0.5 text-[11px] font-semibold text-muted-foreground">
                      {ORIGEM[m.source] ?? m.source}
                    </span>
                  ) : null}
                </span>
                <span className="block text-xs text-muted-foreground">
                  {quando(m.created_at)}
                  {m.profiles?.full_name ? ` · ${m.profiles.full_name}` : ""}
                  {m.reason ? ` · ${m.reason}` : ""}
                </span>
              </span>
              <span className="text-right">
                <span
                  className={`block font-bold ${tipo === "in" ? "text-status-pronto" : "text-destructive"}`}
                >
                  {tipo === "in" ? "+" : "−"}
                  {emQuantidade(Number(m.quantity), m.ingredients?.unit)}
                </span>
                <span
                  className={`block text-xs ${Number(m.balance_after) < 0 ? "font-semibold text-destructive" : "text-muted-foreground"}`}
                >
                  ficou {emQuantidade(Number(m.balance_after))}
                </span>
              </span>
            </li>
          ))}
        </ul>
      )}
    </section>
  )
}

async function AbaDeIngredientes({ restauranteId }: { restauranteId: string }) {
  const ingredientes = await lerIngredientes(restauranteId)
  return (
    <div className="space-y-8">
      <p className="text-sm text-muted-foreground">
        O que a cozinha usa, medido em quilo, litro ou unidade. Os preparos e os pedidos
        prontos dão baixa daqui sozinhos.
      </p>
      <IngredientesDoEstoque ingredientes={ingredientes} />
      <MovimentoDeIngredientes tipo="in" ingredientes={ingredientes} />
      <Livro restauranteId={restauranteId} tipo="in" />
    </div>
  )
}

async function AbaDeSaida({ restauranteId }: { restauranteId: string }) {
  const ingredientes = await lerIngredientes(restauranteId)
  return (
    <div className="space-y-8">
      <p className="text-sm text-muted-foreground">
        A saída acontece de três jeitos: o <strong>preparo</strong> lançado na Cozinha gasta
        os ingredientes dele; o <strong>pedido</strong> que fica pronto gasta a ficha técnica
        de cada produto; e a <strong>saída avulsa</strong>, aqui embaixo, cobre o resto — perda,
        vencido, consumo da equipe.
      </p>
      <MovimentoDeIngredientes tipo="out" ingredientes={ingredientes} />
      <Livro restauranteId={restauranteId} tipo="out" />
    </div>
  )
}

async function AbaDaFicha({
  restauranteId,
  produtoId,
}: {
  restauranteId: string
  produtoId: string | undefined
}) {
  const supabase = await criarClienteDoServidor()
  const [ingredientes, { data: produtos }, { data: fichas }] = await Promise.all([
    lerIngredientes(restauranteId),
    supabase
      .from("products")
      .select("id, name")
      .eq("restaurant_id", restauranteId)
      .is("deleted_at", null)
      .order("name"),
    supabase
      .from("product_ingredients")
      .select("product_id, ingredient_id, quantity, products!inner(restaurant_id)")
      .eq("products.restaurant_id", restauranteId),
  ])

  const lista = produtos ?? []
  const comFicha = new Set((fichas ?? []).map((f) => f.product_id))
  const escolhido = lista.find((p) => p.id === produtoId)

  return (
    <div className="space-y-6">
      <p className="text-sm text-muted-foreground">
        Escolha um produto e diga quanto de cada ingrediente uma unidade gasta. Quando o
        pedido fica <strong>Pronto</strong>, a saída é lançada sozinha.
      </p>

      {ingredientes.length === 0 ? (
        <p className="rounded-xl border border-dashed p-6 text-center text-sm text-muted-foreground">
          Cadastre os ingredientes na aba Ingredientes antes de montar a ficha.
        </p>
      ) : (
        <div className="grid gap-6 lg:grid-cols-[18rem_1fr]">
          <nav aria-label="Produtos" className="max-h-[32rem] overflow-y-auto rounded-xl border bg-card">
            <ul className="divide-y">
              {lista.map((p) => (
                <li key={p.id}>
                  <Link
                    href={`/painel/estoque?aba=ficha&produto=${p.id}`}
                    aria-current={p.id === produtoId ? "page" : undefined}
                    className={`flex items-center justify-between gap-2 px-3 py-2.5 text-sm hover:bg-muted ${p.id === produtoId ? "bg-marca-suave font-semibold" : ""}`}
                  >
                    <span className="truncate">{p.name}</span>
                    {comFicha.has(p.id) ? (
                      <span className="shrink-0 text-[11px] font-semibold text-status-pronto">
                        com ficha
                      </span>
                    ) : null}
                  </Link>
                </li>
              ))}
            </ul>
          </nav>

          {escolhido ? (
            <FichaTecnica
              // A chave remonta o formulario ao trocar de produto: sem ela, as
              // linhas do produto anterior ficavam na tela do novo.
              key={escolhido.id}
              produto={{ id: escolhido.id, nome: escolhido.name }}
              ingredientes={ingredientes}
              atual={(fichas ?? [])
                .filter((f) => f.product_id === escolhido.id)
                .map((f) => ({
                  ingrediente: f.ingredient_id,
                  quantidade: String(f.quantity).replace(".", ","),
                }))}
            />
          ) : (
            <p className="rounded-xl border border-dashed p-6 text-center text-sm text-muted-foreground">
              Escolha um produto na lista.
            </p>
          )}
        </div>
      )}
    </div>
  )
}

export default async function PaginaDeEstoque({ searchParams }: PageProps<"/painel/estoque">) {
  const { vinculo } = await exigirGestao()
  const parametros = await searchParams
  const aba: Aba = ABAS.some((a) => a.chave === parametros.aba)
    ? (parametros.aba as Aba)
    : "produtos"
  const produtoId = typeof parametros.produto === "string" ? parametros.produto : undefined

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold tracking-tight">Estoque</h1>

      <nav aria-label="Abas do estoque" className="flex gap-1 overflow-x-auto border-b">
        {ABAS.map((a) => (
          <Link
            key={a.chave}
            href={a.chave === "produtos" ? "/painel/estoque" : `/painel/estoque?aba=${a.chave}`}
            aria-current={a.chave === aba ? "page" : undefined}
            className={`-mb-px shrink-0 border-b-2 px-4 py-2 text-sm font-semibold transition-colors ${
              a.chave === aba
                ? "border-marca text-foreground"
                : "border-transparent text-muted-foreground hover:text-foreground"
            }`}
          >
            {a.rotulo}
          </Link>
        ))}
      </nav>

      {aba === "produtos" ? <AbaDeProdutos restauranteId={vinculo.restauranteId} /> : null}
      {aba === "ingredientes" ? <AbaDeIngredientes restauranteId={vinculo.restauranteId} /> : null}
      {aba === "saida" ? <AbaDeSaida restauranteId={vinculo.restauranteId} /> : null}
      {aba === "ficha" ? (
        <AbaDaFicha restauranteId={vinculo.restauranteId} produtoId={produtoId} />
      ) : null}
    </div>
  )
}
