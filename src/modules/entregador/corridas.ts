"use server"

import { revalidatePath } from "next/cache"

import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirEntregador } from "@/modules/auth/sessao"
import {
  transicaoDaEntregaPermitida,
  type SituacaoDaEntrega,
} from "@/modules/pedidos/maquina-de-estados"

/**
 * O que o entregador faz, pelo navegador.
 *
 * Espelho de celular/lib/dados/corridas.dart. As duas telas falam com o mesmo
 * banco e obedecem as mesmas travas - a diferenca e so quem esta na frente:
 * quem instalou o aplicativo, e quem abriu o link no celular emprestado.
 *
 * A regra que importa esta no banco, nao aqui: `app.guard_delivery_status`
 * recusa transicao invalida, e `app.guard_courier_platform_fields` impede o
 * entregador de mexer no proprio contador de entregas.
 */

export type ResultadoDaAcao = { ok: true } | { ok: false; erro: string }

/**
 * Aceitar a corrida - se ela ainda estiver na fila.
 *
 * O `eq("status", "searching_courier")` dentro do proprio UPDATE e a trava
 * contra dois entregadores aceitando ao mesmo tempo: o segundo nao encontra a
 * linha e recebe o aviso, em vez de sair para uma entrega que ja e de outro.
 */
export async function aceitarCorrida(entregaId: string): Promise<ResultadoDaAcao> {
  const { entregadorId } = await exigirEntregador()
  const supabase = await criarClienteDoServidor()

  const { data, error } = await supabase
    .from("deliveries")
    .update({ courier_id: entregadorId, status: "assigned" })
    .eq("id", entregaId)
    .eq("status", "searching_courier")
    .select("id")

  if (error) return { ok: false, erro: error.message }
  if (!data || data.length === 0) {
    return { ok: false, erro: "Outro entregador pegou esta corrida." }
  }

  await supabase.from("couriers").update({ availability: "on_delivery" }).eq("id", entregadorId)

  revalidatePath("/entregas")
  return { ok: true }
}

export async function avancarCorrida(
  entregaId: string,
  destino: SituacaoDaEntrega,
): Promise<ResultadoDaAcao> {
  const { entregadorId } = await exigirEntregador()
  const supabase = await criarClienteDoServidor()

  const { data: entrega, error: erroDeLeitura } = await supabase
    .from("deliveries")
    .select("id, status, order_id, courier_id")
    .eq("id", entregaId)
    .single()

  if (erroDeLeitura || !entrega) return { ok: false, erro: "Não achei essa corrida." }
  if (entrega.courier_id !== entregadorId) {
    return { ok: false, erro: "Essa corrida não é sua." }
  }
  if (!transicaoDaEntregaPermitida(entrega.status as SituacaoDaEntrega, destino)) {
    return { ok: false, erro: "Esse passo não é possível a partir de agora." }
  }

  const { error } = await supabase
    .from("deliveries")
    .update({ status: destino })
    .eq("id", entregaId)

  if (error) return { ok: false, erro: error.message }

  // Entrega concluida fecha o pedido e devolve o entregador a fila. O contador
  // de entregas nao e escrito aqui: quem o avanca e o gatilho app.count_delivery.
  if (destino === "delivered") {
    await supabase.from("orders").update({ status: "delivered" }).eq("id", entrega.order_id)
    await supabase.from("couriers").update({ availability: "online" }).eq("id", entregadorId)
  }

  revalidatePath("/entregas")
  return { ok: true }
}

/** Desistir devolve a corrida a fila. O gatilho do banco limpa o entregador. */
export async function desistirDaCorrida(entregaId: string): Promise<ResultadoDaAcao> {
  const { entregadorId } = await exigirEntregador()
  const supabase = await criarClienteDoServidor()

  const { error } = await supabase
    .from("deliveries")
    .update({ status: "searching_courier" })
    .eq("id", entregaId)
    .eq("courier_id", entregadorId)

  if (error) return { ok: false, erro: error.message }

  await supabase.from("couriers").update({ availability: "online" }).eq("id", entregadorId)

  revalidatePath("/entregas")
  return { ok: true }
}

/** Ficar online e sair. Offline some da fila sem perder a corrida em curso. */
export async function mudarDisponibilidade(online: boolean): Promise<ResultadoDaAcao> {
  const { entregadorId } = await exigirEntregador()
  const supabase = await criarClienteDoServidor()

  const { error } = await supabase
    .from("couriers")
    .update({ availability: online ? "online" : "offline" })
    .eq("id", entregadorId)

  if (error) return { ok: false, erro: error.message }

  revalidatePath("/entregas")
  return { ok: true }
}
