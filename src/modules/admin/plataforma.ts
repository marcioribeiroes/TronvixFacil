"use server"

import { revalidatePath } from "next/cache"

import { paraCentavos } from "@/lib/dinheiro"
import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirAdminDaPlataforma } from "@/modules/auth/sessao"
import type { Enums } from "@/types/banco"

/**
 * O que a plataforma configura: cupons, categorias da vitrine e banners.
 *
 * Tudo isto ja existia no banco, com as regras completas, e nao havia como
 * criar nenhum deles sem escrever SQL. Estas acoes sao a porta.
 */

export type ResultadoDaAcao = { ok: true } | { ok: false; erro: string; campo?: string }

function recarregar(...rotas: string[]) {
  for (const r of rotas) revalidatePath(r)
}

// ---------------------------------------------------------------------------
// Cupons
// ---------------------------------------------------------------------------

export async function salvarCupom(dados: {
  id?: string
  codigo: string
  descricao?: string
  tipo: Enums<"discount_type">
  /** Percentual ("15") quando percentage; valor ("10,00") quando fixed. */
  valor: string
  pedidoMinimo?: string
  descontoMaximo?: string
  terminaEm?: string
  usosMaximos?: string
  usosPorCliente: string
  soPrimeiroPedido: boolean
  restauranteId?: string
}): Promise<ResultadoDaAcao> {
  await exigirAdminDaPlataforma()
  const supabase = await criarClienteDoServidor()

  const codigo = dados.codigo.trim().toUpperCase()
  if (codigo.length < 3) {
    return { ok: false, erro: "O código precisa de ao menos 3 letras.", campo: "codigo" }
  }

  // O mesmo campo `value` guarda coisas diferentes conforme o tipo — pontos
  // base no percentual, centavos no valor fixo — e é inteiro nos dois casos.
  // O comentário está no schema; aqui é onde a conversão acontece.
  let valor = 0
  if (dados.tipo === "percentage") {
    const porcento = Number(dados.valor.replace(",", "."))
    if (!Number.isFinite(porcento) || porcento <= 0 || porcento > 100) {
      return { ok: false, erro: "O percentual vai de 1 a 100.", campo: "valor" }
    }
    valor = Math.round(porcento * 100)
  } else if (dados.tipo === "fixed") {
    const centavos = paraCentavos(dados.valor)
    if (centavos === null || centavos <= 0) {
      return { ok: false, erro: "Escreva o valor do desconto.", campo: "valor" }
    }
    valor = centavos
  }

  const campos = {
    // Cupom sem estabelecimento é da plataforma e vale em qualquer loja — é o
    // que a constraint `coupons_scope_consistent` exige.
    scope: (dados.restauranteId ? "restaurant" : "platform") as Enums<"coupon_scope">,
    restaurant_id: dados.restauranteId || null,
    code: codigo,
    description: dados.descricao?.trim() || null,
    discount: dados.tipo,
    value: valor,
    min_order_cents: paraCentavos(dados.pedidoMinimo ?? "") ?? 0,
    max_discount_cents: dados.descontoMaximo?.trim()
      ? paraCentavos(dados.descontoMaximo)
      : null,
    ends_at: dados.terminaEm ? new Date(`${dados.terminaEm}T23:59:59`).toISOString() : null,
    max_uses: dados.usosMaximos?.trim() ? Number(dados.usosMaximos) : null,
    max_uses_per_customer: Math.max(1, Number(dados.usosPorCliente) || 1),
    first_order_only: dados.soPrimeiroPedido,
  }

  const { error } = dados.id
    ? await supabase.from("coupons").update(campos).eq("id", dados.id)
    : await supabase.from("coupons").insert(campos)

  if (error) {
    if (error.code === "23505") {
      return { ok: false, erro: "Já existe um cupom com esse código.", campo: "codigo" }
    }
    return { ok: false, erro: error.message }
  }

  recarregar("/admin/cupons")
  return { ok: true }
}

export async function mudarSituacaoDoCupom(
  id: string,
  ativo: boolean,
): Promise<ResultadoDaAcao> {
  await exigirAdminDaPlataforma()
  const supabase = await criarClienteDoServidor()

  const { error } = await supabase.from("coupons").update({ is_active: ativo }).eq("id", id)
  if (error) return { ok: false, erro: error.message }

  recarregar("/admin/cupons")
  return { ok: true }
}

