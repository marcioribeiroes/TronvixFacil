"use server"

import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirUsuario } from "@/modules/auth/sessao"

/**
 * Guarda e apaga a inscricao de push do aparelho.
 *
 * Uma linha por aparelho: a mesma pessoa no computador do balcao e no celular
 * tem duas, e reinstalar o navegador gera um endereco novo. Quem limpa as
 * inscricoes mortas e a propria funcao de envio, quando o servico de push
 * responde 404 ou 410.
 */

export type ResultadoDaAcao = { ok: true } | { ok: false; erro: string }

export async function salvarInscricaoDePush(dados: {
  endpoint: string
  p256dh: string
  auth: string
  descricao?: string
}): Promise<ResultadoDaAcao> {
  const contexto = await exigirUsuario("/painel/pedidos")
  const supabase = await criarClienteDoServidor()

  const { error } = await supabase.from("push_subscriptions").upsert(
    {
      user_id: contexto.id,
      endpoint: dados.endpoint,
      p256dh: dados.p256dh,
      auth: dados.auth,
      descricao: dados.descricao ?? null,
    },
    { onConflict: "endpoint" },
  )

  if (error) return { ok: false, erro: error.message }
  return { ok: true }
}

export async function removerInscricaoDePush(endpoint: string): Promise<ResultadoDaAcao> {
  await exigirUsuario("/painel/pedidos")
  const supabase = await criarClienteDoServidor()

  const { error } = await supabase.from("push_subscriptions").delete().eq("endpoint", endpoint)
  if (error) return { ok: false, erro: error.message }
  return { ok: true }
}

/** Este aparelho já está inscrito? */
export async function temInscricao(endpoint: string): Promise<boolean> {
  const contexto = await exigirUsuario("/painel/pedidos")
  const supabase = await criarClienteDoServidor()

  const { count } = await supabase
    .from("push_subscriptions")
    .select("id", { count: "exact", head: true })
    .eq("user_id", contexto.id)
    .eq("endpoint", endpoint)

  return (count ?? 0) > 0
}
