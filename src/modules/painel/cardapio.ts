"use server"

import { revalidatePath } from "next/cache"

import { paraCentavos } from "@/lib/dinheiro"
import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirGestao, exigirVinculo } from "@/modules/auth/sessao"

/**
 * O cardapio, pelo navegador.
 *
 * Duas exigencias diferentes de propósito:
 *
 *   exigirGestao  para cadastrar e apagar - dono e gerente.
 *   exigirVinculo para tirar item do ar - o atendente precisa, e e a operacao
 *                 mais usada no meio do movimento: acabou o hamburguer, some
 *                 do cardapio agora.
 *
 * Nada aqui confere pertencimento na mao: a RLS de `products` e `categories`
 * so devolve e so aceita linha do estabelecimento de quem chamou.
 */

export type ResultadoDaAcao = { ok: true } | { ok: false; erro: string; campo?: string }

function recarregar() {
  for (const rota of ["/painel/cardapio", "/painel/produtos", "/painel/categorias", "/painel/adicionais"]) {
    revalidatePath(rota)
  }
}

// ---------------------------------------------------------------------------
// Categorias
// ---------------------------------------------------------------------------

export async function salvarCategoria(dados: {
  id?: string
  nome: string
  descricao?: string
  posicao?: number
}): Promise<ResultadoDaAcao> {
  const { vinculo } = await exigirGestao()
  const supabase = await criarClienteDoServidor()

  const nome = dados.nome.trim()
  if (nome.length < 2) return { ok: false, erro: "Dê um nome à seção.", campo: "nome" }

  const campos = {
    restaurant_id: vinculo.restauranteId,
    name: nome,
    description: dados.descricao?.trim() || null,
    position: dados.posicao ?? 0,
  }

  const { error } = dados.id
    ? await supabase.from("categories").update(campos).eq("id", dados.id)
    : await supabase.from("categories").insert(campos)

  if (error) {
    // O banco recusa duas secoes com o mesmo nome na mesma loja, ignorando
    // maiusculas. A mensagem dele e tecnica; esta e a que ajuda.
    if (error.code === "23505") {
      return { ok: false, erro: "Já existe uma seção com esse nome.", campo: "nome" }
    }
    return { ok: false, erro: error.message }
  }

  recarregar()
  return { ok: true }
}

/**
 * Apagar categoria e exclusao logica.
 *
 * `products.category_id` aponta para ela com ON DELETE RESTRICT: apagar de
 * verdade seria impossivel com produto dentro, e apagar junto levaria o
 * historico de vendas. Some do cardapio, continua no passado.
 */
export async function removerCategoria(id: string): Promise<ResultadoDaAcao> {
  await exigirGestao()
  const supabase = await criarClienteDoServidor()

  const { count } = await supabase
    .from("products")
    .select("id", { count: "exact", head: true })
    .eq("category_id", id)
    .is("deleted_at", null)

  if ((count ?? 0) > 0) {
    return {
      ok: false,
      erro: `Essa seção tem ${count} produto(s). Mova-os antes de removê-la.`,
    }
  }

  const { error } = await supabase
    .from("categories")
    .update({ deleted_at: new Date().toISOString(), is_active: false })
    .eq("id", id)

  if (error) return { ok: false, erro: error.message }

  recarregar()
  return { ok: true }
}

// ---------------------------------------------------------------------------
// Produtos
// ---------------------------------------------------------------------------

export async function salvarProduto(dados: {
  id?: string
  categoriaId: string
  nome: string
  descricao?: string
  preco: string
  precoPromocional?: string
  promocaoTerminaEm?: string
  disponivel: boolean
  destaque: boolean
  controlaEstoque: boolean
  estoque?: string
  /**
   * A foto já está no balde quando isto roda — quem enviou foi o navegador,
   * com a sessão da pessoa. Aqui só se grava o endereço.
   */
  imagemUrl?: string | null
}): Promise<ResultadoDaAcao> {
  const { vinculo } = await exigirGestao()
  const supabase = await criarClienteDoServidor()

  const nome = dados.nome.trim()
  if (nome.length < 2) return { ok: false, erro: "Dê um nome ao produto.", campo: "nome" }

  const preco = paraCentavos(dados.preco)
  if (preco === null || preco <= 0) {
    return { ok: false, erro: "Escreva o preço, como 27,90.", campo: "preco" }
  }

  const promo = dados.precoPromocional?.trim()
    ? paraCentavos(dados.precoPromocional)
    : null

  // O banco recusa promoção >= preço cheio; recusar aqui é mais gentil do que
  // deixar a gravação falhar no fim do formulário.
  if (promo !== null && promo >= preco) {
    return {
      ok: false,
      erro: "A promoção precisa ser menor que o preço cheio.",
      campo: "precoPromocional",
    }
  }

  const estoque = dados.controlaEstoque ? Number(dados.estoque ?? 0) : 0
  if (dados.controlaEstoque && (!Number.isInteger(estoque) || estoque < 0)) {
    return { ok: false, erro: "O estoque é um número inteiro.", campo: "estoque" }
  }

  const campos = {
    restaurant_id: vinculo.restauranteId,
    category_id: dados.categoriaId,
    name: nome,
    description: dados.descricao?.trim() || null,
    price_cents: preco,
    promo_price_cents: promo,
    // Promoção sem fim é promoção que virou preço. Quando há data, ela vale
    // até lá; sem data, vale até alguém tirar.
    promo_ends_at: promo !== null && dados.promocaoTerminaEm
      ? new Date(dados.promocaoTerminaEm).toISOString()
      : null,
    image_url: dados.imagemUrl ?? null,
    is_available: dados.disponivel,
    is_featured: dados.destaque,
    track_stock: dados.controlaEstoque,
    stock_quantity: estoque,
  }

  const { error } = dados.id
    ? await supabase.from("products").update(campos).eq("id", dados.id)
    : await supabase.from("products").insert(campos)

  if (error) return { ok: false, erro: error.message }

  recarregar()
  return { ok: true }
}

