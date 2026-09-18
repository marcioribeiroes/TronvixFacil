"use server"

import { revalidatePath } from "next/cache"

import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirGestao } from "@/modules/auth/sessao"

/**
 * As mesas do salao.
 *
 * Criar em lote e a operacao principal, porque o caso real e "tenho 20 mesas",
 * nao "quero cadastrar a mesa 1". Quem tem nome no salao - Varanda, Balcao -
 * renomeia as poucas depois.
 *
 * O codigo do QR nunca e escolhido nem editado aqui: quem sorteia e o banco.
 * Codigo escolhido a mao vira "mesa1", e "mesa2" se adivinha sozinho.
 */

export type ResultadoDaAcao = { ok: true } | { ok: false; erro: string }

export async function criarMesas(quantidade: number, prefixo = "Mesa"): Promise<ResultadoDaAcao> {
  const { vinculo } = await exigirGestao()
  const supabase = await criarClienteDoServidor()

  const { error } = await supabase.rpc("criar_mesas", {
    p_restaurante: vinculo.restauranteId,
    p_quantidade: quantidade,
    p_prefixo: prefixo.trim() || "Mesa",
  })

  if (error) return { ok: false, erro: error.message }

  revalidatePath("/painel/mesas")
  revalidatePath("/painel")
  return { ok: true }
}

export async function renomearMesa(id: string, rotulo: string): Promise<ResultadoDaAcao> {
  const { vinculo } = await exigirGestao()
  const supabase = await criarClienteDoServidor()

  const nome = rotulo.trim()
  if (nome === "") return { ok: false, erro: "A mesa precisa de um nome." }

  const { error } = await supabase
    .from("restaurant_tables")
    .update({ label: nome })
    .eq("id", id)
    .eq("restaurant_id", vinculo.restauranteId)

  if (error) {
    // O índice único por (estabelecimento, nome) protege contra duas "Mesa 5"
    // no mesmo salão — o garçom não saberia qual é qual.
    if (error.code === "23505") return { ok: false, erro: "Já existe uma mesa com esse nome." }
    return { ok: false, erro: error.message }
  }

  revalidatePath("/painel/mesas")
  return { ok: true }
}

/**
 * Tirar de uso, sem apagar.
 *
 * Mesa quebrada, canto do salao fechado na segunda-feira, area externa na
 * chuva. Desativada, ela recusa pedido - e o QR impresso continua valendo para
 * quando voltar.
 */
export async function mudarUsoDaMesa(id: string, emUso: boolean): Promise<ResultadoDaAcao> {
  const { vinculo } = await exigirGestao()
  const supabase = await criarClienteDoServidor()

  const { error } = await supabase
    .from("restaurant_tables")
    .update({ is_active: emUso })
    .eq("id", id)
    .eq("restaurant_id", vinculo.restauranteId)

  if (error) return { ok: false, erro: error.message }

  revalidatePath("/painel/mesas")
  return { ok: true }
}

/**
 * Remover de vez.
 *
 * O pedido ja feito nela nao se perde: `orders.table_label` guardou o nome, e
 * a chave estrangeira e `on delete set null`. O historico continua dizendo
 * "Mesa 7" depois que a Mesa 7 deixou de existir.
 */
export async function removerMesa(id: string): Promise<ResultadoDaAcao> {
  const { vinculo } = await exigirGestao()
  const supabase = await criarClienteDoServidor()

  const { error } = await supabase
    .from("restaurant_tables")
    .update({ deleted_at: new Date().toISOString(), is_active: false })
    .eq("id", id)
    .eq("restaurant_id", vinculo.restauranteId)

  if (error) return { ok: false, erro: error.message }

  revalidatePath("/painel/mesas")
  return { ok: true }
}
