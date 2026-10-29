"use server"

import { revalidatePath } from "next/cache"
import { z } from "zod"

import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirUsuario } from "@/modules/auth/sessao"

/**
 * O cadastro de entregador, pelo navegador.
 *
 * Espelho de `Corridas.cadastrar` em celular/lib/dados/corridas.dart. O
 * cadastro nasce pendente, e quem garante isso e o banco
 * (`app.guard_courier_insert`), nao o `status` mandado aqui: a chave anonima
 * vai publicada em todo aplicativo, e qualquer um pode chamar a API direto.
 */

export type ResultadoDoCadastro = { ok: true } | { ok: false; erro: string }

const VEICULOS = ["motorcycle", "bicycle", "car", "foot"] as const

const schema = z
  .object({
    restauranteId: z.uuid("Escolha para onde você quer entregar."),
    veiculo: z.enum(VEICULOS, "Escolha como você entrega."),
    placa: z
      .string()
      .trim()
      .toUpperCase()
      .transform((p) => p.replace(/[^A-Z0-9]/g, "")),
  })
  .refine(
    (d) => (d.veiculo !== "motorcycle" && d.veiculo !== "car") || d.placa.length === 7,
    { message: "Informe a placa: 7 letras e números, como ABC1D23." },
  )

export async function cadastrarEntregador(entrada: {
  restauranteId: string
  veiculo: string
  placa: string
}): Promise<ResultadoDoCadastro> {
  const contexto = await exigirUsuario("/entregas/cadastro")
  if (contexto.entregadorId) return { ok: true }

  const dados = schema.safeParse(entrada)
  if (!dados.success) {
    return { ok: false, erro: dados.error.issues[0]?.message ?? "Confira os dados." }
  }

  const supabase = await criarClienteDoServidor()
  const usaPlaca = dados.data.veiculo === "motorcycle" || dados.data.veiculo === "car"

  const { error } = await supabase.from("couriers").insert({
    user_id: contexto.id,
    restaurant_id: dados.data.restauranteId,
    vehicle_type: dados.data.veiculo,
    vehicle_plate: usaPlaca ? dados.data.placa : null,
    status: "pending",
  })

  if (error) {
    // Dois cliques, ou duas abas: o cadastro ja existe, e era isso que a
    // pessoa queria.
    if (error.code === "23505") return { ok: true }
    return { ok: false, erro: "Não deu para enviar o cadastro. Tente de novo." }
  }

  revalidatePath("/entregas")
  return { ok: true }
}
