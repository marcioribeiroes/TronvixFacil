import type { Metadata } from "next"
import Link from "next/link"

import { FormularioDeCadastro } from "@/components/auth/formulario-de-cadastro"
import { LogoTronvixFacil } from "@/components/marca/logo"
import { AvisoDeConfiguracao } from "@/components/aviso-de-configuracao"
import { supabaseConfigurado } from "@/lib/ambiente"

export const metadata: Metadata = { title: "Criar conta" }

export default function PaginaDeCadastro() {
  return (
    <div className="space-y-8">
      <div className="lg:hidden">
        <LogoTronvixFacil tamanho="md" />
      </div>

      <div>
        <h1 className="text-2xl font-bold tracking-tight">Criar conta</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Leva menos de um minuto. Depois é só pedir.
        </p>
      </div>

      {supabaseConfigurado() ? <FormularioDeCadastro /> : <AvisoDeConfiguracao />}

      <p className="text-center text-sm text-muted-foreground">
        Já tem conta?{" "}
        <Link href="/entrar" className="font-semibold text-marca hover:underline">
          Entrar
        </Link>
      </p>
    </div>
  )
}
