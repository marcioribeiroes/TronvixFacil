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
import { diaDeHoje, diaPorExtenso, diaValido, limitesDoDia } from "@/modules/pedidos/dia"
import { emQuantidade } from "@/modules/painel/unidades"

export const metadata: Metadata = { title: "Estoque" }

/**
 * O estoque, em cinco abas:
 *
 *   Produtos        a mercadoria vendavel que chegou (lata, porcao)
 *   Ingredientes    o cadastro da cozinha, o saldo e a entrada
 *   Saida           a saida avulsa e o livro de tudo que saiu - do preparo,
 *                   do pedido pronto e a mao
 *   Ficha tecnica   quanto cada produto gasta, para o pedido pronto dar baixa
 *   Movimentacao    o extrato de um periodo: tudo que entrou e saiu, de produto
 *                   e de ingrediente, na ordem do relogio
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
  { chave: "movimentacao", rotulo: "Movimentação" },
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

// ---------------------------------------------------------------------------
// Movimentacao
//
// As outras abas mostram cada uma o seu pedaco do livro. Esta junta os dois
// livros - produto e ingrediente - num extrato so, de um periodo, para responder
// "o que mexeu no estoque ontem?" sem abrir aba por aba.
// ---------------------------------------------------------------------------

/**
 * O que a movimentacao junta, e de onde cada coisa vem:
 *
 *   entrada   a mercadoria da aba Produtos e o ingrediente da aba Ingredientes
 *   pedido    a saida pelo pedido: o produto vendido (na hora do pedido) e o
 *             ingrediente da ficha tecnica (quando o pedido fica pronto)
 *   avulsa    a saida avulsa da aba Saida - perda, vencido, consumo da equipe
 *   preparo   o preparo lancado na Cozinha
 */
const TIPOS_DE_MOVIMENTO = [
  { chave: "todos", rotulo: "Tudo" },
  { chave: "in", rotulo: "Todas as entradas" },
  { chave: "out", rotulo: "Todas as saídas" },
  { chave: "entrada", rotulo: "Entrada de estoque" },
  { chave: "pedido", rotulo: "Saída pelo pedido" },
  { chave: "avulsa", rotulo: "Saída avulsa" },
  { chave: "preparo", rotulo: "Saída por preparo" },
] as const

const ITENS_DO_MOVIMENTO = [
  { chave: "todos", rotulo: "Produtos e ingredientes" },
  { chave: "produtos", rotulo: "Só produtos" },
  { chave: "ingredientes", rotulo: "Só ingredientes" },
] as const

/** Teto de linhas por livro numa consulta. Periodo longo de loja cheia passa disso. */
const LIMITE_DO_EXTRATO = 500

type TipoDeMovimento = (typeof TIPOS_DE_MOVIMENTO)[number]["chave"]
type ItemDoMovimento = (typeof ITENS_DO_MOVIMENTO)[number]["chave"]

/** Uma linha do extrato, venha de qual livro vier. */
type LinhaDoExtrato = {
  chave: string
  quando: string
  item: string
  deQue: "Produto" | "Ingrediente"
  tipo: "in" | "out" | "adjustment"
  origem: string
  quantidade: string
  saldo: string
  saldoNegativo: boolean
  quem: string | null
  motivo: string | null
}

/** "pedido nº 42", ou so "pedido" quando o numero nao veio. */
function doPedido(numero: number | null | undefined) {
  return numero ? `pedido nº ${numero}` : "pedido"
}

/**
 * De onde veio o movimento de produto. A tabela nao guarda a origem, entao se
 * deduz: entrada sem pedido e a da aba Produtos; com pedido, e o item que
 * voltou de um pedido editado. "adjustment" existe no tipo do banco mas nada
 * grava ainda; se um dia gravar, a linha aparece como "Ajuste" em vez de sumir.
 */
function origemDoProduto(tipo: string, numero: number | null | undefined, temPedido: boolean) {
  if (tipo === "adjustment") return "Ajuste"
  if (tipo === "in") {
    return temPedido ? `Volta do ${doPedido(numero)} editado` : "Entrada · aba Produtos"
  }
  return temPedido ? `Saída pelo ${doPedido(numero)}` : "Saída avulsa"
}

function origemDoIngrediente(tipo: string, fonte: string, numero: number | null | undefined) {
  if (tipo === "in") return "Entrada · aba Ingredientes"
  if (fonte === "order") return `Saída pelo ${doPedido(numero)}`
  if (fonte === "manual") return "Saída avulsa · aba Saída"
  if (fonte === "prep") return "Saída por preparo · Cozinha"
  return ORIGEM[fonte] ?? fonte
}

