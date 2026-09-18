"use client"

import Link from "next/link"
import { useState, useTransition } from "react"
import { Plus, Trash2 } from "lucide-react"

import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { formatarReais } from "@/lib/dinheiro"
import {
  removerAdicional,
  removerGrupoDeAdicionais,
  salvarAdicional,
  salvarGrupoDeAdicionais,
} from "@/modules/painel/cardapio"

type Produto = { id: string; nome: string; secao: string }
type Adicional = { id: string; nome: string; precoCentavos: number }
type Grupo = {
  id: string
  produtoId: string
  nome: string
  obrigatorio: boolean
  minimo: number
  maximo: number
  adicionais: Adicional[]
}

function regra(g: Grupo) {
  if (g.obrigatorio && g.maximo === 1) return "Escolha 1"
  if (g.obrigatorio) return `Escolha de ${g.minimo} a ${g.maximo}`
  if (g.maximo === 1) return "Opcional"
  return `Até ${g.maximo}`
}

export function GruposDeAdicionais({
  produtos,
  grupos,
}: {
  produtos: Produto[]
  grupos: Grupo[]
}) {
  const [enviando, iniciar] = useTransition()
  const [erro, setErro] = useState<string | null>(null)
  const [criandoEm, setCriandoEm] = useState<string | null>(null)
  const [nomeDoGrupo, setNomeDoGrupo] = useState("")
  const [obrigatorio, setObrigatorio] = useState(false)
  const [maximo, setMaximo] = useState("1")

  if (produtos.length === 0) {
    return (
      <div className="rounded-xl border border-dashed p-10 text-center">
        <p className="font-semibold">Cadastre um produto antes</p>
        <p className="mt-1 text-sm text-muted-foreground">
          Adicional pertence a um produto: é o que o cliente escolhe junto dele.
        </p>
        <Link
          href="/painel/produtos"
          className="mt-4 inline-flex h-10 items-center rounded-lg bg-marca px-5 text-sm font-semibold text-white transition-colors hover:bg-marca-forte"
        >
          Ir para Produtos
        </Link>
      </div>
    )
  }

  function criarGrupo(produtoId: string) {
    setErro(null)
    iniciar(async () => {
      const r = await salvarGrupoDeAdicionais({
        produtoId,
        nome: nomeDoGrupo,
        obrigatorio,
        // Obrigatório com mínimo zero não obriga nada; o banco recusa e a tela
        // não deveria nem oferecer.
        minimo: obrigatorio ? 1 : 0,
        maximo: Math.max(1, Number(maximo) || 1),
      })
      if (r.ok) {
        setCriandoEm(null)
        setNomeDoGrupo("")
        setObrigatorio(false)
        setMaximo("1")
      } else setErro(r.erro)
    })
  }

  return (
    <div className="space-y-6">
      {erro ? (
        <p role="alert" className="text-sm font-medium text-destructive">
          {erro}
        </p>
      ) : null}

      {produtos.map((p) => {
        const doProduto = grupos.filter((g) => g.produtoId === p.id)

        return (
          <section key={p.id} className="rounded-xl border bg-card p-4">
            <header className="flex flex-wrap items-center justify-between gap-3">
              <div>
                <h2 className="font-bold">{p.nome}</h2>
                <p className="text-sm text-muted-foreground">{p.secao}</p>
              </div>
              <Button
                size="sm"
                variant="outline"
                onClick={() => setCriandoEm(criandoEm === p.id ? null : p.id)}
              >
                <Plus className="size-4" aria-hidden="true" />
                Grupo
              </Button>
            </header>

            {criandoEm === p.id ? (
              <div className="mt-4 grid gap-3 rounded-lg border p-3 sm:grid-cols-[1fr_auto_auto_auto]">
                <div>
                  <Label htmlFor={`grupo-${p.id}`}>Nome do grupo</Label>
                  <Input
                    id={`grupo-${p.id}`}
                    value={nomeDoGrupo}
                    onChange={(e) => setNomeDoGrupo(e.target.value)}
                    placeholder="Ponto da carne, Extras…"
                  />
                </div>
                <div>
                  <Label htmlFor={`max-${p.id}`}>Máximo</Label>
                  <Input
                    id={`max-${p.id}`}
                    value={maximo}
                    onChange={(e) => setMaximo(e.target.value)}
                    className="w-20"
                    inputMode="numeric"
                  />
                </div>
                <label className="flex items-end gap-2 pb-2 text-sm">
                  <input
                    type="checkbox"
                    checked={obrigatorio}
                    onChange={(e) => setObrigatorio(e.target.checked)}
                    className="size-4 accent-marca"
                  />
                  Obrigatório
                </label>
                <div className="flex items-end">
                  <Button onClick={() => criarGrupo(p.id)} disabled={enviando}>
                    Criar
                  </Button>
                </div>
              </div>
            ) : null}

            {doProduto.length === 0 ? (
              <p className="mt-3 text-sm text-muted-foreground">
                Nenhum grupo. Este produto vai direto para o carrinho.
              </p>
            ) : (
              <div className="mt-4 space-y-4">
                {doProduto.map((g) => (
                  <Grupo key={g.id} grupo={g} />
                ))}
              </div>
            )}
          </section>
        )
      })}
    </div>
  )
}

