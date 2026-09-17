/**
 * Leitura das variaveis de ambiente.
 *
 * O objetivo e falhar cedo e com uma mensagem util. Uma variavel faltando
 * detectada aqui vira um erro claro na subida; detectada la na frente, vira
 * um "Invalid API key" sem contexto no meio de um checkout.
 *
 * O que leva NEXT_PUBLIC_ vai para o navegador e e publico por definicao. O
 * resto e do servidor e nunca pode ser importado por um componente de cliente.
 */

function obrigatoria(nome: string, valor: string | undefined): string {
  if (!valor || valor.trim() === "") {
    throw new Error(
      `Variavel de ambiente ausente: ${nome}. ` +
        `Copie .env.example para .env.local e preencha antes de subir o projeto.`,
    )
  }
  return valor
}

/** Configuracao publica: pode ir para o navegador. */
export const ambientePublico = {
  supabaseUrl: process.env.NEXT_PUBLIC_SUPABASE_URL ?? "",
  supabaseAnonKey: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "",
  nomeDaMarca: process.env.NEXT_PUBLIC_NOME_DA_MARCA ?? "Tronvix Facil",
  urlDoSite: process.env.NEXT_PUBLIC_URL_DO_SITE ?? "http://localhost:3000",
}

/**
 * O projeto esta conectado a um Supabase?
 *
 * Existe para que as telas possam mostrar uma instrucao de configuracao em vez
 * de uma tela branca com erro quando o .env.local ainda nao foi preenchido.
 */
export function supabaseConfigurado(): boolean {
  return Boolean(ambientePublico.supabaseUrl && ambientePublico.supabaseAnonKey)
}

export function exigirAmbientePublico() {
  return {
    supabaseUrl: obrigatoria("NEXT_PUBLIC_SUPABASE_URL", ambientePublico.supabaseUrl),
    supabaseAnonKey: obrigatoria("NEXT_PUBLIC_SUPABASE_ANON_KEY", ambientePublico.supabaseAnonKey),
  }
}

/**
 * Chave de servico. Ignora RLS por completo - e o unico segredo do projeto que
 * nunca, em nenhuma hipotese, pode chegar ao navegador.
 */
export function chaveDeServico(): string {
  return obrigatoria("SUPABASE_SERVICE_ROLE_KEY", process.env.SUPABASE_SERVICE_ROLE_KEY)
}
