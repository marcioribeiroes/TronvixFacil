"use client"

import { useRouter } from "next/navigation"
import { useState, useTransition } from "react"
import { Minus, Plus, Trash2 } from "lucide-react"

import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import {
  ListaDoCardapio,
  type Escolha,
  type Grupo,
  type Secao,
} from "@/components/pedido/cardapio-para-escolher"
import { formatarReais } from "@/lib/dinheiro"
import { editarPedido } from "@/modules/painel/pedidos"

export type ItemDoPedido = {
  id: string
  nome: string
  quantidade: number
  unitarioCentavos: number
  adicionaisCentavos: number
  adicionais: string[]
  observacao: string | null
}

/**
 * O pedido aberto na mão do balcão.
 *
 * Nada vai para o banco até "Salvar": quantidades, remoções e itens novos são
 * montados aqui e seguem numa chamada só. O total que aparece é a prévia — a
 * conta que vale é a que o banco refaz ao salvar.
 */
export function EditorDoPedido({
  pedidoId,
  itens,
  freteCentavos,
  descontoCentavos,
  secoes,
  grupos,
}: {
  pedidoId: string
  itens: ItemDoPedido[]
  freteCentavos: number
  descontoCentavos: number
  secoes: Secao[]
  grupos: Grupo[]
}) {
  const router = useRouter()
  const [enviando, iniciar] = useTransition()
  const [erro, setErro] = useState<string | null>(null)
  const [quantidades, setQuantidades] = useState<Record<string, number>>(() =>
    Object.fromEntries(itens.map((i) => [i.id, i.quantidade])),
  )
  const [novos, setNovos] = useState<(Escolha & { chave: number })[]>([])

  function mudar(id: string, delta: number) {
    setQuantidades((q) => ({ ...q, [id]: Math.min(99, Math.max(0, (q[id] ?? 0) + delta)) }))
  }

  const subtotal =
    itens.reduce(
      (s, i) => s + (i.unitarioCentavos + i.adicionaisCentavos) * (quantidades[i.id] ?? 0),
      0,
    ) + novos.reduce((s, n) => s + n.totalCentavos, 0)
  const desconto = Math.min(descontoCentavos, subtotal + freteCentavos)
  const total = subtotal + freteCentavos - desconto

  const mudados = itens.filter((i) => quantidades[i.id] !== i.quantidade)
  const nadaMudou = mudados.length === 0 && novos.length === 0
  const vazio = subtotal === 0

  function salvar() {
    setErro(null)
    iniciar(async () => {
      const r = await editarPedido(pedidoId, {
        itens: mudados.map((i) => ({ id: i.id, quantidade: quantidades[i.id] ?? 0 })),
        novos: novos.map((n) => ({
          produto_id: n.produto.id,
          quantidade: n.quantidade,
          observacao: n.observacao,
          adicionais: n.adicionais,
        })),
      })
      if (r.ok) router.push("/painel/pedidos")
      else setErro(r.erro)
    })
  }

  return (
    <div className="grid gap-6 lg:grid-cols-[minmax(0,1fr)_minmax(0,1.2fr)]">
      <section className="space-y-4 lg:sticky lg:top-20 lg:self-start">
        <ul className="divide-y rounded-xl border bg-card">
          {itens.map((i) => {
            const q = quantidades[i.id] ?? 0
            return (
              <li
                key={i.id}
                className={`flex items-start gap-3 p-3 text-sm ${q === 0 ? "opacity-50" : ""}`}
              >
                <div className="min-w-0 flex-1">
                  <p className={`font-semibold ${q === 0 ? "line-through" : ""}`}>{i.nome}</p>
                  {i.adicionais.map((a) => (
                    <p key={a} className="text-xs text-muted-foreground">
                      + {a}
                    </p>
                  ))}
                  {i.observacao ? (
                    <p className="text-xs font-semibold text-marca-forte">“{i.observacao}”</p>
                  ) : null}
                  <p className="mt-1 text-xs text-muted-foreground">
                    {formatarReais((i.unitarioCentavos + i.adicionaisCentavos) * q)}
                  </p>
                </div>
                <div className="flex items-center rounded-lg border">
                  <Button
                    size="sm"
                    variant="ghost"
                    onClick={() => mudar(i.id, -1)}
                    disabled={q === 0}
                    aria-label={`Um ${i.nome} a menos`}
                  >
                    {q === 1 ? (
                      <Trash2 className="size-4" aria-hidden="true" />
                    ) : (
                      <Minus className="size-4" aria-hidden="true" />
                    )}
                  </Button>
                  <span className="w-7 text-center font-bold">{q}</span>
                  <Button
                    size="sm"
                    variant="ghost"
                    onClick={() => mudar(i.id, 1)}
                    aria-label={`Um ${i.nome} a mais`}
                  >
                    <Plus className="size-4" aria-hidden="true" />
                  </Button>
                </div>
              </li>
            )
          })}

          {novos.map((n) => (
            <li key={n.chave} className="flex items-start gap-3 bg-marca-suave/40 p-3 text-sm">
              <div className="min-w-0 flex-1">
                <p className="font-semibold">
                  {n.quantidade}× {n.produto.name} <Badge className="ml-1">novo</Badge>
                </p>
                {grupos
                  .flatMap((g) => g.adicionais)
                  .filter((a) => n.adicionais.includes(a.id))
                  .map((a) => (
                    <p key={a.id} className="text-xs text-muted-foreground">
                      + {a.nome}
                    </p>
                  ))}
                {n.observacao ? (
                  <p className="text-xs font-semibold text-marca-forte">“{n.observacao}”</p>
                ) : null}
                <p className="mt-1 text-xs text-muted-foreground">{formatarReais(n.totalCentavos)}</p>
              </div>
              <Button
                size="sm"
                variant="ghost"
                onClick={() => setNovos((atuais) => atuais.filter((x) => x.chave !== n.chave))}
                aria-label={`Tirar ${n.produto.name}`}
              >
                <Trash2 className="size-4" aria-hidden="true" />
              </Button>
            </li>
          ))}
        </ul>

        <dl className="space-y-1.5 rounded-xl border bg-card p-4 text-sm">
          <div className="flex justify-between">
            <dt className="text-muted-foreground">Subtotal</dt>
            <dd>{formatarReais(subtotal)}</dd>
          </div>
          {freteCentavos > 0 ? (
            <div className="flex justify-between">
              <dt className="text-muted-foreground">Entrega</dt>
              <dd>{formatarReais(freteCentavos)}</dd>
            </div>
          ) : null}
          {desconto > 0 ? (
            <div className="flex justify-between">
              <dt className="text-muted-foreground">Desconto</dt>
              <dd>− {formatarReais(desconto)}</dd>
            </div>
          ) : null}
          <div className="flex justify-between border-t pt-2 text-base font-bold">
            <dt>Novo total</dt>
            <dd>{formatarReais(total)}</dd>
          </div>
        </dl>

        {vazio ? (
          <p className="text-sm text-muted-foreground">
            O pedido não pode ficar sem itens. Para desistir de tudo, cancele o pedido na fila.
          </p>
        ) : null}
        {erro ? (
          <p role="alert" className="text-sm font-medium text-destructive">
            {erro}
          </p>
        ) : null}

        <div className="flex gap-2">
          <Button className="flex-1" onClick={salvar} disabled={enviando || nadaMudou || vazio}>
            Salvar alterações
          </Button>
          <Button variant="outline" onClick={() => router.push("/painel/pedidos")}>
            Voltar
          </Button>
        </div>
      </section>

      <section className="space-y-3">
        <h2 className="text-sm font-bold uppercase tracking-wide">Adicionar itens</h2>
        <ListaDoCardapio
          secoes={secoes}
          grupos={grupos}
          rotuloDoBotao="Pôr no pedido"
          aoEscolher={async (escolha) => {
            setNovos((atuais) => [...atuais, { ...escolha, chave: Date.now() }])
            return { ok: true }
          }}
        />
      </section>
    </div>
  )
}
