"use client"

import { useState, useTransition } from "react"
import { Plus, Trash2 } from "lucide-react"

import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import type { IngredienteDoEstoque } from "@/components/painel/ingredientes-do-estoque"
import { movimentarIngredientes, salvarFichaTecnica } from "@/modules/painel/ingredientes"
import { emQuantidade } from "@/modules/painel/unidades"

const SELECT =
  "h-9 w-full rounded-lg border border-input bg-transparent px-2.5 text-sm outline-none focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50"

type Linha = { ingrediente: string; quantidade: string }
const VAZIA: Linha = { ingrediente: "", quantidade: "" }

/**
 * As linhas "ingrediente + quantidade", que a entrada, a saida e a ficha
 * tecnica usam igual. A unidade vem do cadastro e aparece ao lado: quem lanca
 * nao escolhe unidade, so confere.
 */
function Linhas({
  ingredientes,
  linhas,
  setLinhas,
  mostrarSaldo,
}: {
  ingredientes: IngredienteDoEstoque[]
  linhas: Linha[]
  setLinhas: (f: (atuais: Linha[]) => Linha[]) => void
  mostrarSaldo: boolean
}) {
  const porId = new Map(ingredientes.map((i) => [i.id, i]))

  function mudar(indice: number, campo: keyof Linha, valor: string) {
    setLinhas((atuais) => atuais.map((l, i) => (i === indice ? { ...l, [campo]: valor } : l)))
  }

  return (
    <div className="space-y-2">
      {linhas.map((linha, i) => {
        const escolhido = porId.get(linha.ingrediente)
        return (
          <div key={i} className="grid grid-cols-[1fr_6rem_2.5rem_2.25rem] items-center gap-2">
            <select
              aria-label={`Ingrediente ${i + 1}`}
              className={SELECT}
              value={linha.ingrediente}
              onChange={(e) => mudar(i, "ingrediente", e.target.value)}
            >
              <option value="">Escolha…</option>
              {ingredientes.map((ing) => (
                <option key={ing.id} value={ing.id}>
                  {ing.nome}
                  {mostrarSaldo ? ` (tem ${emQuantidade(ing.saldo, ing.unidade)})` : ""}
                </option>
              ))}
            </select>
            <Input
              aria-label={`Quantidade do ingrediente ${i + 1}`}
              value={linha.quantidade}
              onChange={(e) => mudar(i, "quantidade", e.target.value)}
              placeholder="Qtd."
              inputMode="decimal"
            />
            <span className="text-sm text-muted-foreground">{escolhido?.unidade ?? ""}</span>
            <Button
              type="button"
              variant="ghost"
              size="icon"
              aria-label={`Tirar a linha ${i + 1}`}
              disabled={linhas.length === 1}
              onClick={() => setLinhas((atuais) => atuais.filter((_, j) => j !== i))}
            >
              <Trash2 className="size-4" aria-hidden="true" />
            </Button>
          </div>
        )
      })}
      <Button
        type="button"
        variant="outline"
        size="sm"
        onClick={() => setLinhas((atuais) => [...atuais, { ...VAZIA }])}
      >
        <Plus className="size-4" aria-hidden="true" />
        Ingrediente
      </Button>
    </div>
  )
}

