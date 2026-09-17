"use client"

import Link from "next/link"
import { useActionState } from "react"

import { BotaoDeEnvio } from "@/components/auth/botao-de-envio"
import { CampoDeSenha } from "@/components/auth/campo-de-senha"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { entrar } from "@/modules/auth/acoes"

export function FormularioDeLogin({ voltarPara }: { voltarPara?: string }) {
  const [estado, acao] = useActionState(entrar, null)

  return (
    <form action={acao} className="space-y-4" noValidate>
      {voltarPara ? <input type="hidden" name="voltar_para" value={voltarPara} /> : null}

      <div className="space-y-2">
        <Label htmlFor="email">E-mail</Label>
        <Input
          id="email"
          name="email"
          type="email"
          inputMode="email"
          autoComplete="email"
          placeholder="voce@exemplo.com"
          required
          aria-invalid={estado?.ok === false && estado.campo === "email"}
        />
      </div>

      <div className="space-y-2">
        <div className="flex items-center justify-between">
          <Label htmlFor="senha">Senha</Label>
          <Link
            href="/recuperar-senha"
            className="text-xs font-medium text-marca hover:underline"
          >
            Esqueceu a senha?
          </Link>
        </div>
        <CampoDeSenha
          id="senha"
          name="senha"
          autoComplete="current-password"
          placeholder="••••••••"
          required
          aria-invalid={estado?.ok === false && estado.campo === "senha"}
        />
      </div>

      {estado?.ok === false ? (
        // role="alert" faz o leitor de tela anunciar o erro assim que ele
        // aparece, sem que a pessoa precise voltar para procurar.
        <p role="alert" className="rounded-md bg-destructive/10 px-3 py-2 text-sm text-destructive">
          {estado.erro}
        </p>
      ) : null}

      <BotaoDeEnvio className="w-full" carregando="Entrando...">
        Entrar
      </BotaoDeEnvio>
    </form>
  )
}
