import type { Metadata } from "next"
import Link from "next/link"
import { ArrowLeft } from "lucide-react"

import { FormularioDeRecuperacao } from "@/components/auth/formulario-de-recuperacao"
import { AvisoDeConfiguracao } from "@/components/aviso-de-configuracao"
import { supabaseConfigurado } from "@/lib/ambiente"

export const metadata: Metadata = { title: "Recuperar senha" }

export default function PaginaDeRecuperacao() {
  return (
    <div className="space-y-8">
      <Link
        href="/entrar"
        className="inline-flex items-center gap-1.5 text-sm text-muted-foreground hover:text-foreground"
      >
        <ArrowLeft className="size-4" aria-hidden="true" />
        Voltar para o login
      </Link>

      <div>
        <h1 className="text-2xl font-bold tracking-tight">Recuperar senha</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Informe o e-mail da conta e enviaremos um link para criar uma nova senha.
        </p>
      </div>

      {supabaseConfigurado() ? <FormularioDeRecuperacao /> : <AvisoDeConfiguracao />}
    </div>
  )
}
