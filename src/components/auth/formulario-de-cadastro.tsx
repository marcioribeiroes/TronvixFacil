"use client"

import { useActionState } from "react"

import { BotaoDeEnvio } from "@/components/auth/botao-de-envio"
import { CampoDeSenha } from "@/components/auth/campo-de-senha"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { criarConta } from "@/modules/auth/acoes"

export function FormularioDeCadastro() {
  const [estado, acao] = useActionState(criarConta, null)

  const erroNoCampo = (campo: string) => estado?.ok === false && estado.campo === campo

  return (
    <form action={acao} className="space-y-4" noValidate>
      <div className="space-y-2">
        <Label htmlFor="nome">Nome completo</Label>
        <Input
          id="nome"
          name="nome"
          autoComplete="name"
          placeholder="Maria Souza"
          required
          aria-invalid={erroNoCampo("nome")}
        />
      </div>

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
          aria-invalid={erroNoCampo("email")}
        />
      </div>

      <div className="space-y-2">
        <Label htmlFor="telefone">Celular</Label>
        <Input
          id="telefone"
          name="telefone"
          type="tel"
          inputMode="tel"
          autoComplete="tel"
          placeholder="(62) 90000-0000"
          required
          aria-invalid={erroNoCampo("telefone")}
        />
        <p className="text-xs text-muted-foreground">
          É por ele que o entregador fala com você.
        </p>
      </div>

      <div className="space-y-2">
        <Label htmlFor="senha">Senha</Label>
        <CampoDeSenha
          id="senha"
          name="senha"
          autoComplete="new-password"
          placeholder="Mínimo de 8 caracteres"
          required
          aria-invalid={erroNoCampo("senha")}
        />
      </div>

      <div className="space-y-2">
        <Label htmlFor="confirmacao">Confirmar senha</Label>
        <CampoDeSenha
          id="confirmacao"
          name="confirmacao"
          autoComplete="new-password"
          placeholder="Repita a senha"
          required
          aria-invalid={erroNoCampo("confirmacao")}
        />
      </div>

      {estado?.ok === false ? (
        <p role="alert" className="rounded-md bg-destructive/10 px-3 py-2 text-sm text-destructive">
          {estado.erro}
        </p>
      ) : null}

      <BotaoDeEnvio className="w-full" carregando="Criando conta...">
        Criar conta
      </BotaoDeEnvio>
    </form>
  )
}
