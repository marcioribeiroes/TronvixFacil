"use client"

import { useState, useTransition } from "react"
import { useRouter } from "next/navigation"

import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { apagarMinhaConta } from "@/modules/auth/acoes"

/** O que a pessoa precisa digitar. Maiusculas, e sem acento por engano. */
const CONFIRMACAO = "APAGAR"

/**
 * O botao que apaga a conta.
 *
 * Pede a palavra digitada porque isto nao se desfaz — e um clique acidental
 * aqui custa o historico de pedidos de alguem. Nao e burocracia: e o unico
 * freio que existe antes de uma operacao sem volta.
 *
 * As recusas vem do banco em portugues ("Voce tem 1 pedido(s) em andamento…")
 * e sao mostradas como estao: sao instrucoes, nao codigos de erro.
 */
export function ApagarConta() {
  const [texto, setTexto] = useState("")
  const [erro, setErro] = useState<string | null>(null)
  const [enviando, iniciar] = useTransition()
  const router = useRouter()

  return (
    <form
      className="space-y-4 rounded-lg border border-destructive/40 bg-destructive/5 p-5"
      onSubmit={(evento) => {
        evento.preventDefault()
        setErro(null)
        iniciar(async () => {
          const resultado = await apagarMinhaConta()
          if (!resultado.ok) {
            setErro(resultado.erro)
            return
          }
          router.replace("/conta-apagada")
        })
      }}
    >
      <div className="space-y-2">
        <Label htmlFor="confirmacao">
          Para confirmar, digite <strong>{CONFIRMACAO}</strong>
        </Label>
        <Input
          id="confirmacao"
          value={texto}
          onChange={(e) => setTexto(e.target.value)}
          autoComplete="off"
          className="max-w-48 bg-background"
          aria-describedby={erro ? "erro-apagar" : undefined}
        />
      </div>

      {erro && (
        <p id="erro-apagar" className="text-sm font-medium text-destructive">
          {erro}
        </p>
      )}

      <Button
        type="submit"
        variant="destructive"
        disabled={texto.trim().toUpperCase() !== CONFIRMACAO || enviando}
      >
        {enviando ? "Apagando…" : "Apagar minha conta"}
      </Button>
    </form>
  )
}
