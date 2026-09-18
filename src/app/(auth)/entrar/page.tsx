import type { Metadata } from "next"
import Link from "next/link"

import { FormularioDeLogin } from "@/components/auth/formulario-de-login"
import { AvisoDeConfiguracao } from "@/components/aviso-de-configuracao"
import { supabaseConfigurado } from "@/lib/ambiente"

export const metadata: Metadata = { title: "Entrar" }

export default async function PaginaDeLogin({ searchParams }: PageProps<"/entrar">) {
  // No Next 16 searchParams chega como Promise.
  const parametros = await searchParams
  const voltarPara = typeof parametros.voltar_para === "string" ? parametros.voltar_para : undefined

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">Acesse sua conta</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Clientes, restaurantes e entregadores entram por aqui.
        </p>
      </div>

      {supabaseConfigurado() ? <FormularioDeLogin voltarPara={voltarPara} /> : <AvisoDeConfiguracao />}

      <div className="space-y-3 text-center text-sm text-muted-foreground">
        <p>
          Ainda não tem conta?{" "}
          <Link href="/criar-conta" className="font-semibold text-marca hover:underline">
            Cadastre-se
          </Link>
        </p>
        <p className="border-t pt-3">
          Tem um restaurante?{" "}
          <Link
            href="/cadastrar-restaurante"
            className="font-semibold text-marca hover:underline"
          >
            Coloque no ar
          </Link>
        </p>
      </div>
    </div>
  )
}
