"use server"

import { revalidatePath } from "next/cache"
import { z } from "zod"

import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirGestao } from "@/modules/auth/sessao"
import { paraLinha, schemaDaFicha, type FichaDigitada } from "@/modules/clientes/ficha"

/**
 * O caderno de clientes da loja: cadastrar, corrigir e tirar.
 *
 * So a gestao escreve (a RLS confere de novo). Tirar nao apaga: marca
 * `deleted_at`, e os pedidos que o cliente fez continuam inteiros.
 */

export type ResultadoDaAcao = { ok: true } | { ok: false; erro: string }

const id = z.uuid()

function erroDoBanco(error: { code?: string; message: string }): ResultadoDaAcao {
  // O indice unico por (loja, telefone): o mesmo cliente em duas fichas.
  if (error.code === "23505") {
    return { ok: false, erro: "Já existe um cliente com esse telefone." }
  }
  return { ok: false, erro: error.message }
}

/** Cadastra (sem `clienteId`) ou corrige (com ele) uma ficha. */
export async function salvarCliente(
  clienteId: string | null,
  dados: FichaDigitada,
): Promise<ResultadoDaAcao> {
  const { vinculo } = await exigirGestao()

  const ficha = schemaDaFicha.safeParse(dados)
  if (!ficha.success) {
    return { ok: false, erro: ficha.error.issues[0]?.message ?? "Confira os dados do cliente." }
  }

  const supabase = await criarClienteDoServidor()
  const linha = paraLinha(ficha.data)

  if (clienteId === null) {
    const { error } = await supabase.from("restaurant_customers").insert({
      ...linha,
      restaurant_id: vinculo.restauranteId,
    })
    if (error) return erroDoBanco(error)
  } else {
    if (!id.safeParse(clienteId).success) return { ok: false, erro: "Cliente não encontrado." }
    const { error } = await supabase
      .from("restaurant_customers")
      .update(linha)
      .eq("id", clienteId)
      .eq("restaurant_id", vinculo.restauranteId)
      .is("deleted_at", null)
    if (error) return erroDoBanco(error)
  }

  revalidatePath("/painel/clientes")
  return { ok: true }
}

export async function removerCliente(clienteId: string): Promise<ResultadoDaAcao> {
  const { vinculo } = await exigirGestao()
  if (!id.safeParse(clienteId).success) return { ok: false, erro: "Cliente não encontrado." }

  const supabase = await criarClienteDoServidor()
  const { error } = await supabase
    .from("restaurant_customers")
    .update({ deleted_at: new Date().toISOString() })
    .eq("id", clienteId)
    .eq("restaurant_id", vinculo.restauranteId)

  if (error) return erroDoBanco(error)

  revalidatePath("/painel/clientes")
  return { ok: true }
}
