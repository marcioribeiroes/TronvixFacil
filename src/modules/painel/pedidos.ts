"use server"

import { revalidatePath } from "next/cache"

import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import {
  transicaoDoPedidoPermitida,
  type SituacaoDoPedido,
  type TipoDeEntrega,
} from "@/modules/pedidos/maquina-de-estados"
import { exigirVinculo } from "@/modules/auth/sessao"

/**
 * O que o balcao faz com um pedido.
 *
 * Atendente tambem mexe na fila - e o trabalho dele. Quem nao pode e quem nao
 * tem vinculo nenhum, e disso cuida `exigirVinculo`; a RLS confere de novo, e
 * o gatilho `app.guard_order_status` recusa transicao invalida mesmo que a
 * tela ofereca por engano.
 */

export type ResultadoDaAcao = { ok: true } | { ok: false; erro: string }

export async function avancarPedido(
  id: string,
  destino: SituacaoDoPedido,
): Promise<ResultadoDaAcao> {
  const { vinculo } = await exigirVinculo()
  const supabase = await criarClienteDoServidor()

  const { data: pedido, error: erroDeLeitura } = await supabase
    .from("orders")
    .select("id, status, fulfillment, restaurant_id")
    .eq("id", id)
    .single()

  if (erroDeLeitura || !pedido) {
    return { ok: false, erro: "Não achei esse pedido." }
  }
  if (pedido.restaurant_id !== vinculo.restauranteId) {
    // A RLS ja teria escondido o pedido; isto e a mensagem, nao a tranca.
    return { ok: false, erro: "Esse pedido não é deste estabelecimento." }
  }

  const atual = pedido.status as SituacaoDoPedido
  const tipo = pedido.fulfillment as TipoDeEntrega

  if (!transicaoDoPedidoPermitida(atual, destino, tipo)) {
    return { ok: false, erro: "Esse passo não é possível a partir de agora." }
  }

  const { error } = await supabase.from("orders").update({ status: destino }).eq("id", id)
  if (error) return { ok: false, erro: error.message }

  // Despachar poe a corrida na fila dos entregadores do estabelecimento. Sem
  // isto, "saiu para entrega" seria so uma etiqueta e ninguem seria chamado.
  if (destino === "out_for_delivery") {
    await supabase
      .from("deliveries")
      .update({ status: "searching_courier" })
      .eq("order_id", id)
      .eq("status", "pending")
  }

  revalidatePath("/painel/pedidos")
  revalidatePath("/painel")
  return { ok: true }
}

/**
 * Chamar o entregador, com a previsao de quando a comida fica pronta.
 *
 * Existe separado de `avancarPedido` porque sao duas decisoes diferentes. Ate
 * aqui um clique so fazia as duas — marcava o pedido como saido E procurava
 * quem levasse — e dai ou a comida esperava entregador depois de pronta, ou o
 * balcao clicava cedo e a tela do cliente dizia "saiu para entrega" com o
 * pedido ainda no balcao.
 *
 * Os minutos nao sao enfeite: sao o unico numero que deixa o entregador
 * aceitar a corrida e chegar na hora, em vez de correr ate a loja e esperar la.
 *
 * A regra mora em `public.chamar_entregador`: quem pode chamar, de quais
 * situacoes, e a transacao que poe a corrida na fila junto com a previsao.
 */
export async function chamarEntregador(
  id: string,
  minutos: number,
): Promise<ResultadoDaAcao> {
  await exigirVinculo()

  if (!Number.isInteger(minutos) || minutos < 0 || minutos > 180) {
    return { ok: false, erro: "A previsão tem de estar entre 0 e 180 minutos." }
  }

  const supabase = await criarClienteDoServidor()
  const { error } = await supabase.rpc("chamar_entregador", {
    p_pedido: id,
    p_minutos: minutos,
  })

  if (error) return { ok: false, erro: error.message }

  revalidatePath("/painel/pedidos")
  revalidatePath("/painel")
  return { ok: true }
}

/**
 * Recusar exige motivo.
 *
 * O motivo vai para `cancellation_reason`, o gatilho o copia para o historico,
 * e e ele que o cliente le na tela de acompanhamento. Recusa sem explicacao e
 * a reclamacao do dia seguinte.
 */
export async function recusarPedido(id: string, motivo: string): Promise<ResultadoDaAcao> {
  await exigirVinculo()

  const limpo = motivo.trim()
  if (limpo.length < 3) {
    return { ok: false, erro: "Diga o motivo — o cliente vê essa mensagem." }
  }

  const supabase = await criarClienteDoServidor()
  const { error } = await supabase
    .from("orders")
    .update({ status: "rejected", cancellation_reason: limpo })
    .eq("id", id)

  if (error) return { ok: false, erro: error.message }

  revalidatePath("/painel/pedidos")
  revalidatePath("/painel")
  return { ok: true }
}

export async function abrirOuFecharLoja(aberto: boolean): Promise<ResultadoDaAcao> {
  const { vinculo } = await exigirVinculo()
  const supabase = await criarClienteDoServidor()

  const { error } = await supabase
    .from("restaurants")
    .update({ is_open: aberto })
    .eq("id", vinculo.restauranteId)

  if (error) return { ok: false, erro: error.message }

  revalidatePath("/painel/pedidos")
  revalidatePath("/painel")
  return { ok: true }
}

/**
 * O balcao confirma que o Pix caiu.
 *
 * Nao ha provedor de pagamento: o dinheiro vai direto do cliente para a conta
 * do restaurante, e quem ve o dinheiro entrar e o dono. Por isso a confirmacao
 * e um ato de gente, e nao um webhook.
 *
 * A regra inteira vive em `confirmar_pix`, no banco: marcar o pagamento e
 * soltar o pedido acontecem na mesma transacao. Separadas, uma poderia
 * acontecer sem a outra — pagamento pago com pedido parado.
 */
export async function confirmarPix(id: string): Promise<ResultadoDaAcao> {
  await exigirVinculo()
  const supabase = await criarClienteDoServidor()

  const { error } = await supabase.rpc("confirmar_pix", { p_pedido: id })
  if (error) return { ok: false, erro: error.message }

  revalidatePath("/painel/pedidos")
  revalidatePath("/painel")
  return { ok: true }
}
