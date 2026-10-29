"use client"

import { useState, useTransition } from "react"
import { Plus, Trash2 } from "lucide-react"

import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { lancarPreparo } from "@/modules/painel/cozinha"

/** Sem acento e sem caixa, como o banco compara: "file" acha "Filé". */
function normalizar(texto: string) {
  return texto.normalize("NFD").replace(/\p{Diacritic}/gu, "").trim().toLowerCase()
}

/**
 * O lancamento de um preparo: data, o que foi feito, para qual prato e com o
 * que. O prato sugere os produtos do cardapio, mas aceita qualquer nome - o
 * molho base serve a tres pratos, e nem todo preparo tem produto proprio.
 *
 * Os ingredientes sao os do estoque: o nome sugere o cadastro, a unidade vem
 * dele, e a quantidade e obrigatoria - e ela que sai do estoque. Nome que nao
 * esta no cadastro e recusado pelo banco, com o aviso de onde cadastrar.
 *
 * Enter na quantidade do ultimo ingrediente abre a linha seguinte: quem lanca
 * esta lendo a ficha da bancada, e nao quer tirar a mao do teclado a cada item.
 */

type Linha = { nome: string; quantidade: string }

const LINHA_VAZIA: Linha = { nome: "", quantidade: "" }

export function LancarPreparo({
  hoje,
  pratos,
  ingredientes,
}: {
  hoje: string
  pratos: string[]
  ingredientes: { nome: string; unidade: string }[]
}) {
  const [enviando, iniciar] = useTransition()
  const [aviso, setAviso] = useState<{ tipo: "erro" | "ok"; texto: string } | null>(null)

  const [data, setData] = useState(hoje)
  const [nome, setNome] = useState("")
  const [prato, setPrato] = useState("")
  const [observacao, setObservacao] = useState("")
  const [linhas, setLinhas] = useState<Linha[]>([{ ...LINHA_VAZIA }])
  const unidadeDe = new Map(ingredientes.map((i) => [normalizar(i.nome), i.unidade]))

  function mudar(indice: number, campo: keyof Linha, valor: string) {
    setLinhas((atuais) => atuais.map((l, i) => (i === indice ? { ...l, [campo]: valor } : l)))
  }

  function acrescentarLinha() {
    setLinhas((atuais) => [...atuais, { ...LINHA_VAZIA }])
  }

  function enviar() {
    setAviso(null)
    iniciar(async () => {
      const r = await lancarPreparo({ data, nome, prato, observacao, ingredientes: linhas })
      if (!r.ok) {
        setAviso({ tipo: "erro", texto: r.erro })
        return
      }
      setAviso({ tipo: "ok", texto: `Preparo nº ${r.numero} lançado.` })
      // A data fica: quem lanca a producao do dia lanca varios seguidos.
      setNome("")
      setPrato("")
      setObservacao("")
      setLinhas([{ ...LINHA_VAZIA }])
    })
  }

  return (
    <form
      className="space-y-5 rounded-xl border bg-card p-4 sm:p-5"
      noValidate
      onSubmit={(e) => {
        e.preventDefault()
        enviar()
      }}
    >
      <h2 className="font-bold">Lançar preparo</h2>

      <div className="grid gap-4 sm:grid-cols-[10rem_1fr_1fr]">
        <div className="space-y-2">
          <Label htmlFor="preparo-data">Data</Label>
          <Input
            id="preparo-data"
            type="date"
            value={data}
            max={hoje}
            onChange={(e) => setData(e.target.value)}
          />
        </div>
        <div className="space-y-2">
          <Label htmlFor="preparo-nome">Preparo</Label>
          <Input
            id="preparo-nome"
            value={nome}
            onChange={(e) => setNome(e.target.value)}
            placeholder="Molho de tomate"
          />
        </div>
        <div className="space-y-2">
          <Label htmlFor="preparo-prato">Prato</Label>
          <Input
            id="preparo-prato"
            value={prato}
            onChange={(e) => setPrato(e.target.value)}
            placeholder="Filé à parmegiana"
            list="pratos-do-cardapio"
          />
          <datalist id="pratos-do-cardapio">
            {pratos.map((p) => (
              <option key={p} value={p} />
            ))}
          </datalist>
        </div>
      </div>

      <fieldset className="space-y-2">
        <legend className="mb-2 text-sm font-medium">Ingredientes</legend>
        {ingredientes.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            Nenhum ingrediente no estoque ainda. A gestão cadastra em Estoque → Ingredientes.
          </p>
        ) : null}
        <datalist id="ingredientes-do-estoque">
          {ingredientes.map((i) => (
            <option key={i.nome} value={i.nome} />
          ))}
        </datalist>

        {linhas.map((linha, i) => (
          <div key={i} className="grid grid-cols-[1fr_5.5rem_2.5rem_2.25rem] items-center gap-2">
            <Input
              aria-label={`Ingrediente ${i + 1}`}
              value={linha.nome}
              onChange={(e) => mudar(i, "nome", e.target.value)}
              placeholder="Ingrediente"
              list="ingredientes-do-estoque"
            />
            <Input
              aria-label={`Quantidade do ingrediente ${i + 1}`}
              value={linha.quantidade}
              onChange={(e) => mudar(i, "quantidade", e.target.value)}
              placeholder="Qtd."
              inputMode="decimal"
              onKeyDown={(e) => {
                if (e.key === "Enter" && i === linhas.length - 1 && linha.nome.trim()) {
                  e.preventDefault()
                  acrescentarLinha()
                }
              }}
            />
            <span className="text-sm text-muted-foreground">
              {unidadeDe.get(normalizar(linha.nome)) ?? ""}
            </span>
            <Button
              type="button"
              variant="ghost"
              size="icon"
              aria-label={`Tirar o ingrediente ${i + 1}`}
              disabled={linhas.length === 1}
              onClick={() => setLinhas((atuais) => atuais.filter((_, j) => j !== i))}
            >
              <Trash2 className="size-4" aria-hidden="true" />
            </Button>
          </div>
        ))}

        <Button type="button" variant="outline" size="sm" onClick={acrescentarLinha}>
          <Plus className="size-4" aria-hidden="true" />
          Ingrediente
        </Button>
      </fieldset>

      <div className="space-y-2">
        <Label htmlFor="preparo-observacao">Observação</Label>
        <Input
          id="preparo-observacao"
          value={observacao}
          onChange={(e) => setObservacao(e.target.value)}
          placeholder="Lote, validade, quem preparou…"
          maxLength={500}
        />
      </div>

      <div className="flex flex-wrap items-center gap-3">
        <Button type="submit" disabled={enviando}>
          {enviando ? "Lançando…" : "Lançar preparo"}
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
