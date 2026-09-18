"use client"

import { useState, useTransition } from "react"
import { Pencil, Plus, Star, Trash2 } from "lucide-react"

import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { formatarReais, formatarValor } from "@/lib/dinheiro"
import {
  mudarDisponibilidade,
  removerProduto,
  salvarProduto,
} from "@/modules/painel/cardapio"

type Produto = {
  id: string
  category_id: string
  name: string
  description: string | null
  price_cents: number
  promo_price_cents: number | null
  promo_ends_at: string | null
  is_available: boolean
  is_featured: boolean
  track_stock: boolean
  stock_quantity: number
  sold_count: number
}

type Categoria = { id: string; nome: string }

export function ListaDeProdutos({
  categorias,
  produtos,
  podeGerenciar,
}: {
  categorias: Categoria[]
  produtos: Produto[]
  podeGerenciar: boolean
}) {
  const [editando, setEditando] = useState<Produto | "novo" | null>(null)

  if (categorias.length === 0) {
    return (
      <div className="rounded-xl border border-dashed p-10 text-center">
        <p className="font-semibold">Crie uma seção antes</p>
        <p className="mt-1 text-sm text-muted-foreground">
          Todo produto pertence a uma seção do cardápio. Comece por Categorias.
        </p>
      </div>
    )
  }

  return (
    <div className="space-y-6">
      {podeGerenciar ? (
        <Button onClick={() => setEditando("novo")}>
          <Plus className="size-4" aria-hidden="true" />
          Novo produto
        </Button>
      ) : null}

      {editando ? (
        <FormularioDeProduto
          categorias={categorias}
          produto={editando === "novo" ? null : editando}
          aoFechar={() => setEditando(null)}
        />
      ) : null}

      {categorias.map((c) => {
        const daSecao = produtos.filter((p) => p.category_id === c.id)
        if (daSecao.length === 0) return null

        return (
          <section key={c.id}>
            <h2 className="text-sm font-bold uppercase tracking-wide text-muted-foreground">
              {c.nome}
            </h2>
            <ul className="mt-2 divide-y rounded-xl border bg-card">
              {daSecao.map((p) => (
                <LinhaDoProduto
                  key={p.id}
                  produto={p}
                  podeGerenciar={podeGerenciar}
                  aoEditar={() => setEditando(p)}
                />
              ))}
            </ul>
          </section>
        )
      })}
    </div>
  )
}

function LinhaDoProduto({
  produto: p,
  podeGerenciar,
  aoEditar,
}: {
  produto: Produto
  podeGerenciar: boolean
  aoEditar: () => void
}) {
  const [enviando, iniciar] = useTransition()
  const [erro, setErro] = useState<string | null>(null)

  // A janela manda: promoção vencida volta ao preço cheio, e é assim que
  // fechar_pedido cobra. A tela precisa contar a mesma história.
  const promoValendo =
    p.promo_price_cents !== null &&
    (!p.promo_ends_at || new Date(p.promo_ends_at) > new Date())

  const esgotado = p.track_stock && p.stock_quantity <= 0

  return (
    <li className="flex flex-wrap items-center gap-3 p-4">
      <div className="min-w-0 flex-1">
        <div className="flex flex-wrap items-center gap-2">
          <span className="font-semibold">{p.name}</span>
          {p.is_featured ? (
            <Star className="size-3.5 text-status-pronto" aria-label="Em destaque" />
          ) : null}
          {esgotado ? <Badge variant="destructive">Esgotado</Badge> : null}
          {promoValendo ? <Badge>Promoção</Badge> : null}
        </div>
        {p.description ? (
          <p className="line-clamp-1 text-sm text-muted-foreground">{p.description}</p>
        ) : null}
        <p className="mt-1 text-sm">
          <strong>{formatarReais(promoValendo ? p.promo_price_cents! : p.price_cents)}</strong>
          {promoValendo ? (
            <span className="ml-2 text-muted-foreground line-through">
              {formatarReais(p.price_cents)}
            </span>
          ) : null}
          {p.track_stock ? (
            <span className="ml-2 text-muted-foreground">· {p.stock_quantity} em estoque</span>
          ) : null}
          {p.sold_count > 0 ? (
            <span className="ml-2 text-muted-foreground">· {p.sold_count} vendidos</span>
          ) : null}
        </p>
      </div>

      {/* Tirar do ar é do atendente também: é a operação do meio do movimento. */}
      <label className="flex cursor-pointer items-center gap-2 text-sm">
        <input
          type="checkbox"
          checked={p.is_available}
          disabled={enviando}
          onChange={(e) =>
            iniciar(async () => {
              const r = await mudarDisponibilidade(p.id, e.target.checked)
              if (!r.ok) setErro(r.erro)
            })
          }
          className="size-4 accent-marca"
        />
        {p.is_available ? "No ar" : "Fora do ar"}
      </label>

      {podeGerenciar ? (
        <div className="flex gap-1">
          <Button size="sm" variant="ghost" onClick={aoEditar} aria-label={`Editar ${p.name}`}>
            <Pencil className="size-4" aria-hidden="true" />
          </Button>
          <Button
            size="sm"
            variant="ghost"
            disabled={enviando}
            aria-label={`Remover ${p.name}`}
            onClick={() =>
              iniciar(async () => {
                const r = await removerProduto(p.id)
                if (!r.ok) setErro(r.erro)
              })
            }
          >
            <Trash2 className="size-4" aria-hidden="true" />
          </Button>
        </div>
      ) : null}

      {erro ? (
        <p role="alert" className="w-full text-sm font-medium text-destructive">
          {erro}
        </p>
      ) : null}
    </li>
  )
}

