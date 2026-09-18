import "server-only"

import { cookies } from "next/headers"

import { criarClienteDoServidor } from "@/lib/supabase/servidor"

/**
 * A mesa em que a pessoa esta sentada.
 *
 * Vive num cookie, e nao na URL: entre ler o QR e fechar o pedido a pessoa
 * passa pelo cardapio, pelo produto, pelo carrinho e pelo login. Carregar o
 * codigo por todas essas telas na query string daria uma chance a cada
 * navegacao de perder a mesa - e perder a mesa significa o pedido cair na
 * cozinha sem dizer para onde levar.
 *
 * Quatro horas de validade. Uma refeicao demora duas; o dobro cobre a
 * sobremesa e o cafe, e nao cobre o cliente de amanha sentado em outro lugar.
 */

export const COOKIE_DA_MESA = "tronvix_mesa"

export type MesaAtual = {
  codigo: string
  rotulo: string
  restauranteId: string
  restauranteNome: string
  restauranteSlug: string
}

/** Le a mesa do cookie e confere no banco. Cookie velho de mesa apagada da null. */
export async function mesaAtual(): Promise<MesaAtual | null> {
  const codigo = (await cookies()).get(COOKIE_DA_MESA)?.value
  if (!codigo) return null
  return mesaPeloCodigo(codigo)
}

export async function mesaPeloCodigo(codigo: string): Promise<MesaAtual | null> {
  const supabase = await criarClienteDoServidor()

  const { data } = await supabase
    .from("restaurant_tables")
    .select("code, label, restaurant_id, restaurants(name, slug, status)")
    .eq("code", codigo.trim().toLowerCase())
    .eq("is_active", true)
    .is("deleted_at", null)
    .maybeSingle()

  if (!data || !data.restaurants || data.restaurants.status !== "approved") return null

  return {
    codigo: data.code,
    rotulo: data.label,
    restauranteId: data.restaurant_id,
    restauranteNome: data.restaurants.name,
    restauranteSlug: data.restaurants.slug,
  }
}

export async function esquecerMesa() {
  ;(await cookies()).delete(COOKIE_DA_MESA)
}
