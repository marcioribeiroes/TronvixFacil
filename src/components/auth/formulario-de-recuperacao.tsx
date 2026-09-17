"use client"

import { CheckCircle2 } from "lucide-react"
import { useActionState } from "react"

import { BotaoDeEnvio } from "@/components/auth/botao-de-envio"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { pedirRecuperacao } from "@/modules/auth/acoes"

export function FormularioDeRecuperacao() {
  const [estado, acao] = useActionState(pedirRecuperacao, null)

  if (estado?.ok) {
    return (
      <div className="rounded-lg border border-status-pronto/30 bg-status-pronto/10 p-4">
        <CheckCircle2 className="size-5 text-status-pronto" aria-hidden="true" />
        <p className="mt-2 text-sm text-foreground">{estado.mensagem}</p>
      </div>
    )
  }

  return (
    <form action={acao} className="space-y-4" noValidate>
      <div className="space-y-2">
        <Label htmlFor="email">E-mail da conta</Label>
        <Input
          id="email"
          name="email"
          type="email"
          inputMode="email"
          autoComplete="email"
          placeholder="voce@exemplo.com"
          required
          aria-invalid={estado?.ok === false}
        />
      </div>

      {estado?.ok === false ? (
        <p role="alert" className="rounded-md bg-destructive/10 px-3 py-2 text-sm text-destructive">
          {estado.erro}
        </p>
      ) : null}

      <BotaoDeEnvio className="w-full" carregando="Enviando...">
        Enviar link de recuperação
      </BotaoDeEnvio>
    </form>
  )
}
