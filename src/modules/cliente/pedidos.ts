"use server"

import { revalidatePath } from "next/cache"
import { z } from "zod"

import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirUsuario } from "@/modules/auth/sessao"
import { schemaDoItemNovo, type ItemNovo } from "@/modules/pedidos/edicao"

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

const schemaDoPedirMais = z.array(schemaDoItemNovo).min(1, "Escolha ao menos um item.").max(50)

/**
 * O cliente da mesa acrescenta itens ao proprio pedido.
 *
 * So acrescenta, e so na mesa, enquanto o pedido esta aberto e nao foi pago.
 * Preco, adicionais e estoque sao conferidos em `pedir_mais_na_mesa`, como no
 * fechamento: a tela manda o que o cliente quer, o banco diz quanto custa.
 */
export async function pedirMaisNaMesa(id: string, itens: ItemNovo[]): Promise<ResultadoDaAcao> {
  await exigirUsuario(`/pedidos/${id}`)

  const dados = schemaDoPedirMais.safeParse(itens)
  if (!z.uuid().safeParse(id).success || !dados.success) {
    return { ok: false, erro: dados.error?.issues[0]?.message ?? "Confira os itens." }
  }

  const supabase = await criarClienteDoServidor()
  const { error } = await supabase.rpc("pedir_mais_na_mesa", {
    p_pedido: id,
    p_itens: dados.data,
  })
  if (error) return { ok: false, erro: error.message }

  revalidatePath(`/pedidos/${id}`)
  return { ok: true }
}
