"use server"

import { revalidatePath } from "next/cache"

import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirUsuario } from "@/modules/auth/sessao"

/**
 * O que o cliente faz com o proprio pedido.
 *
 * Por enquanto, uma coisa so: desistir. E ele desiste ate a loja aceitar —
 * depois disso a comida esta sendo feita, e quem paga a conta do cancelamento
 * e o restaurante. A regra inteira vive em `cancelar_pedido`, no banco, junto
 * com a decisao de QUEM cancelou.
 */

export type ResultadoDaAcao = { ok: true } | { ok: false; erro: string }

export async function cancelarMeuPedido(id: string): Promise<ResultadoDaAcao> {
  await exigirUsuario("/pedidos")
  const supabase = await criarClienteDoServidor()

  // Sem motivo: o cliente nao deve explicacao por desistir. O banco poe o
  // texto padrao, e e ele que o balcao le.
  const { error } = await supabase.rpc("cancelar_pedido", { p_pedido: id })
  if (error) return { ok: false, erro: error.message }

  revalidatePath("/pedidos")
  revalidatePath(`/pedidos/${id}`)
  return { ok: true }
}