async function AbaDeMovimentacao({
  restauranteId,
  parametros,
}: {
  restauranteId: string
  parametros: Record<string, string | string[] | undefined>
}) {
  const supabase = await criarClienteDoServidor()

  const { data: loja } = await supabase
    .from("restaurants")
    .select("timezone")
    .eq("id", restauranteId)
    .single()
  const fuso = loja?.timezone ?? "America/Sao_Paulo"
  const hoje = diaDeHoje(fuso)
  // O periodo vai de `de` ate `ate`, os dois inclusive. `dia` sozinho ainda
  // vale, para o link antigo de um dia so continuar abrindo.
  const umDia = diaValido(parametros.dia) ? parametros.dia : undefined
  let de = diaValido(parametros.de) ? parametros.de : (umDia ?? hoje)
  let ate = diaValido(parametros.ate) ? parametros.ate : (umDia ?? de)
  // Trocados por engano: vira o periodo certo em vez de dar lista vazia.
  if (de > ate) [de, ate] = [ate, de]
  const tipo: TipoDeMovimento = TIPOS_DE_MOVIMENTO.some((t) => t.chave === parametros.tipo)
    ? (parametros.tipo as TipoDeMovimento)
    : "todos"
  const item: ItemDoMovimento = ITENS_DO_MOVIMENTO.some((i) => i.chave === parametros.item)
    ? (parametros.item as ItemDoMovimento)
    : "todos"
  const { inicio } = limitesDoDia(de, fuso)
  const { fim } = limitesDoDia(ate, fuso)
  const periodo =
    de === ate
      ? de === hoje
        ? "hoje"
        : `em ${diaPorExtenso(de)}`
      : `de ${diaPorExtenso(de)} a ${diaPorExtenso(ate)}`

  let produtos = supabase
    .from("stock_movements")
    .select(
      "id, kind, quantity, balance_after, order_id, reason, created_at, products(name), profiles(full_name), orders(number)",
    )
    .eq("restaurant_id", restauranteId)
    .gte("created_at", inicio)
    .lt("created_at", fim)
    .order("created_at", { ascending: false })
    .limit(LIMITE_DO_EXTRATO)
  let ingredientes = supabase
    .from("ingredient_movements")
    .select(
      "id, kind, source, quantity, balance_after, reason, created_at, ingredients(name, unit), profiles(full_name), orders(number)",
    )
    .eq("restaurant_id", restauranteId)
    .gte("created_at", inicio)
    .lt("created_at", fim)
    .order("created_at", { ascending: false })
    .limit(LIMITE_DO_EXTRATO)
  // O filtro vai para a consulta, e nao para depois dela: assim o teto de
  // linhas vale para o que foi pedido, e nao some nada que caberia.
  //
  // Produto so tem entrada (aba Produtos ou volta de pedido editado) e saida
  // pelo pedido. Avulsa e preparo sao so de ingrediente.
  let buscarProdutos = item !== "ingredientes"
  const buscarIngredientes = item !== "produtos"
  if (tipo === "in" || tipo === "out") {
    produtos = produtos.eq("kind", tipo)
    ingredientes = ingredientes.eq("kind", tipo)
  } else if (tipo === "entrada") {
    produtos = produtos.eq("kind", "in").is("order_id", null)
    ingredientes = ingredientes.eq("kind", "in")
  } else if (tipo === "pedido") {
    produtos = produtos.eq("kind", "out").not("order_id", "is", null)
    ingredientes = ingredientes.eq("kind", "out").eq("source", "order")
  } else if (tipo === "avulsa") {
    buscarProdutos = false
    ingredientes = ingredientes.eq("kind", "out").eq("source", "manual")
  } else if (tipo === "preparo") {
    buscarProdutos = false
    ingredientes = ingredientes.eq("kind", "out").eq("source", "prep")
  }

  const [{ data: deProdutos }, { data: deIngredientes }] = await Promise.all([
    buscarProdutos ? produtos : Promise.resolve({ data: [] }),
    buscarIngredientes ? ingredientes : Promise.resolve({ data: [] }),
  ])

  const linhas: LinhaDoExtrato[] = [
    ...(deProdutos ?? []).map((m) => ({
      chave: `p-${m.id}`,
      quando: m.created_at,
      item: m.products?.name ?? "Produto removido",
      deQue: "Produto" as const,
      tipo: m.kind,
      origem: origemDoProduto(m.kind, m.orders?.number, Boolean(m.order_id)),
      quantidade: String(Math.abs(m.quantity)),
      saldo: String(m.balance_after),
      saldoNegativo: m.balance_after < 0,
      quem: m.profiles?.full_name ?? null,
      motivo: m.reason,
    })),
    ...(deIngredientes ?? []).map((m) => ({
      chave: `i-${m.id}`,
      quando: m.created_at,
      item: m.ingredients?.name ?? "Ingrediente removido",
      deQue: "Ingrediente" as const,
      tipo: m.kind as LinhaDoExtrato["tipo"],
      origem: origemDoIngrediente(m.kind, m.source, m.orders?.number),
      quantidade: emQuantidade(Math.abs(Number(m.quantity)), m.ingredients?.unit),
      saldo: emQuantidade(Number(m.balance_after)),
      saldoNegativo: Number(m.balance_after) < 0,
      quem: m.profiles?.full_name ?? null,
      motivo: m.reason,
    })),
  ].sort((a, b) => b.quando.localeCompare(a.quando))

  // Bateu o teto em algum dos livros: os mais antigos do periodo ficaram de
  // fora, e a tela avisa em vez de fingir que mostrou tudo.
  const cortado =
    (deProdutos ?? []).length >= LIMITE_DO_EXTRATO ||
    (deIngredientes ?? []).length >= LIMITE_DO_EXTRATO

  const entradas = linhas.filter((l) => l.tipo === "in").length
  const saidas = linhas.filter((l) => l.tipo === "out").length

  return (
    <div className="space-y-6">
      <p className="text-sm text-muted-foreground">
        Tudo o que entrou e saiu do estoque {periodo}, do mais recente para o mais antigo:
        a <strong>entrada</strong> das abas Produtos e Ingredientes, a{" "}
        <strong>saída pelo pedido</strong>, a <strong>saída avulsa</strong> da aba Saída e o{" "}
        <strong>preparo</strong> lançado na Cozinha.
      </p>

      {/* Formulario GET: os filtros vao para a URL, e a aba vai junto. */}
      <form className="flex flex-wrap items-end gap-2">
        <input type="hidden" name="aba" value="movimentacao" />
        <label className="text-sm">
          <span className="block text-xs text-muted-foreground">De</span>
          <input
            type="date"
            name="de"
            defaultValue={de}
            max={hoje}
            className="h-9 rounded-lg border bg-background px-2 text-sm"
          />
        </label>
        <label className="text-sm">
          <span className="block text-xs text-muted-foreground">Até</span>
          <input
            type="date"
            name="ate"
            defaultValue={ate}
            max={hoje}
            className="h-9 rounded-lg border bg-background px-2 text-sm"
          />
        </label>
        <label className="text-sm">
          <span className="block text-xs text-muted-foreground">Movimento</span>
          <select
            name="tipo"
            defaultValue={tipo}
            className="h-9 rounded-lg border bg-background px-2 text-sm"
          >
            {TIPOS_DE_MOVIMENTO.map((t) => (
              <option key={t.chave} value={t.chave}>
                {t.rotulo}
              </option>
            ))}
          </select>
        </label>
        <label className="text-sm">
          <span className="block text-xs text-muted-foreground">Item</span>
          <select
            name="item"
            defaultValue={item}
            className="h-9 rounded-lg border bg-background px-2 text-sm"
          >
            {ITENS_DO_MOVIMENTO.map((i) => (
              <option key={i.chave} value={i.chave}>
                {i.rotulo}
              </option>
            ))}
          </select>
        </label>
        <button
          type="submit"
          className="h-9 rounded-lg border bg-background px-4 text-sm font-semibold hover:bg-muted"
        >
          Ver
        </button>
      </form>

      <dl className="grid grid-cols-2 gap-3 rounded-xl border bg-muted/40 p-4">
        <div>
          <dt className="text-xs font-semibold uppercase text-muted-foreground">Entradas</dt>
          <dd className="text-xl font-bold text-status-pronto">{entradas}</dd>
        </div>
        <div>
          <dt className="text-xs font-semibold uppercase text-muted-foreground">Saídas</dt>
          <dd className="text-xl font-bold text-destructive">{saidas}</dd>
        </div>
      </dl>

      {cortado ? (
        <p className="rounded-lg border bg-card px-4 py-3 text-sm text-muted-foreground">
          Período com muita movimentação: aparecem só as {LIMITE_DO_EXTRATO} mais recentes de
          cada livro. Diminua o período ou use os filtros para ver o resto.
        </p>
      ) : null}

      {linhas.length === 0 ? (
        <p className="rounded-xl border border-dashed p-6 text-center text-sm text-muted-foreground">
          Nenhuma movimentação nesse período com esses filtros.
        </p>
      ) : (
        <ul className="divide-y rounded-xl border bg-card">
          {linhas.map((l) => (
            <li key={l.chave} className="flex flex-wrap items-center gap-x-3 gap-y-1 p-3 text-sm">
              <span className="min-w-0 flex-1">
                <span className="block truncate font-medium">
                  {l.item}
                  <span className="ml-2 rounded-full bg-muted px-2 py-0.5 text-[11px] font-semibold text-muted-foreground">
                    {l.deQue} · {l.origem}
                  </span>
                </span>
                <span className="block text-xs text-muted-foreground">
                  {quando(l.quando)}
                  {l.quem ? ` · ${l.quem}` : ""}
                  {l.motivo ? ` · ${l.motivo}` : ""}
                </span>
              </span>
              <span className="text-right">
                <span
                  className={`block font-bold ${
                    l.tipo === "in"
                      ? "text-status-pronto"
                      : l.tipo === "out"
                        ? "text-destructive"
                        : ""
                  }`}
                >
                  {l.tipo === "in" ? "+" : l.tipo === "out" ? "−" : "± "}
                  {l.quantidade}
                </span>
                <span
                  className={`block text-xs ${l.saldoNegativo ? "font-semibold text-destructive" : "text-muted-foreground"}`}
                >
                  ficou {l.saldo}
                </span>
              </span>
            </li>
          ))}
        </ul>
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
      {aba === "movimentacao" ? (
        <AbaDeMovimentacao restauranteId={vinculo.restauranteId} parametros={parametros} />
      ) : null}
    </div>
  )
}
