"use server"

import { revalidatePath } from "next/cache"
import { z } from "zod"

import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirAdminDaPlataforma } from "@/modules/auth/sessao"

/**
 * A comissao, cobrada por mes.
 *
 * O dinheiro do pedido vai direto do cliente para a loja — nao ha operadora
 * no meio para reter a parte da plataforma. Entao a plataforma fecha o mes
 * (`gerar_fechamento_de_comissoes`), cobra cada loja e da baixa quando recebe
 * (`marcar_comissao_paga`). As regras moram no banco.
 */

type Resultado = { ok: true } | { ok: false; erro: string }

const MES = /^\d{4}-\d{2}$/

export async function gerarFechamento(mes: string): Promise<Resultado> {
  await exigirAdminDaPlataforma()
  if (!MES.test(mes)) return { ok: false, erro: "Mês inválido." }

  const supabase = await criarClienteDoServidor()
  const { error } = await supabase.rpc("gerar_fechamento_de_comissoes", { p_mes: `${mes}-01` })
  if (error) return { ok: false, erro: error.message }

  revalidatePath("/admin/financeiro")
  return { ok: true }
}

export async function marcarComissaoPaga(id: string, observacao: string): Promise<Resultado> {
  await exigirAdminDaPlataforma()
  if (!z.uuid().safeParse(id).success) return { ok: false, erro: "Extrato inválido." }

  const supabase = await criarClienteDoServidor()
  const { error } = await supabase.rpc("marcar_comissao_paga", {
    p_extrato: id,
    p_observacao: observacao.trim().slice(0, 200),
  })
  if (error) return { ok: false, erro: error.message }

  revalidatePath("/admin/financeiro")
  return { ok: true }
}
