"use client"

import { CheckCircle2 } from "lucide-react"
import Link from "next/link"
import { useActionState } from "react"

import { BotaoDeEnvio } from "@/components/auth/botao-de-envio"
import { CampoDeSenha } from "@/components/auth/campo-de-senha"
import { Button } from "@/components/ui/button"
import { Label } from "@/components/ui/label"
import { definirNovaSenha } from "@/modules/auth/acoes"

export function FormularioDeNovaSenha() {
  const [estado, acao] = useActionState(definirNovaSenha, null)

  if (estado?.ok) {
    return (
      <div className="space-y-4">
        <div className="rounded-lg border border-status-pronto/30 bg-status-pronto/10 p-4">
          <CheckCircle2 className="size-5 text-status-pronto" aria-hidden="true" />
          <p className="mt-2 text-sm">{estado.mensagem}</p>
        </div>
        <Button size="lg" className="w-full" render={<Link href="/entrar" />}>
          Ir para o login
        </Button>
      </div>
    )
  }

  return (
    <form action={acao} className="space-y-4" noValidate>
      <div className="space-y-2">
        <Label htmlFor="senha">Nova senha</Label>
        <CampoDeSenha id="senha" name="senha" autoComplete="new-password" required />
      </div>

      <div className="space-y-2">
        <Label htmlFor="confirmacao">Confirmar nova senha</Label>
        <CampoDeSenha id="confirmacao" name="confirmacao" autoComplete="new-password" required />
      </div>

      {estado?.ok === false ? (
        <p role="alert" className="rounded-md bg-destructive/10 px-3 py-2 text-sm text-destructive">
          {estado.erro}
        </p>
      ) : null}

      <BotaoDeEnvio className="w-full" carregando="Salvando...">
        Salvar nova senha
      </BotaoDeEnvio>
    </form>
  )
}
