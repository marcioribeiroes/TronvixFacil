"use client"

import { useState, useTransition } from "react"
import { Minus, Plus } from "lucide-react"

import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { formatarReais } from "@/lib/dinheiro"

/**
 * O cardapio com a escolha do produto: adicionais, observacao e quantidade.
 *
 * Um componente so para tres caminhos — o carrinho do cliente, a edicao do
 * pedido pela loja e o "pedir mais" da mesa. Cada um diz o que fazer com a
 * escolha (`aoEscolher`); as regras dos grupos sao as mesmas nos tres, e
 * quem obriga de verdade e o banco.
 */

export type Produto = {
  id: string
  name: string
  description: string | null
  image_url: string | null
  price_cents: number
  promo_price_cents: number | null
  promo_starts_at: string | null
  promo_ends_at: string | null
  is_available: boolean
  track_stock: boolean
  stock_quantity: number
}

export type Adicional = { id: string; nome: string; precoCentavos: number }
export type Grupo = {
  id: string
  produtoId: string
  nome: string
  obrigatorio: boolean
  minimo: number
  maximo: number
  adicionais: Adicional[]
}

/**
 * A promocao so vale dentro da janela.
 *
 * A mesma conta existe em `fechar_pedido` e no aplicativo. Se as tres
 * divergirem, quem manda e a do banco - e o cliente veria um preco na tela e
 * outro na conta, que e o pior jeito de perder confianca.
 */
export function precoQueVale(p: Produto) {
  if (p.promo_price_cents === null) return p.price_cents
  const agora = new Date()
  if (p.promo_starts_at && new Date(p.promo_starts_at) > agora) return p.price_cents
  if (p.promo_ends_at && new Date(p.promo_ends_at) < agora) return p.price_cents
  return p.promo_price_cents
}


/** O que sai da escolha de um produto. */
export type Escolha = {
  produto: Produto
  quantidade: number
  adicionais: string[]
  observacao: string
  /** Preco do momento, so para mostrar. A conta de verdade e do banco. */
  totalCentavos: number
}

export type Secao = { id: string; nome: string; produtos: Produto[] }

type Resultado = { ok: true } | { ok: false; erro: string }

export function ListaDoCardapio({
  secoes,
  grupos,
  aoEscolher,
  rotuloDoBotao = "Adicionar",
  bloqueio,
}: {
  secoes: Secao[]
  grupos: Grupo[]
  aoEscolher: (escolha: Escolha) => Promise<Resultado>
  rotuloDoBotao?: string
  /** Texto do botao quando nao da para escolher (loja fechada, por exemplo). */
  bloqueio?: string
}) {
  const [escolhido, setEscolhido] = useState<Produto | null>(null)

  return (
    <div className="space-y-8">
      {secoes.map((s) => (
        <section key={s.id}>
          <h2 className="text-sm font-bold uppercase tracking-wide text-muted-foreground">
            {s.nome}
          </h2>
          <ul className="mt-2 divide-y rounded-xl border bg-card">
            {s.produtos.map((p) => {
              const esgotado = p.track_stock && p.stock_quantity <= 0
              const indisponivel = !p.is_available || esgotado
              const preco = precoQueVale(p)

              return (
                <li key={p.id}>
                  <button
                    type="button"
                    disabled={indisponivel}
                    onClick={() => setEscolhido(p)}
                    className="flex w-full items-start gap-4 p-4 text-left transition-colors hover:bg-muted/50 disabled:opacity-50 disabled:hover:bg-transparent"
                  >
                    <div className="min-w-0 flex-1">
                      <div className="flex flex-wrap items-center gap-2">
                        <span className="font-semibold">{p.name}</span>
                        {esgotado ? <Badge variant="destructive">Esgotado</Badge> : null}
                        {!p.is_available && !esgotado ? (
                          <Badge variant="secondary">Indisponível</Badge>
                        ) : null}
                      </div>
                      {p.description ? (
                        <p className="mt-0.5 line-clamp-2 text-sm text-muted-foreground">
                          {p.description}
                        </p>
                      ) : null}
                      <p className="mt-1.5 text-sm">
                        <strong>{formatarReais(preco)}</strong>
                        {preco !== p.price_cents ? (
                          <span className="ml-2 text-muted-foreground line-through">
                            {formatarReais(p.price_cents)}
                          </span>
                        ) : null}
                      </p>
                    </div>

                    {p.image_url ? (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img
                        src={p.image_url}
                        alt=""
                        className="size-20 shrink-0 rounded-lg object-cover"
                      />
                    ) : null}
                  </button>
                </li>
              )
            })}
          </ul>
        </section>
      ))}

      {escolhido ? (
        <EscolhaDoProduto
          produto={escolhido}
          grupos={grupos.filter((g) => g.produtoId === escolhido.id)}
          aoEscolher={aoEscolher}
          rotuloDoBotao={rotuloDoBotao}
          bloqueio={bloqueio}
          aoFechar={() => setEscolhido(null)}
        />
      ) : null}
    </div>
  )
}

