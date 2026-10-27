"use server"

import { revalidatePath } from "next/cache"
import { z } from "zod"

import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirGestao } from "@/modules/auth/sessao"

/**
 * A mercadoria que chega.
 *
 * A conta - somar no saldo, ligar o controle, deixar a linha no livro - e do
 * banco, em `dar_entrada_no_estoque`, e vale para a nota inteira de uma vez:
 * ou entra tudo, ou nada. Aqui so se confere a forma antes de mandar.
 */

const schemaDaEntrada = z.object({
  itens: z
    .array(
      z.object({
        produto: z.uuid(),
        quantidade: z
          .number()
          .int("A quantidade é um número inteiro.")
          .min(1, "A quantidade mínima é 1.")
          .max(100_000, "Quantidade alta demais para uma entrada."),
      }),
    )
    .min(1, "Leia ou escolha ao menos um produto.")
    .max(200, "No máximo 200 itens por entrada."),
  observacao: z.string().trim().max(200, "A observação tem no máximo 200 caracteres.").optional(),
})

export type EntradaDeEstoque = z.input<typeof schemaDaEntrada>

export async function darEntradaNoEstoque(
  entrada: EntradaDeEstoque,
): Promise<{ ok: true; unidades: number } | { ok: false; erro: string }> {
  const { vinculo } = await exigirGestao()

  const dados = schemaDaEntrada.safeParse(entrada)
  if (!dados.success) {
    return { ok: false, erro: dados.error.issues[0]?.message ?? "Confira a entrada." }
  }

  const supabase = await criarClienteDoServidor()
  const { data, error } = await supabase.rpc("dar_entrada_no_estoque", {
    p_restaurante: vinculo.restauranteId,
    p_itens: dados.data.itens,
    p_observacao: dados.data.observacao || undefined,
  })
  if (error || data === null) {
    return { ok: false, erro: error?.message ?? "Não deu para dar entrada." }
  }

  for (const rota of ["/painel/estoque", "/painel/produtos", "/painel/cardapio"]) {
    revalidatePath(rota)
  }
  return { ok: true, unidades: data }
}