function Grupo({ grupo: g }: { grupo: Grupo }) {
  const [enviando, iniciar] = useTransition()
  const [erro, setErro] = useState<string | null>(null)
  const [nome, setNome] = useState("")
  const [preco, setPreco] = useState("")

  function adicionar() {
    if (!nome.trim()) return
    setErro(null)
    iniciar(async () => {
      const r = await salvarAdicional({ grupoId: g.id, nome, preco })
      if (r.ok) {
        setNome("")
        setPreco("")
      } else setErro(r.erro)
    })
  }

  return (
    <div className="rounded-lg border p-3">
      <header className="flex flex-wrap items-center gap-2">
        <span className="font-semibold">{g.nome}</span>
        <Badge variant={g.obrigatorio ? "default" : "secondary"}>{regra(g)}</Badge>
        <Button
          size="sm"
          variant="ghost"
          className="ml-auto"
          disabled={enviando}
          aria-label={`Remover grupo ${g.nome}`}
          onClick={() =>
            iniciar(async () => {
              const r = await removerGrupoDeAdicionais(g.id)
              if (!r.ok) setErro(r.erro)
            })
          }
        >
          <Trash2 className="size-4" aria-hidden="true" />
        </Button>
      </header>

      <ul className="mt-2 divide-y">
        {g.adicionais.map((a) => (
          <li key={a.id} className="flex items-center gap-2 py-1.5 text-sm">
            <span className="flex-1">{a.nome}</span>
            <span className="text-muted-foreground">
              {a.precoCentavos === 0 ? "grátis" : `+ ${formatarReais(a.precoCentavos)}`}
            </span>
            <Button
              size="sm"
              variant="ghost"
              disabled={enviando}
              aria-label={`Remover ${a.nome}`}
              onClick={() =>
                iniciar(async () => {
                  const r = await removerAdicional(a.id)
                  if (!r.ok) setErro(r.erro)
                })
              }
            >
              <Trash2 className="size-3.5" aria-hidden="true" />
            </Button>
          </li>
        ))}
      </ul>

      <div className="mt-2 flex gap-2">
        <Input
          value={nome}
          onChange={(e) => setNome(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && adicionar()}
          placeholder="Nome da opção"
          className="flex-1"
        />
        <Input
          value={preco}
          onChange={(e) => setPreco(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && adicionar()}
          placeholder="grátis"
          className="w-24"
          inputMode="decimal"
        />
        <Button size="sm" variant="outline" onClick={adicionar} disabled={enviando}>
          <Plus className="size-4" aria-hidden="true" />
        </Button>
      </div>

      {erro ? (
        <p role="alert" className="mt-2 text-sm font-medium text-destructive">
          {erro}
        </p>
      ) : null}
    </div>
  )
}
