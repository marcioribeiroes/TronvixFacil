"use server"

import { revalidatePath } from "next/cache"
import { z } from "zod"

import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirGestao } from "@/modules/auth/sessao"
import { UNIDADES } from "@/modules/painel/unidades"

/**
 * O estoque de ingredientes, pela gestao: cadastro, entrada, saida avulsa e
 * ficha tecnica.
 *
 * Toda conta de saldo e do banco (`app.movimentar_ingrediente`). As saidas do
 * preparo e do pedido pronto nao passam por aqui: nascem sozinhas, no
 * lancamento do preparo e na troca de status do pedido.
 */

export type ResultadoDaAcao = { ok: true } | { ok: false; erro: string }

/** Aceita "2,5" e "2.5": quem digita na cozinha usa virgula. */
const quantidade = z
  .string()
  .trim()
  .min(1, "Informe a quantidade.")
  .transform((texto, ctx) => {
    const numero = Number(texto.replace(",", "."))
    if (!Number.isFinite(numero) || numero <= 0 || numero > 1_000_000) {
      ctx.addIssue({ code: "custom", message: `Quantidade inválida: ${texto}.` })
      return z.NEVER
    }
    return numero
  })

const itens = z
  .array(z.object({ ingrediente: z.string(), quantidade: z.string() }))
  // Linha sem ingrediente escolhido e a que sobrou em branco, nao um erro.
  .transform((lista) => lista.filter((i) => i.ingrediente !== ""))
  .pipe(
    z
      .array(z.object({ ingrediente: z.uuid("Escolha o ingrediente."), quantidade }))
      .max(200, "No máximo 200 itens por lançamento."),
  )

function primeiroErro(erro: z.ZodError) {
  return erro.issues[0]?.message ?? "Confira os dados."
}

function revalidar() {
  revalidatePath("/painel/estoque")
  revalidatePath("/painel/cozinha")
}

const schemaDoIngrediente = z.object({
  id: z.uuid().optional(),
  nome: z.string().trim().min(1, "Informe o nome do ingrediente.").max(120),
  unidade: z.enum(UNIDADES, "Escolha a unidade."),
})

export async function salvarIngrediente(
  entrada: z.input<typeof schemaDoIngrediente>,
): Promise<ResultadoDaAcao> {
  const { vinculo } = await exigirGestao()
  const dados = schemaDoIngrediente.safeParse(entrada)
  if (!dados.success) return { ok: false, erro: primeiroErro(dados.error) }

  const supabase = await criarClienteDoServidor()
  const { error } = await supabase.rpc("salvar_ingrediente", {
    p_restaurante: vinculo.restauranteId,
    p_nome: dados.data.nome,
    p_unidade: dados.data.unidade,
    ...(dados.data.id ? { p_id: dados.data.id } : {}),
  })
  if (error) return { ok: false, erro: error.message }

  revalidar()
  return { ok: true }
}

export async function arquivarIngrediente(id: string): Promise<ResultadoDaAcao> {
  await exigirGestao()
  if (!z.uuid().safeParse(id).success) return { ok: false, erro: "Ingrediente inválido." }

  const supabase = await criarClienteDoServidor()
  const { error } = await supabase.rpc("arquivar_ingrediente", { p_id: id })
  if (error) return { ok: false, erro: error.message }

  revalidar()
  return { ok: true }
}

const schemaDoMovimento = z.object({
  tipo: z.enum(["in", "out"]),
  itens: itens.refine((l) => l.length > 0, "Escolha ao menos um ingrediente."),
  motivo: z.string().trim().max(200, "O motivo tem no máximo 200 caracteres."),
})

export async function movimentarIngredientes(
  entrada: z.input<typeof schemaDoMovimento>,
): Promise<{ ok: true; itens: number } | { ok: false; erro: string }> {
  const { vinculo } = await exigirGestao()
  const dados = schemaDoMovimento.safeParse(entrada)
  if (!dados.success) return { ok: false, erro: primeiroErro(dados.error) }

  const supabase = await criarClienteDoServidor()
  const { data, error } = await supabase.rpc("movimentar_ingredientes", {
    p_restaurante: vinculo.restauranteId,
    p_tipo: dados.data.tipo,
    p_itens: dados.data.itens,
    p_motivo: dados.data.motivo || undefined,
  })
  if (error || data === null) {
    return { ok: false, erro: error?.message ?? "Não deu para lançar." }
  }

  revalidar()
  return { ok: true, itens: data }
}

const schemaDaFicha = z.object({ produto: z.uuid("Escolha o produto."), itens })

export async function salvarFichaTecnica(
  entrada: z.input<typeof schemaDaFicha>,
): Promise<ResultadoDaAcao> {
  await exigirGestao()
  const dados = schemaDaFicha.safeParse(entrada)
  if (!dados.success) return { ok: false, erro: primeiroErro(dados.error) }

  const supabase = await criarClienteDoServidor()
  const { error } = await supabase.rpc("salvar_ficha_tecnica", {
    p_produto: dados.data.produto,
    p_itens: dados.data.itens,
  })
  if (error) return { ok: false, erro: error.message }

  revalidar()
  return { ok: true }
}
