"use server"

import { revalidatePath } from "next/cache"

import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import type { Enums } from "@/types/banco"
import { exigirUsuario, obterContexto } from "@/modules/auth/sessao"

/**
 * O carrinho do cliente, na web.
 *
 * Mora no servidor, como no aplicativo: e da tabela `carts` que
 * `public.fechar_pedido` le para recalcular os precos. Um carrinho so no
 * navegador obrigaria a mandar quanto custa - exatamente o que o banco nao
 * aceita.
 *
 * Consequencia boa: quem monta o pedido no computador e fecha no celular
 * encontra o carrinho como deixou.
 */

export type ResultadoDaAcao = { ok: true; id?: string } | { ok: false; erro: string }

function recarregar() {
  revalidatePath("/carrinho")
  revalidatePath("/", "layout")
}

/**
 * Abre (ou reabre) o carrinho de um estabelecimento.
 *
 * Trocar de restaurante apaga o carrinho anterior: um pedido pertence a um
 * estabelecimento so, e e o indice `carts_open_per_restaurant_idx` que garante
 * isso. Quem avisa o cliente antes de descartar e a tela.
 */
async function abrirCarrinho(restauranteId: string) {
  const contexto = await exigirUsuario("/carrinho")
  const supabase = await criarClienteDoServidor()

  const { data: existente } = await supabase
    .from("carts")
    .select("id, restaurant_id")
    .eq("user_id", contexto.id)
    .maybeSingle()

  if (existente?.restaurant_id === restauranteId) return existente.id
  if (existente) await supabase.from("carts").delete().eq("id", existente.id)

  const { data: novo, error } = await supabase
    .from("carts")
    .insert({ user_id: contexto.id, restaurant_id: restauranteId })
    .select("id")
    .single()

  if (error || !novo) throw new Error(error?.message ?? "Não consegui abrir o carrinho.")
  return novo.id
}

export async function adicionarAoCarrinho(dados: {
  restauranteId: string
  produtoId: string
  quantidade: number
  adicionais: string[]
  observacao?: string
}): Promise<ResultadoDaAcao> {
  try {
    const carrinhoId = await abrirCarrinho(dados.restauranteId)
    const supabase = await criarClienteDoServidor()

    const { data: item, error } = await supabase
      .from("cart_items")
      .insert({
        cart_id: carrinhoId,
        product_id: dados.produtoId,
        quantity: Math.max(1, Math.min(99, dados.quantidade)),
        notes: dados.observacao?.trim() || null,
      })
      .select("id")
      .single()

    if (error || !item) return { ok: false, erro: error?.message ?? "Não consegui adicionar." }

    if (dados.adicionais.length > 0) {
      const { error: erroDosAdicionais } = await supabase.from("cart_item_addons").insert(
        dados.adicionais.map((addon_id) => ({ cart_item_id: item.id, addon_id })),
      )
      if (erroDosAdicionais) return { ok: false, erro: erroDosAdicionais.message }
    }

    recarregar()
    return { ok: true, id: item.id }
  } catch (e) {
    return { ok: false, erro: e instanceof Error ? e.message : "Não consegui adicionar." }
  }
}

export async function mudarQuantidade(
  itemId: string,
  quantidade: number,
): Promise<ResultadoDaAcao> {
  await exigirUsuario("/carrinho")
  const supabase = await criarClienteDoServidor()

  const { error } =
    quantidade <= 0
      ? await supabase.from("cart_items").delete().eq("id", itemId)
      : await supabase
          .from("cart_items")
          .update({ quantity: Math.min(99, quantidade) })
          .eq("id", itemId)

  if (error) return { ok: false, erro: error.message }

  recarregar()
  return { ok: true }
}

export async function esvaziarCarrinho(): Promise<ResultadoDaAcao> {
  const contexto = await exigirUsuario("/carrinho")
  const supabase = await criarClienteDoServidor()

  const { error } = await supabase.from("carts").delete().eq("user_id", contexto.id)
  if (error) return { ok: false, erro: error.message }

  recarregar()
  return { ok: true }
}

