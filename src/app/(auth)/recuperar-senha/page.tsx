import type { Metadata } from "next"
import Link from "next/link"
import { ArrowLeft } from "lucide-react"

import { FormularioDeRecuperacao } from "@/components/auth/formulario-de-recuperacao"
import { AvisoDeConfiguracao } from "@/components/aviso-de-configuracao"
import { supabaseConfigurado } from "@/lib/ambiente"

export const metadata: Metadata = { title: "Recuperar senha" }

export default async function PaginaDeRecuperacao({
  searchParams,
}: PageProps<"/recuperar-senha">) {
  const parametros = await searchParams
  const linkInvalido = parametros.link === "invalido"

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

      {linkInvalido ? (
        <p role="alert" className="rounded-md bg-destructive/10 px-3 py-2 text-sm text-destructive">
          Este link de recuperação expirou ou já foi usado. Peça um novo abaixo e abra-o no mesmo
          navegador em que fez o pedido.
        </p>
      ) : null}

      {supabaseConfigurado() ? <FormularioDeRecuperacao /> : <AvisoDeConfiguracao />}
    </div>
  )
}
