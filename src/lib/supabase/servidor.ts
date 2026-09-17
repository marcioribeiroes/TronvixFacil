import "server-only"

import { createServerClient } from "@supabase/ssr"
import { cookies } from "next/headers"

import { exigirAmbientePublico } from "@/lib/ambiente"
import type { Banco } from "@/types/banco"

/**
 * Cliente Supabase do servidor, com a sessao do usuario da requisicao.
 *
 * Continua sujeito a RLS: e o cliente certo para tudo que o usuario tem
 * direito de ver e fazer. Componentes de servidor, Server Actions e rotas de
 * API usam este.
 */
export async function criarClienteDoServidor() {
  const { supabaseUrl, supabaseAnonKey } = exigirAmbientePublico()
  const armazem = await cookies()

  return createServerClient<Banco>(supabaseUrl, supabaseAnonKey, {
    cookies: {
      getAll() {
        return armazem.getAll()
      },
      setAll(cookiesParaGravar) {
        try {
          for (const { name, value, options } of cookiesParaGravar) {
            armazem.set(name, value, options)
          }
        } catch {
          // Componentes de servidor nao podem gravar cookie. Quem renova a
          // sessao e o proxy (src/proxy.ts), entao ignorar aqui e correto -
          // nao e um erro escondido.
        }
      },
    },
  })
}
