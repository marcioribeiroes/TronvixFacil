"use client"

import { useState, useTransition } from "react"
import { Archive, Pencil } from "lucide-react"

import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { arquivarIngrediente, salvarIngrediente } from "@/modules/painel/ingredientes"
import { UNIDADES, emQuantidade } from "@/modules/painel/unidades"

export type IngredienteDoEstoque = {
  id: string
  nome: string
  unidade: string
  saldo: number
}

const SELECT =
  "h-9 w-full rounded-lg border border-input bg-transparent px-2.5 text-sm outline-none focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50"

/**
 * O cadastro dos ingredientes e o saldo de cada um.
 *
 * O mesmo formulario cadastra e corrige: tocar no lapis traz o ingrediente
 * para cima. Saldo negativo aparece em vermelho - e o aviso que a regra
 * "permite e avisa" promete: a saida entrou, a contagem e que esta devendo.
 */
export function IngredientesDoEstoque({ ingredientes }: { ingredientes: IngredienteDoEstoque[] }) {
  const [enviando, iniciar] = useTransition()
  const [erro, setErro] = useState<string | null>(null)
  const [editando, setEditando] = useState<string | null>(null)
  const [nome, setNome] = useState("")
  const [unidade, setUnidade] = useState<string>("kg")

  const negativos = ingredientes.filter((i) => i.saldo < 0).length

  function limpar() {
    setEditando(null)
    setNome("")
    setUnidade("kg")
  }

  function salvar() {
    setErro(null)
    iniciar(async () => {
      const r = await salvarIngrediente({
        id: editando ?? undefined,
        nome,
        unidade: unidade as (typeof UNIDADES)[number],
      })
      if (r.ok) limpar()
      else setErro(r.erro)
    })
  }

  function arquivar(i: IngredienteDoEstoque) {
    if (!window.confirm(`Arquivar ${i.nome}? Ele sai das fichas técnicas; o histórico fica.`)) return
    setErro(null)
    iniciar(async () => {
      const r = await arquivarIngrediente(i.id)
      if (!r.ok) setErro(r.erro)
    })
  }

  return (
    <section className="space-y-4">
      <form
        className="grid gap-3 rounded-xl border bg-card p-4 sm:grid-cols-[1fr_8rem_auto] sm:items-end"
        noValidate
        onSubmit={(e) => {
          e.preventDefault()
          salvar()
        }}
      >
        <div className="space-y-2">
          <Label htmlFor="ingrediente-nome">{editando ? "Corrigir ingrediente" : "Novo ingrediente"}</Label>
          <Input
            id="ingrediente-nome"
            value={nome}
            onChange={(e) => setNome(e.target.value)}
            placeholder="Tomate"
          />
        </div>
        <div className="space-y-2">
          <Label htmlFor="ingrediente-unidade">Unidade</Label>
          <select
            id="ingrediente-unidade"
            className={SELECT}
            value={unidade}
            onChange={(e) => setUnidade(e.target.value)}
          >
            {UNIDADES.map((u) => (
              <option key={u} value={u}>
                {u}
              </option>
            ))}
          </select>
        </div>
        <div className="flex gap-2">
          <Button type="submit" disabled={enviando}>
            {editando ? "Salvar" : "Cadastrar"}
          </Button>
          {editando ? (
            <Button type="button" variant="ghost" onClick={limpar}>
              Cancelar
            </Button>
          ) : null}
        </div>
        {erro ? (
          <p role="alert" className="text-sm font-medium text-destructive sm:col-span-3">
            {erro}
          </p>
        ) : null}
      </form>

      {negativos > 0 ? (
        <p className="rounded-lg border border-destructive/40 bg-destructive/5 px-4 py-3 text-sm">
          <strong className="text-destructive">
            {negativos} {negativos === 1 ? "ingrediente está" : "ingredientes estão"} com saldo
            negativo.
          </strong>{" "}
          Saiu mais do que entrou: lance a entrada do que chegou para acertar a contagem.
        </p>
      ) : null}

      {ingredientes.length === 0 ? (
        <p className="rounded-xl border border-dashed p-6 text-center text-sm text-muted-foreground">
          Nenhum ingrediente cadastrado. Cadastre o primeiro acima — os preparos da cozinha
          usam esta lista.
        </p>
      ) : (
        <ul className="divide-y rounded-xl border bg-card">
          {ingredientes.map((i) => (
            <li key={i.id} className="flex items-center gap-3 p-3 text-sm">
              <span className="min-w-0 flex-1 truncate font-medium">{i.nome}</span>
              <span
                className={`font-bold tabular-nums ${i.saldo < 0 ? "text-destructive" : ""}`}
              >
                {emQuantidade(i.saldo, i.unidade)}
              </span>
              <Button
                variant="ghost"
                size="icon"
                aria-label={`Corrigir ${i.nome}`}
                onClick={() => {
                  setEditando(i.id)
                  setNome(i.nome)
                  setUnidade(i.unidade)
                  setErro(null)
                }}
              >
                <Pencil className="size-4" aria-hidden="true" />
              </Button>
              <Button
                variant="ghost"
                size="icon"
                aria-label={`Arquivar ${i.nome}`}
                disabled={enviando}
                onClick={() => arquivar(i)}
              >
                <Archive className="size-4" aria-hidden="true" />
              </Button>
            </li>
          ))}
        </ul>
      )}
    </section>
  )
}
