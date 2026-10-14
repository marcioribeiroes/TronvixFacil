"use server"

import { cookies } from "next/headers"
import { redirect } from "next/navigation"
import { z } from "zod"

import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { COOKIE_DO_SUPORTE } from "@/modules/auth/suporte-cookie"
import { exigirAdminDaPlataforma } from "@/modules/auth/sessao"

/**
 * Modo suporte: a equipe da plataforma abre o painel de uma loja.
 *
 * O cookie so diz QUAL loja; quem decide se vale e o servidor, a cada pagina —
 * `exigirVinculo` confere que a pessoa ainda e administradora e que a sessao
 * de suporte esta aberta no banco. Cookie copiado para uma conta comum nao
 * abre nada.
 */

export async function entrarComoSuporte(restauranteId: string): Promise<void> {
  await exigirAdminDaPlataforma()
  if (!z.uuid().safeParse(restauranteId).success) redirect("/admin/restaurantes")

  const supabase = await criarClienteDoServidor()
  const { error } = await supabase.rpc("entrar_como_suporte", { p_restaurante: restauranteId })
  if (error) redirect("/admin/restaurantes")

  const armazem = await cookies()
  armazem.set(COOKIE_DO_SUPORTE, restauranteId, {
    httpOnly: true,
    sameSite: "lax",
    secure: process.env.NODE_ENV === "production",
    path: "/",
    // Um turno. Suporte esquecido aberto nao fica valendo para sempre.
    maxAge: 60 * 60 * 8,
  })

  redirect("/painel/pedidos")
}

export async function sairDoSuporte(): Promise<void> {
  await exigirAdminDaPlataforma()

  const supabase = await criarClienteDoServidor()
  await supabase.rpc("sair_do_suporte")

  const armazem = await cookies()
  armazem.delete(COOKIE_DO_SUPORTE)

  redirect("/admin/restaurantes")
}
