"use server"

import { revalidatePath } from "next/cache"

import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirAdminDaPlataforma } from "@/modules/auth/sessao"

/**
 * O que a plataforma decide sobre um estabelecimento.
 *
 * Nenhuma destas acoes confere se quem chamou e administrador por conta
 * propria - `exigirAdminDaPlataforma` redireciona quem nao e, e a RLS recusa
 * de qualquer jeito: `app.guard_restaurant_platform_fields` so deixa a
 * plataforma mexer em status e comissao. A tela e a terceira tranca, nao a
 * primeira.
 */

export type ResultadoDaAcao = { ok: true } | { ok: false; erro: string }

type Situacao = "pending" | "approved" | "suspended" | "rejected"

const VERBO: Record<Situacao, string> = {
  approved: "aprovar",
  suspended: "suspender",
  rejected: "recusar",
  pending: "voltar para analise",
}

export async function decidirSobreEstabelecimento(
  id: string,
  situacao: Situacao,
): Promise<ResultadoDaAcao> {
  await exigirAdminDaPlataforma()
  const supabase = await criarClienteDoServidor()

  const { error } = await supabase
    .from("restaurants")
    .update({
      status: situacao,
      // Aprovar carimba a data; as outras decisoes nao apagam o carimbo
      // anterior - saber que um estabelecimento ja foi aprovado um dia e
      // informacao, nao ruido.
      ...(situacao === "approved" ? { approved_at: new Date().toISOString() } : {}),
      // Suspenso ou recusado nao pode continuar aberto recebendo pedido.
      ...(situacao === "approved" ? {} : { is_open: false }),
    })
    .eq("id", id)

  if (error) {
    return { ok: false, erro: `Não consegui ${VERBO[situacao]}: ${error.message}` }
  }

  revalidatePath("/admin/restaurantes")
  return { ok: true }
}

/**
 * A comissao, em pontos base. 1000 = 10,00%.
 *
 * Inteiro ate o banco, sem passar por ponto flutuante em nenhum momento: a
 * mesma razao pela qual dinheiro e centavos neste projeto.
 */
export async function mudarComissao(
  id: string,
  pontosBase: number,
): Promise<ResultadoDaAcao> {
  await exigirAdminDaPlataforma()

  if (!Number.isInteger(pontosBase) || pontosBase < 0 || pontosBase > 5000) {
    return { ok: false, erro: "A comissão vai de 0% a 50%." }
  }

  const supabase = await criarClienteDoServidor()
  const { error } = await supabase
    .from("restaurants")
    .update({ commission_bps: pontosBase })
    .eq("id", id)

  if (error) {
    return { ok: false, erro: `Não consegui mudar a comissão: ${error.message}` }
  }

  revalidatePath("/admin/restaurantes")
  return { ok: true }
}
