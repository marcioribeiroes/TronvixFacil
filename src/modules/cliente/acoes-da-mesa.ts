"use server"

import { revalidatePath } from "next/cache"

import { esquecerMesa } from "@/modules/cliente/mesa"

/**
 * Sair da mesa.
 *
 * Separado de mesa.ts porque aquele arquivo e "server-only", nao "use server":
 * ele le do banco e do cookie para as paginas, e nada ali deve virar endpoint
 * chamavel pelo navegador. So esta acao precisa disso.
 */
export async function sairDaMesa() {
  await esquecerMesa()
  revalidatePath("/", "layout")
}
