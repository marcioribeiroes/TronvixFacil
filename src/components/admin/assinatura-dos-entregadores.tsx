"use client"

import { useState, useTransition } from "react"

import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { salvarAssinaturaDosEntregadores } from "@/modules/admin/plataforma"

/**
 * A mensalidade do autonomo: quando comeca, quanto custa, e para onde vai o
 * Pix. Sem data de inicio, a cobranca fica desligada - e o lancamento gratis.
 * Depois dela, cada motoboy tem 30 dias gratis a partir da aprovacao.
 */

type TipoDeChave = "cpf" | "cnpj" | "email" | "telefone" | "aleatoria"

const SELECT =
  "h-9 w-full rounded-lg border border-input bg-transparent px-2.5 text-sm outline-none focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50"

export function AssinaturaDosEntregadores({
  inicio,
  precoCentavos,
  chave,
  titular,
  cidade,
}: {
  inicio: string | null
  precoCentavos: number
  chave: string | null
  titular: string | null
  cidade: string | null
}) {
  const [enviando, iniciar] = useTransition()
  const [aviso, setAviso] = useState<{ tipo: "erro" | "ok"; texto: string } | null>(null)
  const [dados, setDados] = useState({
    inicio: inicio ?? "",
    preco: (precoCentavos / 100).toFixed(2).replace(".", ","),
    tipoDaChave: (chave?.startsWith("+55") ? "telefone" : chave?.includes("@") ? "email" : "aleatoria") as TipoDeChave,
    chave: chave ?? "",
    titular: titular ?? "",
    cidade: cidade ?? "",
  })

  const mudar = (campo: keyof typeof dados) => (valor: string) =>
    setDados((d) => ({ ...d, [campo]: valor }))

  function salvar() {
    setAviso(null)
    iniciar(async () => {
      const r = await salvarAssinaturaDosEntregadores(dados)
      setAviso(r.ok ? { tipo: "ok", texto: "Assinatura salva." } : { tipo: "erro", texto: r.erro })
    })
  }

  return (
    <form
      className="space-y-4 rounded-xl border bg-card p-5"
      noValidate
      onSubmit={(e) => {
        e.preventDefault()
        salvar()
      }}
    >
      <div>
        <h2 className="font-bold">Assinatura do entregador autônomo</h2>
        <p className="mt-1 text-sm text-muted-foreground">
          Deixe a data em branco para não cobrar (lançamento grátis). A partir dela, cada
          motoboy tem 30 dias grátis contados da aprovação; depois, paga por Pix e você confirma
          em Entregadores.
        </p>
      </div>

      <div className="grid gap-4 sm:grid-cols-2">
        <div className="space-y-2">
          <Label htmlFor="assinatura-inicio">Começar a cobrar em</Label>
          <Input
            id="assinatura-inicio"
            type="date"
            value={dados.inicio}
            onChange={(e) => mudar("inicio")(e.target.value)}
          />
        </div>
        <div className="space-y-2">
          <Label htmlFor="assinatura-preco">Valor por mês (R$)</Label>
          <Input
            id="assinatura-preco"
            inputMode="decimal"
            value={dados.preco}
            onChange={(e) => mudar("preco")(e.target.value)}
          />
        </div>
        <div className="space-y-2">
          <Label htmlFor="assinatura-tipo">Tipo da chave Pix</Label>
          <select
            id="assinatura-tipo"
            className={SELECT}
            value={dados.tipoDaChave}
            onChange={(e) => mudar("tipoDaChave")(e.target.value)}
          >
            <option value="cnpj">CNPJ</option>
            <option value="cpf">CPF</option>
            <option value="email">E-mail</option>
            <option value="telefone">Telefone</option>
            <option value="aleatoria">Aleatória</option>
          </select>
        </div>
        <div className="space-y-2">
          <Label htmlFor="assinatura-chave">Chave Pix da plataforma</Label>
          <Input
            id="assinatura-chave"
            value={dados.chave}
            onChange={(e) => mudar("chave")(e.target.value)}
          />
        </div>
        <div className="space-y-2">
          <Label htmlFor="assinatura-titular">Nome do titular</Label>
          <Input
            id="assinatura-titular"
            value={dados.titular}
            onChange={(e) => mudar("titular")(e.target.value)}
            placeholder="Tronvix Desenvolvimento"
          />
        </div>
        <div className="space-y-2">
          <Label htmlFor="assinatura-cidade">Cidade do titular</Label>
          <Input
            id="assinatura-cidade"
            value={dados.cidade}
            onChange={(e) => mudar("cidade")(e.target.value)}
            placeholder="Cachoeiro de Itapemirim"
          />
        </div>
      </div>

      <div className="flex flex-wrap items-center gap-3">
        <Button type="submit" disabled={enviando}>
          {enviando ? "Salvando…" : "Salvar assinatura"}
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
