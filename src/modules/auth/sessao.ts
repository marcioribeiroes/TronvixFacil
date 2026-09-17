import "server-only"

import { cache } from "react"
import { redirect } from "next/navigation"

import { supabaseConfigurado } from "@/lib/ambiente"
import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import type { Enums, Tabelas } from "@/types/banco"

/**
 * Quem esta pedindo, e o que essa pessoa pode.
 *
 * Toda pagina de area protegida comeca por aqui. As funcoes exigir* nao
 * devolvem null: ou entregam o contexto completo, ou redirecionam. Isso tira
 * da pagina a tentacao de "seguir mesmo assim" com um usuario incompleto.
 */

export type Perfil = Tabelas<"profiles">
export type Vinculo = {
  restauranteId: string
  cargo: Enums<"restaurant_role">
  nome: string
  slug: string
  situacao: Enums<"restaurant_status">
  logoUrl: string | null
}

export type ContextoDoUsuario = {
  id: string
  email: string | null
  perfil: Perfil
  vinculos: Vinculo[]
  entregadorId: string | null
  ehAdminDaPlataforma: boolean
}

/**
 * cache() do React: varias chamadas dentro da MESMA requisicao reaproveitam o
 * resultado. Um layout, a pagina e tres componentes podem perguntar quem e o
 * usuario sem gerar cinco idas ao banco.
 */
export const obterContexto = cache(async (): Promise<ContextoDoUsuario | null> => {
  // Sem Supabase configurado nao ha sessao possivel - e nao ha erro a lancar.
  // Isso mantem o projeto navegavel logo apos o clone, antes do .env.local:
  // as telas publicas renderizam e explicam o que falta configurar.
  if (!supabaseConfigurado()) return null

  const supabase = await criarClienteDoServidor()

  // getUser valida o token no servidor. Nunca decidir acesso com getSession.
  const {
    data: { user },
  } = await supabase.auth.getUser()

  if (!user) return null

  const [{ data: perfil }, { data: vinculos }, { data: entregador }] = await Promise.all([
    supabase.from("profiles").select("*").eq("id", user.id).maybeSingle(),
    supabase
      .from("restaurant_members")
      .select("restaurant_id, role, restaurants(name, slug, status, logo_url)")
      .eq("user_id", user.id)
      .eq("is_active", true)
      .is("deleted_at", null),
    supabase.from("couriers").select("id").eq("user_id", user.id).maybeSingle(),
  ])

  // O perfil e criado por gatilho junto com o usuario. Nao existir aqui
  // significa banco em estado inconsistente - melhor tratar como sem sessao do
  // que seguir com um usuario sem papel.
  if (!perfil) return null

  type LinhaDeVinculo = {
    restaurant_id: string
    role: Enums<"restaurant_role">
    restaurants: {
      name: string
      slug: string
      status: Enums<"restaurant_status">
      logo_url: string | null
    } | null
  }

  return {
    id: user.id,
    email: user.email ?? null,
    perfil,
    vinculos: ((vinculos ?? []) as unknown as LinhaDeVinculo[])
      .filter((v) => v.restaurants !== null)
      .map((v) => ({
        restauranteId: v.restaurant_id,
        cargo: v.role,
        nome: v.restaurants!.name,
        slug: v.restaurants!.slug,
        situacao: v.restaurants!.status,
        logoUrl: v.restaurants!.logo_url,
      })),
    entregadorId: entregador?.id ?? null,
    ehAdminDaPlataforma: perfil.platform_role === "platform_admin",
  }
})

/** Exige sessao. Sem ela, manda para o login guardando o destino pretendido. */
export async function exigirUsuario(destino?: string): Promise<ContextoDoUsuario> {
  const contexto = await obterContexto()
  if (!contexto) {
    redirect(destino ? `/entrar?voltar_para=${encodeURIComponent(destino)}` : "/entrar")
  }
  return contexto
}

/**
 * Exige vinculo com um estabelecimento.
 *
 * Sem `restauranteId`, assume o primeiro vinculo - o caso comum, de quem tem
 * uma loja so. Quem tem mais de uma troca pelo seletor do painel.
 */
export async function exigirVinculo(restauranteId?: string) {
  const contexto = await exigirUsuario("/painel")

  const vinculo = restauranteId
    ? contexto.vinculos.find((v) => v.restauranteId === restauranteId)
    : contexto.vinculos[0]

  if (!vinculo) {
    // Admin da plataforma nao herda vinculo: ele administra a plataforma, e
    // entrar no painel de um restaurante e outra coisa, feita pelo /admin.
    redirect(contexto.ehAdminDaPlataforma ? "/admin" : "/painel/sem-acesso")
  }

  return { contexto, vinculo }
}

/** Exige cargo de gestao: cardapio, equipe, financeiro e configuracoes. */
export async function exigirGestao(restauranteId?: string) {
  const { contexto, vinculo } = await exigirVinculo(restauranteId)

  if (vinculo.cargo !== "owner" && vinculo.cargo !== "manager") {
    redirect("/painel/pedidos")
  }

  return { contexto, vinculo }
}

export async function exigirAdminDaPlataforma() {
  const contexto = await exigirUsuario("/admin")
  if (!contexto.ehAdminDaPlataforma) redirect("/")
  return contexto
}

export async function exigirEntregador() {
  const contexto = await exigirUsuario("/entregas")
  if (!contexto.entregadorId) redirect("/entregas/cadastro")
  return { contexto, entregadorId: contexto.entregadorId }
}

/**
 * Para onde mandar a pessoa logo apos o login.
 *
 * A ordem reflete o uso: quem tem painel trabalha nele o dia inteiro; ser
 * cliente e o caso geral e fica por ultimo.
 */
export function rotaInicialDe(contexto: ContextoDoUsuario): string {
  if (contexto.ehAdminDaPlataforma) return "/admin"
  if (contexto.vinculos.length > 0) return "/painel"
  if (contexto.entregadorId) return "/entregas"
  return "/"
}