/**
 * Remover cupom é exclusão lógica.
 *
 * `coupon_redemptions` aponta para ele e guarda quanto cada pedido abateu.
 * Apagar de verdade levaria junto a explicação de um desconto no histórico.
 */
export async function removerCupom(id: string): Promise<ResultadoDaAcao> {
  await exigirAdminDaPlataforma()
  const supabase = await criarClienteDoServidor()

  const { error } = await supabase
    .from("coupons")
    .update({ deleted_at: new Date().toISOString(), is_active: false })
    .eq("id", id)

  if (error) return { ok: false, erro: error.message }

  recarregar("/admin/cupons")
  return { ok: true }
}

// ---------------------------------------------------------------------------
// Categorias da vitrine
// ---------------------------------------------------------------------------

export async function salvarCategoriaDaPlataforma(dados: {
  id?: string
  nome: string
  slug: string
  posicao: number
}): Promise<ResultadoDaAcao> {
  await exigirAdminDaPlataforma()
  const supabase = await criarClienteDoServidor()

  const nome = dados.nome.trim()
  if (nome.length < 2) return { ok: false, erro: "Dê um nome à categoria.", campo: "nome" }

  // O slug é o que o aplicativo usa para filtrar; gerado do nome quando vazio,
  // para ninguém precisar pensar nele.
  const slug =
    dados.slug.trim() ||
    nome
      .normalize("NFD")
      .replace(/[̀-ͯ]/g, "")
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-|-$/g, "")

  const campos = { name: nome, slug, position: dados.posicao }

  const { error } = dados.id
    ? await supabase.from("platform_categories").update(campos).eq("id", dados.id)
    : await supabase.from("platform_categories").insert(campos)

  if (error) {
    if (error.code === "23505") {
      return { ok: false, erro: "Já existe uma categoria com esse endereço.", campo: "slug" }
    }
    return { ok: false, erro: error.message }
  }

  recarregar("/admin/categorias", "/")
  return { ok: true }
}

export async function mudarSituacaoDaCategoria(
  id: string,
  ativa: boolean,
): Promise<ResultadoDaAcao> {
  await exigirAdminDaPlataforma()
  const supabase = await criarClienteDoServidor()

  const { error } = await supabase
    .from("platform_categories")
    .update({ is_active: ativa })
    .eq("id", id)

  if (error) return { ok: false, erro: error.message }

  recarregar("/admin/categorias", "/")
  return { ok: true }
}

// ---------------------------------------------------------------------------
// Banners
// ---------------------------------------------------------------------------

export async function salvarBanner(dados: {
  id?: string
  titulo: string
  imagemUrl: string
  destino?: string
  posicao: number
  terminaEm?: string
}): Promise<ResultadoDaAcao> {
  await exigirAdminDaPlataforma()
  const supabase = await criarClienteDoServidor()

  if (dados.titulo.trim().length < 2) {
    return { ok: false, erro: "Dê um título à faixa.", campo: "titulo" }
  }
  if (!/^https?:\/\//.test(dados.imagemUrl.trim())) {
    return { ok: false, erro: "A imagem precisa de um endereço http(s).", campo: "imagemUrl" }
  }

  const campos = {
    title: dados.titulo.trim(),
    image_url: dados.imagemUrl.trim(),
    target_url: dados.destino?.trim() || null,
    position: dados.posicao,
    ends_at: dados.terminaEm ? new Date(`${dados.terminaEm}T23:59:59`).toISOString() : null,
  }

  const { error } = dados.id
    ? await supabase.from("banners").update(campos).eq("id", dados.id)
    : await supabase.from("banners").insert(campos)

  if (error) return { ok: false, erro: error.message }

  recarregar("/admin/banners", "/")
  return { ok: true }
}

export async function removerBanner(id: string): Promise<ResultadoDaAcao> {
  await exigirAdminDaPlataforma()
  const supabase = await criarClienteDoServidor()

  const { error } = await supabase.from("banners").update({ is_active: false }).eq("id", id)
  if (error) return { ok: false, erro: error.message }

  recarregar("/admin/banners", "/")
  return { ok: true }
}