function EscolhaDoProduto({
  produto,
  grupos,
  aoEscolher,
  rotuloDoBotao,
  bloqueio,
  aoFechar,
}: {
  produto: Produto
  grupos: Grupo[]
  aoEscolher: (escolha: Escolha) => Promise<Resultado>
  rotuloDoBotao: string
  bloqueio?: string
  aoFechar: () => void
}) {
  const [enviando, iniciar] = useTransition()
  const [erro, setErro] = useState<string | null>(null)
  const [quantidade, setQuantidade] = useState(1)
  const [observacao, setObservacao] = useState("")
  const [escolhidos, setEscolhidos] = useState<string[]>([])

  const preco = precoQueVale(produto)
  const adicionaisCentavos = grupos
    .flatMap((g) => g.adicionais)
    .filter((a) => escolhidos.includes(a.id))
    .reduce((soma, a) => soma + a.precoCentavos, 0)
  const total = (preco + adicionaisCentavos) * quantidade

  // O primeiro grupo obrigatório ainda sem escolha. A tela obedece às regras,
  // mas quem obriga de verdade é fechar_pedido, no banco.
  const pendente = grupos.find(
    (g) => g.adicionais.filter((a) => escolhidos.includes(a.id)).length < g.minimo,
  )

  function alternar(g: Grupo, id: string) {
    setEscolhidos((atuais) => {
      const doGrupo = g.adicionais.map((a) => a.id)
      const jaEscolhido = atuais.includes(id)

      if (g.maximo === 1) {
        // Escolha única: entra no lugar do que estava.
        return [...atuais.filter((x) => !doGrupo.includes(x)), ...(jaEscolhido ? [] : [id])]
      }
      if (jaEscolhido) return atuais.filter((x) => x !== id)
      const quantos = atuais.filter((x) => doGrupo.includes(x)).length
      if (quantos >= g.maximo) return atuais
      return [...atuais, id]
    })
  }

  function adicionar() {
    setErro(null)
    iniciar(async () => {
      const r = await aoEscolher({
        produto,
        quantidade,
        adicionais: escolhidos,
        observacao,
        totalCentavos: total,
      })
      if (r.ok) {
        aoFechar()
      } else setErro(r.erro)
    })
  }

  return (
    <div
      className="fixed inset-0 z-50 flex items-end justify-center bg-black/50 p-0 sm:items-center sm:p-6"
      role="dialog"
      aria-modal="true"
      aria-label={produto.name}
    >
      <div className="max-h-[90dvh] w-full max-w-lg overflow-y-auto rounded-t-2xl bg-background sm:rounded-2xl">
        <div className="p-5">
          <h2 className="text-xl font-bold">{produto.name}</h2>
          {produto.description ? (
            <p className="mt-1 text-sm text-muted-foreground">{produto.description}</p>
          ) : null}
          <p className="mt-2 font-bold">{formatarReais(preco)}</p>
        </div>

        {grupos.map((g) => {
          const noGrupo = g.adicionais.filter((a) => escolhidos.includes(a.id)).length
          return (
            <section key={g.id} className="border-t">
              <header className="flex items-center justify-between bg-muted/50 px-5 py-3">
                <span className="font-semibold">{g.nome}</span>
                <Badge variant={g.obrigatorio ? "default" : "secondary"}>
                  {g.obrigatorio
                    ? noGrupo >= g.minimo
                      ? "ok"
                      : g.maximo === 1
                        ? "Escolha 1"
                        : `Escolha ${g.minimo}`
                    : g.maximo === 1
                      ? "Opcional"
                      : `Até ${g.maximo}`}
                </Badge>
              </header>
              <ul className="divide-y">
                {g.adicionais.map((a) => (
                  <li key={a.id}>
                    <label className="flex cursor-pointer items-center gap-3 px-5 py-3">
                      <input
                        type={g.maximo === 1 ? "radio" : "checkbox"}
                        name={g.id}
                        checked={escolhidos.includes(a.id)}
                        onChange={() => alternar(g, a.id)}
                        className="size-4 accent-marca"
                      />
                      <span className="flex-1">{a.nome}</span>
                      {a.precoCentavos > 0 ? (
                        <span className="text-sm text-muted-foreground">
                          + {formatarReais(a.precoCentavos)}
                        </span>
                      ) : null}
                    </label>
                  </li>
                ))}
              </ul>
            </section>
          )
        })}

        <div className="border-t p-5">
          <label htmlFor="obs" className="text-sm font-medium">
            Alguma observação?
          </label>
          <Input
            id="obs"
            value={observacao}
            onChange={(e) => setObservacao(e.target.value)}
            placeholder="Sem cebola, ponto da carne, embalar separado"
            maxLength={200}
            className="mt-1"
          />
        </div>

        {erro ? (
          <p role="alert" className="px-5 pb-3 text-sm font-medium text-destructive">
            {erro}
          </p>
        ) : null}

        <div className="sticky bottom-0 flex items-center gap-3 border-t bg-background p-4">
          <div className="flex items-center rounded-lg border">
            <Button
              size="sm"
              variant="ghost"
              onClick={() => setQuantidade((q) => Math.max(1, q - 1))}
              aria-label="Menos um"
            >
              <Minus className="size-4" aria-hidden="true" />
            </Button>
            <span className="w-8 text-center font-bold">{quantidade}</span>
            <Button
              size="sm"
              variant="ghost"
              onClick={() => setQuantidade((q) => Math.min(99, q + 1))}
              aria-label="Mais um"
            >
              <Plus className="size-4" aria-hidden="true" />
            </Button>
          </div>

          <Button
            className="flex-1"
            onClick={adicionar}
            disabled={enviando || Boolean(bloqueio) || Boolean(pendente)}
          >
            {bloqueio
              ? bloqueio
              : pendente
                ? `Escolha em "${pendente.nome}"`
                : `${rotuloDoBotao} · ${formatarReais(total)}`}
          </Button>

          <Button variant="ghost" onClick={aoFechar}>
            Fechar
          </Button>
        </div>
      </div>
    </div>
  )
}