function FormularioDeProduto({
  categorias,
  produto,
  aoFechar,
}: {
  categorias: Categoria[]
  produto: Produto | null
  aoFechar: () => void
}) {
  const [enviando, iniciar] = useTransition()
  const [erro, setErro] = useState<string | null>(null)

  const [categoriaId, setCategoriaId] = useState(produto?.category_id ?? categorias[0].id)
  const [nome, setNome] = useState(produto?.name ?? "")
  const [descricao, setDescricao] = useState(produto?.description ?? "")
  const [preco, setPreco] = useState(produto ? formatarValor(produto.price_cents) : "")
  const [promo, setPromo] = useState(
    produto?.promo_price_cents ? formatarValor(produto.promo_price_cents) : "",
  )
  const [fimDaPromo, setFimDaPromo] = useState(
    produto?.promo_ends_at ? produto.promo_ends_at.slice(0, 10) : "",
  )
  const [disponivel, setDisponivel] = useState(produto?.is_available ?? true)
  const [destaque, setDestaque] = useState(produto?.is_featured ?? false)
  const [controlaEstoque, setControlaEstoque] = useState(produto?.track_stock ?? false)
  const [estoque, setEstoque] = useState(String(produto?.stock_quantity ?? 0))

  function salvar() {
    setErro(null)
    iniciar(async () => {
      const r = await salvarProduto({
        id: produto?.id,
        categoriaId,
        nome,
        descricao,
        preco,
        precoPromocional: promo,
        promocaoTerminaEm: fimDaPromo,
        disponivel,
        destaque,
        controlaEstoque,
        estoque,
      })
      if (r.ok) aoFechar()
      else setErro(r.erro)
    })
  }

  return (
    <div className="rounded-xl border bg-card p-5">
      <h2 className="font-bold">{produto ? `Editar ${produto.name}` : "Novo produto"}</h2>

      <div className="mt-4 grid gap-4 sm:grid-cols-2">
        <div className="sm:col-span-2">
          <Label htmlFor="nome">Nome</Label>
          <Input id="nome" value={nome} onChange={(e) => setNome(e.target.value)} />
        </div>

        <div className="sm:col-span-2">
          <Label htmlFor="descricao">Descrição</Label>
          <Input
            id="descricao"
            value={descricao}
            onChange={(e) => setDescricao(e.target.value)}
            placeholder="Pão, hambúrguer, queijo, alface e tomate"
          />
        </div>

        <div>
          <Label htmlFor="secao">Seção</Label>
          <select
            id="secao"
            value={categoriaId}
            onChange={(e) => setCategoriaId(e.target.value)}
            className="h-10 w-full rounded-lg border bg-background px-3 text-sm"
          >
            {categorias.map((c) => (
              <option key={c.id} value={c.id}>
                {c.nome}
              </option>
            ))}
          </select>
        </div>

        <div>
          <Label htmlFor="preco">Preço</Label>
          <Input
            id="preco"
            value={preco}
            onChange={(e) => setPreco(e.target.value)}
            placeholder="27,90"
            inputMode="decimal"
          />
        </div>

        <div>
          <Label htmlFor="promo">Preço promocional</Label>
          <Input
            id="promo"
            value={promo}
            onChange={(e) => setPromo(e.target.value)}
            placeholder="deixe vazio se não houver"
            inputMode="decimal"
          />
        </div>

        <div>
          <Label htmlFor="fim">Promoção até</Label>
          <Input
            id="fim"
            type="date"
            value={fimDaPromo}
            onChange={(e) => setFimDaPromo(e.target.value)}
            disabled={!promo.trim()}
          />
        </div>
      </div>

      <div className="mt-4 flex flex-wrap gap-5 text-sm">
        <label className="flex cursor-pointer items-center gap-2">
          <input
            type="checkbox"
            checked={disponivel}
            onChange={(e) => setDisponivel(e.target.checked)}
            className="size-4 accent-marca"
          />
          No ar
        </label>
        <label className="flex cursor-pointer items-center gap-2">
          <input
            type="checkbox"
            checked={destaque}
            onChange={(e) => setDestaque(e.target.checked)}
            className="size-4 accent-marca"
          />
          Em destaque
        </label>
        <label className="flex cursor-pointer items-center gap-2">
          <input
            type="checkbox"
            checked={controlaEstoque}
            onChange={(e) => setControlaEstoque(e.target.checked)}
            className="size-4 accent-marca"
          />
          Controlar estoque
        </label>
        {controlaEstoque ? (
          <Input
            value={estoque}
            onChange={(e) => setEstoque(e.target.value)}
            className="w-24"
            inputMode="numeric"
            aria-label="Quantidade em estoque"
          />
        ) : null}
      </div>

      {erro ? (
        <p role="alert" className="mt-4 text-sm font-medium text-destructive">
          {erro}
        </p>
      ) : null}

      <div className="mt-5 flex gap-2">
        <Button onClick={salvar} disabled={enviando}>
          {enviando ? "Salvando…" : "Salvar"}
        </Button>
        <Button variant="ghost" onClick={aoFechar}>
          Cancelar
        </Button>
      </div>
    </div>
  )
}
