import type { Metadata } from "next"

import { FormularioDeNovaSenha } from "@/components/auth/formulario-de-nova-senha"
import { AvisoDeConfiguracao } from "@/components/aviso-de-configuracao"
import { supabaseConfigurado } from "@/lib/ambiente"

export const metadata: Metadata = { title: "Nova senha" }

/**
 * Destino do link enviado por e-mail. O Supabase ja troca o token por uma
 * sessao antes de a pagina carregar, entao aqui basta gravar a senha nova.
 */
export default function PaginaDeNovaSenha() {
  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">Criar nova senha</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Escolha uma senha com pelo menos 8 caracteres, entre letras e números.
        </p>
      </div>

      {supabaseConfigurado() ? <FormularioDeNovaSenha /> : <AvisoDeConfiguracao />}
    </div>
  )
}
