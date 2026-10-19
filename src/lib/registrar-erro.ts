import { ambientePublico } from "@/lib/ambiente"

/**
 * Manda um erro para `registrar_erro`, no banco.
 *
 * Serve ao servidor e ao navegador: e um `fetch` direto na API do Supabase,
 * com a chave publica, sem depender de sessao nem de biblioteca. Nunca lanca:
 * o registro de um erro que falha nao pode virar um segundo erro na tela.
 */
export async function registrarErro(erro: {
  origem: "servidor" | "navegador"
  mensagem: string
  pilha?: string | null
  endereco?: string | null
  contexto?: Record<string, unknown> | null
}): Promise<void> {
  const { supabaseUrl, supabaseAnonKey } = ambientePublico
  if (!supabaseUrl || !supabaseAnonKey || !erro.mensagem) return

  try {
    await fetch(`${supabaseUrl}/rest/v1/rpc/registrar_erro`, {
      method: "POST",
      headers: {
        apikey: supabaseAnonKey,
        Authorization: `Bearer ${supabaseAnonKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        p_origem: erro.origem,
        p_mensagem: erro.mensagem,
        p_pilha: erro.pilha ?? null,
        p_endereco: erro.endereco ?? null,
        p_versao: process.env.NEXT_PUBLIC_VERCEL_GIT_COMMIT_SHA?.slice(0, 7) ?? null,
        p_contexto: erro.contexto ?? null,
      }),
      keepalive: true,
    })
  } catch {
    // Sem rede, sem registro. O erro original segue o caminho dele.
  }
}