/** Tirar e repor item do ar: a operação mais usada no meio do movimento. */
export async function mudarDisponibilidade(
  id: string,
  disponivel: boolean,
): Promise<ResultadoDaAcao> {
  await exigirVinculo()
  const supabase = await criarClienteDoServidor()

  const { error } = await supabase
    .from("products")
    .update({ is_available: disponivel })
    .eq("id", id)

  if (error) return { ok: false, erro: error.message }

  recarregar()
  return { ok: true }
}

/**
 * Remover produto é exclusão lógica.
 *
 * `order_items` aponta para ele com ON DELETE SET NULL e guarda o nome e o
 * preço copiados; apagar de verdade não quebraria o pedido antigo, mas
 * apagaria a possibilidade de voltar atrás. Some do cardápio, continua no
 * histórico.
 */
export async function removerProduto(id: string): Promise<ResultadoDaAcao> {
  await exigirGestao()
  const supabase = await criarClienteDoServidor()

  const { error } = await supabase
    .from("products")
    .update({ deleted_at: new Date().toISOString(), is_available: false })
    .eq("id", id)

  if (error) return { ok: false, erro: error.message }

  recarregar()
  return { ok: true }
}

// ---------------------------------------------------------------------------
// Adicionais
// ---------------------------------------------------------------------------

export async function salvarGrupoDeAdicionais(dados: {
  id?: string
  produtoId: string
  nome: string
  obrigatorio: boolean
  minimo: number
  maximo: number
}): Promise<ResultadoDaAcao> {
  const { vinculo } = await exigirGestao()
  const supabase = await criarClienteDoServidor()

  const nome = dados.nome.trim()
  if (nome.length < 2) return { ok: false, erro: "Dê um nome ao grupo.", campo: "nome" }

  // O banco recusa "obrigatório com mínimo zero" — um grupo assim não obriga
  // nada e só engana a tela. Corrigir aqui evita a rejeição lá.
  const minimo = dados.obrigatorio ? Math.max(1, dados.minimo) : Math.max(0, dados.minimo)
  const maximo = Math.max(1, dados.maximo)

  if (minimo > maximo) {
    return { ok: false, erro: "O mínimo não pode ser maior que o máximo.", campo: "minimo" }
  }

  const campos = {
    restaurant_id: vinculo.restauranteId,
    product_id: dados.produtoId,
    name: nome,
    is_required: dados.obrigatorio,
    min_select: minimo,
    max_select: maximo,
  }

  const { error } = dados.id
    ? await supabase.from("addon_groups").update(campos).eq("id", dados.id)
    : await supabase.from("addon_groups").insert(campos)

  if (error) return { ok: false, erro: error.message }

  recarregar()
  return { ok: true }
}

export async function salvarAdicional(dados: {
  id?: string
  grupoId: string
  nome: string
  preco: string
}): Promise<ResultadoDaAcao> {
  const { vinculo } = await exigirGestao()
  const supabase = await criarClienteDoServidor()

  const nome = dados.nome.trim()
  if (nome.length < 1) return { ok: false, erro: "Dê um nome ao adicional.", campo: "nome" }

  // Adicional de graça é comum — "sem cebola", "ao ponto" — então preço vazio
  // vale zero, e não erro.
  const preco = dados.preco.trim() ? (paraCentavos(dados.preco) ?? 0) : 0
  if (preco < 0) return { ok: false, erro: "Preço inválido.", campo: "preco" }

  const campos = {
    restaurant_id: vinculo.restauranteId,
    group_id: dados.grupoId,
    name: nome,
    price_cents: preco,
  }

  const { error } = dados.id
    ? await supabase.from("addons").update(campos).eq("id", dados.id)
    : await supabase.from("addons").insert(campos)

  if (error) {
    if (error.code === "23505") {
      return { ok: false, erro: "Já existe um adicional com esse nome no grupo.", campo: "nome" }
    }
    return { ok: false, erro: error.message }
  }

  recarregar()
  return { ok: true }
}

export async function removerAdicional(id: string): Promise<ResultadoDaAcao> {
  await exigirGestao()
  const supabase = await criarClienteDoServidor()

  const { error } = await supabase
    .from("addons")
    .update({ deleted_at: new Date().toISOString(), is_available: false })
    .eq("id", id)

  if (error) return { ok: false, erro: error.message }

  recarregar()
  return { ok: true }
}

export async function removerGrupoDeAdicionais(id: string): Promise<ResultadoDaAcao> {
  await exigirGestao()
  const supabase = await criarClienteDoServidor()

  const { error } = await supabase
    .from("addon_groups")
    .update({ deleted_at: new Date().toISOString(), is_active: false })
    .eq("id", id)

  if (error) return { ok: false, erro: error.message }

  recarregar()
  return { ok: true }
}
