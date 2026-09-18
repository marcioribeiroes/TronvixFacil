"use client"

import { useState, useTransition } from "react"
import { GripVertical, Plus, Trash2 } from "lucide-react"

import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { removerCategoria, salvarCategoria } from "@/modules/painel/cardapio"

type Secao = {
  id: string
  nome: string
  descricao: string | null
  posicao: number
  produtos: number
}

export function SecoesDoCardapio({ categorias }: { categorias: Secao[] }) {
  const [enviando, iniciar] = useTransition()
  const [erro, setErro] = useState<string | null>(null)
  const [nova, setNova] = useState("")
  const [editando, setEditando] = useState<string | null>(null)
  const [nome, setNome] = useState("")

  function criar() {
    if (!nova.trim()) return
    setErro(null)
    iniciar(async () => {
      const r = await salvarCategoria({
        nome: nova,
        // Entra no fim da lista: ordem é decisão de quem monta o cardápio, e
        // o palpite razoável é "depois do que já existe".
        posicao: (categorias.at(-1)?.posicao ?? 0) + 1,
      })
      if (r.ok) setNova("")
      else setErro(r.erro)
    })
  }

  function renomear(id: string) {
    setErro(null)
    iniciar(async () => {
      const r = await salvarCategoria({ id, nome })
      if (r.ok) setEditando(null)
      else setErro(r.erro)
    })
  }

  function remover(id: string) {
    setErro(null)
    iniciar(async () => {
      const r = await removerCategoria(id)
      if (!r.ok) setErro(r.erro)
    })
  }

  return (
    <div className="space-y-4">
      <div className="flex gap-2">
        <Input
          value={nova}
          onChange={(e) => setNova(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && criar()}
          placeholder="Nova seção — Lanches, Bebidas, Sobremesas…"
          className="max-w-sm"
        />
        <Button onClick={criar} disabled={enviando || !nova.trim()}>
          <Plus className="size-4" aria-hidden="true" />
          Criar
        </Button>
      </div>

      {erro ? (
        <p role="alert" className="text-sm font-medium text-destructive">
          {erro}
        </p>
      ) : null}

      {categorias.length === 0 ? (
        <div className="rounded-xl border border-dashed p-10 text-center">
          <p className="font-semibold">Nenhuma seção ainda</p>
          <p className="mt-1 text-sm text-muted-foreground">
            Crie a primeira acima. Sem seção não dá para cadastrar produto — é
            exigência do banco, não da tela.
          </p>
        </div>
      ) : (
        <ul className="divide-y rounded-xl border bg-card">
          {categorias.map((c) => (
            <li key={c.id} className="flex items-center gap-3 p-4">
              <GripVertical className="size-4 shrink-0 text-muted-foreground" aria-hidden="true" />

              {editando === c.id ? (
                <>
                  <Input
                    value={nome}
                    onChange={(e) => setNome(e.target.value)}
                    onKeyDown={(e) => e.key === "Enter" && renomear(c.id)}
                    className="max-w-sm"
                    autoFocus
                  />
                  <Button size="sm" onClick={() => renomear(c.id)} disabled={enviando}>
                    Salvar
                  </Button>
                  <Button size="sm" variant="ghost" onClick={() => setEditando(null)}>
                    Cancelar
                  </Button>
                </>
              ) : (
                <>
                  <button
                    type="button"
                    className="flex-1 text-left"
                    onClick={() => {
                      setNome(c.nome)
                      setEditando(c.id)
                    }}
                  >
                    <span className="font-semibold">{c.nome}</span>
                    <span className="ml-2 text-sm text-muted-foreground">
                      {c.produtos} produto{c.produtos === 1 ? "" : "s"}
                    </span>
                  </button>

                  <Button
                    size="sm"
                    variant="ghost"
                    onClick={() => remover(c.id)}
                    disabled={enviando}
                    aria-label={`Remover ${c.nome}`}
                  >
                    <Trash2 className="size-4" aria-hidden="true" />
                  </Button>
                </>
              )}
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}