/** Entrada (o que chegou) ou saida avulsa (perda, uso fora de preparo). */
export function MovimentoDeIngredientes({
  tipo,
  ingredientes,
}: {
  tipo: "in" | "out"
  ingredientes: IngredienteDoEstoque[]
}) {
  const [enviando, iniciar] = useTransition()
  const [aviso, setAviso] = useState<{ tipo: "erro" | "ok"; texto: string } | null>(null)
  const [linhas, setLinhas] = useState<Linha[]>([{ ...VAZIA }])
  const [motivo, setMotivo] = useState("")

  const entrada = tipo === "in"

  function enviar() {
    setAviso(null)
    iniciar(async () => {
      const r = await movimentarIngredientes({ tipo, itens: linhas, motivo })
      if (!r.ok) {
        setAviso({ tipo: "erro", texto: r.erro })
        return
      }
      setAviso({
        tipo: "ok",
        texto: `${entrada ? "Entrada" : "Saída"} de ${r.itens} ${r.itens === 1 ? "ingrediente" : "ingredientes"} lançada.`,
      })
      setLinhas([{ ...VAZIA }])
      setMotivo("")
    })
  }

  if (ingredientes.length === 0) {
    return (
      <p className="rounded-xl border border-dashed p-6 text-center text-sm text-muted-foreground">
        Cadastre os ingredientes na aba Ingredientes antes de lançar.
      </p>
    )
  }

  return (
    <form
      className="space-y-4 rounded-xl border bg-card p-4"
      noValidate
      onSubmit={(e) => {
        e.preventDefault()
        enviar()
      }}
    >
      <h2 className="font-bold">{entrada ? "Entrada de ingredientes" : "Saída avulsa"}</h2>
      <Linhas
        ingredientes={ingredientes}
        linhas={linhas}
        setLinhas={setLinhas}
        mostrarSaldo={!entrada}
      />
      <div className="space-y-2">
        <Label htmlFor={`motivo-${tipo}`}>{entrada ? "Nota ou fornecedor" : "Motivo"}</Label>
        <Input
          id={`motivo-${tipo}`}
          value={motivo}
          onChange={(e) => setMotivo(e.target.value)}
          placeholder={entrada ? "Nota 1234 — Hortifruti Central" : "Perda, vencido, consumo da equipe…"}
          maxLength={200}
        />
      </div>
      <div className="flex flex-wrap items-center gap-3">
        <Button type="submit" disabled={enviando}>
          {enviando ? "Lançando…" : entrada ? "Lançar entrada" : "Lançar saída"}
        </Button>
        {aviso ? (
          <p
            role={aviso.tipo === "erro" ? "alert" : "status"}
            className={`text-sm font-medium ${aviso.tipo === "erro" ? "text-destructive" : "text-marca"}`}
          >
            {aviso.texto}
          </p>
        ) : null}
      </div>
    </form>
  )
}

/**
 * A ficha tecnica de um produto: quanto de cada ingrediente UMA unidade gasta.
 * Quando o pedido fica pronto, o banco multiplica pela quantidade pedida.
 */
export function FichaTecnica({
  produto,
  ingredientes,
  atual,
}: {
  produto: { id: string; nome: string }
  ingredientes: IngredienteDoEstoque[]
  atual: Linha[]
}) {
  const [enviando, iniciar] = useTransition()
  const [aviso, setAviso] = useState<{ tipo: "erro" | "ok"; texto: string } | null>(null)
  const [linhas, setLinhas] = useState<Linha[]>(atual.length > 0 ? atual : [{ ...VAZIA }])

  function salvar() {
    setAviso(null)
    iniciar(async () => {
      const r = await salvarFichaTecnica({ produto: produto.id, itens: linhas })
      setAviso(
        r.ok
          ? { tipo: "ok", texto: "Ficha técnica salva." }
          : { tipo: "erro", texto: r.erro },
      )
    })
  }

  return (
    <form
      className="space-y-4 rounded-xl border bg-card p-4"
      noValidate
      onSubmit={(e) => {
        e.preventDefault()
        salvar()
      }}
    >
      <div>
        <h2 className="font-bold">{produto.nome}</h2>
        <p className="text-xs text-muted-foreground">
          Quanto uma unidade gasta. Pedido com 2 unidades gasta o dobro, na hora em que fica
          pronto. Sem linha nenhuma, o produto não gasta ingrediente.
        </p>
      </div>
      <Linhas
        ingredientes={ingredientes}
        linhas={linhas}
        setLinhas={setLinhas}
        mostrarSaldo={false}
      />
      <div className="flex flex-wrap items-center gap-3">
        <Button type="submit" disabled={enviando}>
          {enviando ? "Salvando…" : "Salvar ficha técnica"}
        </Button>
        {aviso ? (
          <p
            role={aviso.tipo === "erro" ? "alert" : "status"}
            className={`text-sm font-medium ${aviso.tipo === "erro" ? "text-destructive" : "text-marca"}`}
          >
            {aviso.texto}
          </p>
        ) : null}
      </div>
    </form>
  )
}
