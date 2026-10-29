"use server"

import { revalidatePath } from "next/cache"
import { z } from "zod"

import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirGestao, exigirVinculo } from "@/modules/auth/sessao"

/**
 * O livro de preparos da cozinha.
 *
 * Lancar e da equipe toda - quem faz o molho e a cozinha, nao a gerencia - e
 * vai inteiro pelo banco, em `lancar_preparo`: o numero sai do contador da
 * loja e o preparo so existe com os ingredientes junto. Apagar e da gestao.
 */

/** Aceita "2,5" e "2.5": quem digita na cozinha usa virgula. */
const quantidade = z
  .string()
  .trim()
  .transform((texto, ctx) => {
    if (texto === "") return null
    const numero = Number(texto.replace(",", "."))
    if (!Number.isFinite(numero) || numero <= 0 || numero > 1_000_000) {
      ctx.addIssue({ code: "custom", message: `Quantidade inválida: ${texto}.` })
      return z.NEVER
    }
    return numero
  })

const schemaDoPreparo = z.object({
  data: z.iso.date("Informe a data do preparo."),
  nome: z.string().trim().min(1, "Informe o nome do preparo.").max(120),
  prato: z.string().trim().min(1, "Informe o nome do prato.").max(120),
  observacao: z.string().trim().max(500, "A observação tem no máximo 500 caracteres."),
  ingredientes: z
    .array(
      z.object({
        nome: z.string().trim().max(120),
        quantidade,
        unidade: z.string().trim().max(20),
      }),
    )
    // Linha em branco e a que sobrou do Enter, nao um ingrediente sem nome.
    .transform((lista) => lista.filter((i) => i.nome !== ""))
    .refine((lista) => lista.length > 0, "Informe ao menos um ingrediente.")
    .refine((lista) => lista.length <= 100, "No máximo 100 ingredientes por preparo."),
})

export type LancamentoDePreparo = z.input<typeof schemaDoPreparo>

export async function lancarPreparo(
  entrada: LancamentoDePreparo,
): Promise<{ ok: true; numero: number } | { ok: false; erro: string }> {
  const { vinculo } = await exigirVinculo()

  const dados = schemaDoPreparo.safeParse(entrada)
  if (!dados.success) {
    return { ok: false, erro: dados.error.issues[0]?.message ?? "Confira o preparo." }
  }

  const supabase = await criarClienteDoServidor()
  const { data, error } = await supabase.rpc("lancar_preparo", {
    p_restaurante: vinculo.restauranteId,
    p_data: dados.data.data,
    p_nome: dados.data.nome,
    p_prato: dados.data.prato,
    p_ingredientes: dados.data.ingredientes.map((i) => ({
      nome: i.nome,
      quantidade: i.quantidade,
      unidade: i.unidade || null,
    })),
    p_observacao: dados.data.observacao || undefined,
  })
  if (error || data === null) {
    return { ok: false, erro: error?.message ?? "Não deu para lançar o preparo." }
  }

  revalidatePath("/painel/cozinha")
  return { ok: true, numero: data }
}

export async function apagarPreparo(
  id: string,
): Promise<{ ok: true } | { ok: false; erro: string }> {
  const { vinculo } = await exigirGestao()
  if (!z.uuid().safeParse(id).success) return { ok: false, erro: "Preparo inválido." }

  const supabase = await criarClienteDoServidor()
  const { error, count } = await supabase
    .from("kitchen_preps")
    .delete({ count: "exact" })
    .eq("id", id)
    .eq("restaurant_id", vinculo.restauranteId)

  if (error) return { ok: false, erro: error.message }
  if (!count) return { ok: false, erro: "Não achei esse preparo." }

  revalidatePath("/painel/cozinha")
  return { ok: true }
}
