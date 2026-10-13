"use client"

import { useState, useTransition } from "react"
import { ArrowDownToLine, ArrowUpFromLine } from "lucide-react"

import { Button } from "@/components/ui/button"
import { cancelarLancamento, registrarFundo, registrarSangria } from "@/modules/caixa/acoes"

/**
 * Os formularios do caixa: fundo de caixa e sangria.
 *
 * O valor e digitado como se fala ("150", "150,00", "R$ 150") e vira centavos
 * no servidor, por `paraCentavos`. Nenhum float no caminho.
 */

function Erro({ texto }: { texto: string | null }) {
  if (!texto) return null
  return (
    <p role="alert" className="text-sm font-medium text-destructive">
      {texto}
    </p>
  )
}

const campo = "h-10 rounded-lg border bg-background px-3 text-sm"

export function RegistrarFundo() {
  const [enviando, iniciar] = useTransition()
  const [erro, setErro] = useState<string | null>(null)
  const [valor, setValor] = useState("")

  function enviar(e: React.FormEvent) {
    e.preventDefault()
    setErro(null)
    iniciar(async () => {
      const r = await registrarFundo({ valor })
      if (r.ok) setValor("")
      else setErro(r.erro)
    })
  }

  return (
    <form onSubmit={enviar} className="space-y-3 rounded-xl border bg-card p-4">
      <div className="flex items-center gap-2">
        <ArrowDownToLine className="size-4 text-muted-foreground" aria-hidden="true" />
        <h2 className="font-semibold">Fundo de caixa</h2>
      </div>
      <p className="text-sm text-muted-foreground">
        O dinheiro que fica na gaveta para troco, antes do primeiro cliente. Um por dia.
      </p>
      <div className="flex gap-2">
        <label htmlFor="valor-do-fundo" className="sr-only">
          Valor do fundo de caixa
        </label>
        <input
          id="valor-do-fundo"
          inputMode="decimal"
          placeholder="R$ 0,00"
          value={valor}
          onChange={(e) => setValor(e.target.value)}
          className={`${campo} w-32`}
        />
        <Button type="submit" disabled={enviando || valor.trim() === ""}>
          Registrar fundo
        </Button>
      </div>
      <Erro texto={erro} />
    </form>
  )
}

export function RegistrarSangria() {
  const [enviando, iniciar] = useTransition()
  const [erro, setErro] = useState<string | null>(null)
  const [valor, setValor] = useState("")
  const [motivo, setMotivo] = useState("")

  function enviar(e: React.FormEvent) {
    e.preventDefault()
    setErro(null)
    iniciar(async () => {
      const r = await registrarSangria({ valor, motivo })
      if (r.ok) {
        setValor("")
        setMotivo("")
      } else setErro(r.erro)
    })
  }

  return (
    <form onSubmit={enviar} className="space-y-3 rounded-xl border bg-card p-4">
      <div className="flex items-center gap-2">
        <ArrowUpFromLine className="size-4 text-muted-foreground" aria-hidden="true" />
        <h2 className="font-semibold">Sangria</h2>
      </div>
      <p className="text-sm text-muted-foreground">
        Dinheiro que sai da gaveta no meio do dia — para o cofre, para o banco, para pagar
        um fornecedor.
      </p>
      <div className="flex flex-wrap gap-2">
        <label htmlFor="valor-da-sangria" className="sr-only">
          Valor da sangria
        </label>
        <input
          id="valor-da-sangria"
          inputMode="decimal"
          placeholder="R$ 0,00"
          value={valor}
          onChange={(e) => setValor(e.target.value)}
          className={`${campo} w-32`}
        />
        <label htmlFor="motivo-da-sangria" className="sr-only">
          Motivo da sangria
        </label>
        <input
          id="motivo-da-sangria"
          placeholder="Motivo"
          value={motivo}
          onChange={(e) => setMotivo(e.target.value)}
          className={`${campo} min-w-40 flex-1`}
        />
        <Button
          type="submit"
          variant="outline"
          disabled={enviando || valor.trim() === "" || motivo.trim() === ""}
        >
          Registrar sangria
        </Button>
      </div>
      <Erro texto={erro} />
    </form>
  )
}

/** So aparece para a gestao; quem decide de verdade e o banco. */
export function CancelarLancamento({ id, descricao }: { id: string; descricao: string }) {
  const [enviando, iniciar] = useTransition()
  const [erro, setErro] = useState<string | null>(null)

  function cancelar() {
    if (!window.confirm(`Cancelar ${descricao}? O lançamento continua no relatório, riscado.`)) {
      return
    }
    setErro(null)
    iniciar(async () => {
      const r = await cancelarLancamento(id)
      if (!r.ok) setErro(r.erro)
    })
  }

  return (
    <span className="inline-flex items-center gap-2">
      <Button variant="ghost" size="sm" onClick={cancelar} disabled={enviando}>
        Cancelar
      </Button>
      {erro ? <span className="text-xs text-destructive">{erro}</span> : null}
    </span>
  )
}