/**
 * Fecha o pedido.
 *
 * Manda o que a pessoa escolheu — jamais quanto custa. `fechar_pedido`
 * recalcula tudo a partir do cardapio daquele instante, e e o unico caminho
 * pelo qual um cliente cria pedido: a politica de INSERT em `orders` nao
 * aceita mais nada vindo dele.
 */
export async function fecharPedido(dados: {
  tipo: Enums<"fulfillment_type">
  forma: Enums<"payment_method">
  enderecoId?: string
  cupom?: string
  observacao?: string
  trocoPara?: string
}): Promise<ResultadoDaAcao> {
  const contexto = await exigirUsuario("/carrinho")
  const supabase = await criarClienteDoServidor()

  const { data: carrinho } = await supabase
    .from("carts")
    .select("id")
    .eq("user_id", contexto.id)
    .maybeSingle()

  if (!carrinho) return { ok: false, erro: "Seu carrinho está vazio." }

  // Pix e cartão de crédito são as formas que um gateway processa; o resto se
  // paga na porta. Enquanto o provedor é simulado, a tela prefere as de porta
  // — um pedido em "aguardando pagamento" nunca chegaria ao balcão.
  const noApp = dados.forma === "pix" || dados.forma === "credit_card"

  const troco = dados.trocoPara?.trim()
    ? Math.round(Number(dados.trocoPara.replace(/[^\d,.-]/g, "").replace(",", ".")) * 100)
    : null

  const { data: id, error } = await supabase.rpc("fechar_pedido", {
    p_cart_id: carrinho.id,
    p_fulfillment: dados.tipo,
    p_payment_method: dados.forma,
    p_payment_timing: noApp ? "online" : "on_delivery",
    p_address_id: dados.tipo === "delivery" ? (dados.enderecoId ?? undefined) : undefined,
    p_change_for_cents:
      dados.forma === "cash" && troco !== null ? troco : undefined,
    p_coupon_code: dados.cupom?.trim() || undefined,
    p_notes: dados.observacao?.trim() || undefined,
  })

  if (error) return { ok: false, erro: error.message }

  recarregar()
  revalidatePath("/pedidos")
  return { ok: true, id: id as string }
}

/**
 * Quanto um cupom abate, antes de fechar.
 *
 * A conta e do banco: `simular_cupom` usa a MESMA funcao de desconto que
 * `fechar_pedido` usa na hora de cobrar. Se a tela fizesse a propria conta, as
 * duas divergiriam no dia em que alguem mexesse numa delas.
 */
export async function simularCupom(dados: {
  codigo: string
  restauranteId: string
  subtotalCentavos: number
  taxaCentavos: number
}): Promise<{ ok: true; descontoCentavos: number } | { ok: false; erro: string }> {
  await exigirUsuario("/carrinho")
  const supabase = await criarClienteDoServidor()

  const { data, error } = await supabase.rpc("simular_cupom", {
    p_code: dados.codigo.trim(),
    p_restaurant: dados.restauranteId,
    p_subtotal_cents: dados.subtotalCentavos,
    p_delivery_fee_cents: dados.taxaCentavos,
  })

  // As mensagens vem do banco ja em portugues — "Este cupom venceu", "Voce ja
  // usou este cupom" — e chegam a tela como estao.
  if (error) return { ok: false, erro: error.message }

  const resposta = data as { discount_cents?: number } | null
  return { ok: true, descontoCentavos: Number(resposta?.discount_cents ?? 0) }
}

/** Quanto o carrinho tem, para o contador do cabeçalho. */
export async function contarItensDoCarrinho(): Promise<number> {
  const contexto = await obterContexto()
  if (!contexto) return 0

  const supabase = await criarClienteDoServidor()
  const { data } = await supabase
    .from("carts")
    .select("cart_items(quantity)")
    .eq("user_id", contexto.id)
    .maybeSingle()

  return (data?.cart_items ?? []).reduce((soma, i) => soma + i.quantity, 0)
}
