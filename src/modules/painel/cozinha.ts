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
 * loja, o preparo so existe com os ingredientes junto, e cada ingrediente sai
 * do estoque na mesma transacao. Apagar e da gestao, e devolve ao estoque.
 */

/**
 * Aceita "2,5" e "2.5": quem digita na cozinha usa virgula. Obrigatoria: e ela
 * que vira a saida do estoque.
 */
const quantidade = z
  .string()
  .trim()
  .min(1, "Informe a quantidade de cada ingrediente.")
  .transform((texto, ctx) => {
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
        quantidade: z.string(),
      }),
    )
    // Linha em branco e a que sobrou do Enter, nao um ingrediente sem nome.
    .transform((lista) => lista.filter((i) => i.nome.trim() !== ""))
    .pipe(z.array(z.object({ nome: z.string().trim().max(120), quantidade })))
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
    p_ingredientes: dados.data.ingredientes,
    p_observacao: dados.data.observacao || undefined,
  })
  if (error || data === null) {
    return { ok: false, erro: error?.message ?? "Não deu para lançar o preparo." }
  }

  revalidatePath("/painel/cozinha")
  revalidatePath("/painel/estoque")
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

  // Apagar devolve ao estoque o que o preparo tirou (gatilho no banco).
  revalidatePath("/painel/cozinha")
  revalidatePath("/painel/estoque")
  return { ok: true }
}
