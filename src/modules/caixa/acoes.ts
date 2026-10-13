"use server"

import { revalidatePath } from "next/cache"
import { z } from "zod"

import { paraCentavos } from "@/lib/dinheiro"
import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirVinculo } from "@/modules/auth/sessao"
import type { ResultadoDaAcao } from "@/modules/painel/pedidos"

/**
 * O que a equipe faz no caixa alem de receber: abrir o dia com o fundo, tirar
 * dinheiro com a sangria, e — so a gestao — cancelar o lancamento errado.
 *
 * As regras (fundo unico por dia, sangria com motivo e sem passar do que ha na
 * gaveta, cancelamento so de hoje) moram nas funcoes do banco. Aqui o Zod
 * confere o formato, e o banco confere o resto.
 */

const valor = z
  .string()
  .transform((texto, ctx) => {
    const centavos = paraCentavos(texto)
    if (centavos === null || centavos <= 0) {
      ctx.addIssue({ code: "custom", message: "Informe um valor maior que zero." })
      return z.NEVER
    }
    return centavos
  })

const schemaDoFundo = z.object({ valor })

const schemaDaSangria = z.object({
  valor,
  motivo: z.string().trim().min(3, "Diga o motivo da sangria — vai para o relatório."),
})

function primeiroErro(erro: z.ZodError) {
  return erro.issues[0]?.message ?? "Confira os dados."
}

function revalidar() {
  revalidatePath("/painel/caixa")
  revalidatePath("/painel/caixa/relatorio")
}

export async function registrarFundo(entrada: { valor: string }): Promise<ResultadoDaAcao> {
  const { vinculo } = await exigirVinculo()

  const dados = schemaDoFundo.safeParse(entrada)
  if (!dados.success) return { ok: false, erro: primeiroErro(dados.error) }

  const supabase = await criarClienteDoServidor()
  const { error } = await supabase.rpc("registrar_fundo_de_caixa", {
    p_restaurante: vinculo.restauranteId,
    p_valor_cents: dados.data.valor,
  })
  if (error) return { ok: false, erro: error.message }

  revalidar()
  return { ok: true }
}

export async function registrarSangria(entrada: {
  valor: string
  motivo: string
}): Promise<ResultadoDaAcao> {
  const { vinculo } = await exigirVinculo()

  const dados = schemaDaSangria.safeParse(entrada)
  if (!dados.success) return { ok: false, erro: primeiroErro(dados.error) }

  const supabase = await criarClienteDoServidor()
  const { error } = await supabase.rpc("registrar_sangria", {
    p_restaurante: vinculo.restauranteId,
    p_valor_cents: dados.data.valor,
    p_motivo: dados.data.motivo,
  })
  if (error) return { ok: false, erro: error.message }

  revalidar()
  return { ok: true }
}

export async function cancelarLancamento(id: string): Promise<ResultadoDaAcao> {
  await exigirVinculo()

  if (!z.uuid().safeParse(id).success) return { ok: false, erro: "Lançamento inválido." }

  const supabase = await criarClienteDoServidor()
  const { error } = await supabase.rpc("cancelar_movimento_de_caixa", { p_movimento: id })
  if (error) return { ok: false, erro: error.message }

  revalidar()
  return { ok: true }
}
