"use server"

import { revalidatePath } from "next/cache"

import { paraCentavos } from "@/lib/dinheiro"
import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirGestao } from "@/modules/auth/sessao"
import type { Enums } from "@/types/banco"

/**
 * O que o dono configura da propria loja.
 *
 * Tudo aqui ja valia no banco e so nao tinha tela: taxa e minimo entram na
 * conta de `fechar_pedido`, horario e a outra metade de "aberto agora", e as
 * formas de pagamento sao as que o checkout oferece. O que o dono NAO mexe -
 * situacao e comissao - fica de fora, e o gatilho
 * `app.guard_restaurant_platform_fields` recusaria de qualquer jeito.
 */

export type ResultadoDaAcao = { ok: true } | { ok: false; erro: string; campo?: string }

export async function salvarConfiguracoes(dados: {
  nome: string
  descricao?: string
  telefone?: string
  taxaDeEntrega: string
  freteGratisAcima?: string
  pedidoMinimo: string
  minutosDePreparo: string
  minutosDeEntrega: string
  raioKm: string
  aceitaAgendamento: boolean
}): Promise<ResultadoDaAcao> {
  const { vinculo } = await exigirGestao()
  const supabase = await criarClienteDoServidor()

  if (dados.nome.trim().length < 2) {
    return { ok: false, erro: "A loja precisa de um nome.", campo: "nome" }
  }

  const taxa = paraCentavos(dados.taxaDeEntrega) ?? 0
  const minimo = paraCentavos(dados.pedidoMinimo) ?? 0
  const gratisAcima = dados.freteGratisAcima?.trim()
    ? paraCentavos(dados.freteGratisAcima)
    : null

  if (taxa < 0 || minimo < 0) {
    return { ok: false, erro: "Valores não podem ser negativos." }
  }

  const { error } = await supabase
    .from("restaurants")
    .update({
      name: dados.nome.trim(),
      description: dados.descricao?.trim() || null,
      // O banco exige só dígitos no telefone; tirar a máscara aqui evita a
      // rejeição do check no fim do formulário.
      phone: dados.telefone?.replace(/\D/g, "") || null,
      delivery_fee_cents: taxa,
      free_delivery_above_cents: gratisAcima,
      min_order_cents: minimo,
      avg_prep_minutes: Math.max(1, Number(dados.minutosDePreparo) || 30),
      avg_delivery_minutes: Math.max(1, Number(dados.minutosDeEntrega) || 20),
      delivery_radius_km: Math.max(0.5, Number(dados.raioKm.replace(",", ".")) || 5),
      accepts_scheduled_orders: dados.aceitaAgendamento,
    })
    .eq("id", vinculo.restauranteId)

  if (error) return { ok: false, erro: error.message }

  revalidatePath("/painel/configuracoes")
  revalidatePath("/painel/pedidos")
  revalidatePath("/")
  return { ok: true }
}

export async function mudarFormaDePagamento(
  metodo: Enums<"payment_method">,
  momento: Enums<"payment_timing">,
  aceita: boolean,
): Promise<ResultadoDaAcao> {
  const { vinculo } = await exigirGestao()
  const supabase = await criarClienteDoServidor()

  // A mesma forma pode valer online e na entrega com regras diferentes; por
  // isso `timing` entra na chave, e o upsert precisa das tres colunas.
  const { error } = await supabase.from("restaurant_payment_methods").upsert(
    {
      restaurant_id: vinculo.restauranteId,
      method: metodo,
      timing: momento,
      is_active: aceita,
    },
    { onConflict: "restaurant_id,method,timing" },
  )

  if (error) return { ok: false, erro: error.message }

  revalidatePath("/painel/configuracoes")
  return { ok: true }
}

export async function salvarHorario(dados: {
  diaDaSemana: number
  abre: string
  fecha: string
}): Promise<ResultadoDaAcao> {
  const { vinculo } = await exigirGestao()
  const supabase = await criarClienteDoServidor()

  if (dados.abre === dados.fecha) {
    return { ok: false, erro: "Abrir e fechar no mesmo horário não é um turno." }
  }

  const { error } = await supabase.from("restaurant_hours").insert({
    restaurant_id: vinculo.restauranteId,
    weekday: dados.diaDaSemana,
    opens_at: dados.abre,
    closes_at: dados.fecha,
  })

  if (error) {
    if (error.code === "23505") {
      return { ok: false, erro: "Esse turno já existe nesse dia." }
    }
    return { ok: false, erro: error.message }
  }

  revalidatePath("/painel/configuracoes")
  return { ok: true }
}

export async function removerHorario(id: string): Promise<ResultadoDaAcao> {
  await exigirGestao()
  const supabase = await criarClienteDoServidor()

  const { error } = await supabase.from("restaurant_hours").delete().eq("id", id)
  if (error) return { ok: false, erro: error.message }

  revalidatePath("/painel/configuracoes")
  return { ok: true }
}

// ---------------------------------------------------------------------------
// Entregadores do estabelecimento
// ---------------------------------------------------------------------------

export async function decidirSobreEntregador(
  entregadorId: string,
  situacao: Enums<"courier_status">,
): Promise<ResultadoDaAcao> {
  await exigirGestao()
  const supabase = await criarClienteDoServidor()

  const { error } = await supabase
    .from("couriers")
    .update({
      status: situacao,
      // Suspender alguém não pode deixá-lo "disponível" na fila; o banco
      // recusaria na próxima mudança e a tela mentiria até lá.
      ...(situacao === "approved" ? {} : { availability: "offline" as const }),
    })
    .eq("id", entregadorId)

  if (error) return { ok: false, erro: error.message }

  revalidatePath("/painel/entregas")
  return { ok: true }
}

export async function aceitarEntregadorDaPlataforma(
  aceita: boolean,
): Promise<ResultadoDaAcao> {
  const { vinculo } = await exigirGestao()
  const supabase = await criarClienteDoServidor()

  const { error } = await supabase
    .from("restaurants")
    .update({ accepts_platform_couriers: aceita })
    .eq("id", vinculo.restauranteId)

  if (error) return { ok: false, erro: error.message }

  revalidatePath("/painel/entregas")
  return { ok: true }
}

/**
 * Guarda a URL da logo ou da capa.
 *
 * O arquivo ja esta no balde quando isto roda: quem enviou foi o navegador,
 * com a sessao da pessoa, e a politica do balde ja recusou quem nao gerencia a
 * loja. Aqui so se grava o endereco.
 *
 * A foto antiga fica no balde. Apagar exigiria guardar o caminho anterior e
 * lidar com o caso de duas abas trocando a foto ao mesmo tempo; o custo de
 * alguns kilobytes parados e menor que o de apagar a foto errada.
 */
export async function salvarImagemDaLoja(
  qual: "logo" | "capa",
  url: string | null,
): Promise<ResultadoDaAcao> {
  const { vinculo } = await exigirGestao()
  const supabase = await criarClienteDoServidor()

  const { error } = await supabase
    .from("restaurants")
    .update(qual === "logo" ? { logo_url: url } : { cover_url: url })
    .eq("id", vinculo.restauranteId)

  if (error) return { ok: false, erro: error.message }

  revalidatePath("/painel/configuracoes")
  revalidatePath("/painel")
  revalidatePath("/")
  revalidatePath(`/restaurante/${vinculo.slug}`)
  return { ok: true }
}

/**
 * A chave Pix da loja.
 *
 * O dinheiro vai direto para a conta do restaurante — a plataforma nao passa no
 * meio, nao retem nada e nao cobra taxa por transacao. O que ela faz e montar o
 * codigo com o valor certo e mostrar ao cliente.
 *
 * Nome e cidade nao sao enfeite: eles aparecem no aplicativo do banco na hora
 * de confirmar, e nome que o cliente nao reconhece e pagamento que nao acontece.
 */
export async function salvarPix(dados: {
  chave: string
  tipo: string
  nomeDoRecebedor: string
  cidade: string
}): Promise<ResultadoDaAcao> {
  const { vinculo } = await exigirGestao()
  const supabase = await criarClienteDoServidor()

  const chave = dados.chave.trim()

  // Apagar a chave desliga o Pix — e a tela de fechar pedido deixa de
  // oferece-lo, em vez de oferecer e falhar.
  if (chave === "") {
    const { error } = await supabase
      .from("restaurants")
      .update({ pix_key: null, pix_key_type: null })
      .eq("id", vinculo.restauranteId)
    if (error) return { ok: false, erro: error.message }
    revalidatePath("/painel/configuracoes")
    return { ok: true }
  }

  const tipos = ["cpf", "cnpj", "email", "telefone", "aleatoria"]
  if (!tipos.includes(dados.tipo)) {
    return { ok: false, erro: "Escolha o tipo da chave.", campo: "tipo" }
  }

  const erroDaChave = conferirChavePix(chave, dados.tipo)
  if (erroDaChave) return { ok: false, erro: erroDaChave, campo: "chave" }

  if (dados.nomeDoRecebedor.trim().length < 2) {
    return {
      ok: false,
      erro: "O nome de quem recebe aparece no banco do cliente.",
      campo: "nomeDoRecebedor",
    }
  }
  if (dados.cidade.trim().length < 2) {
    return { ok: false, erro: "A cidade também entra no código.", campo: "cidade" }
  }

  const { error } = await supabase
    .from("restaurants")
    .update({
      pix_key: chave,
      pix_key_type: dados.tipo,
      pix_recipient_name: dados.nomeDoRecebedor.trim(),
      pix_city: dados.cidade.trim(),
    })
    .eq("id", vinculo.restauranteId)

  if (error) return { ok: false, erro: error.message }

  revalidatePath("/painel/configuracoes")
  revalidatePath("/painel")
  return { ok: true }
}

/**
 * Chave errada so aparece quando o cliente tenta pagar — e ai o pedido ja
 * esta parado. Conferir aqui e mais barato do que descobrir depois.
 */
function conferirChavePix(chave: string, tipo: string): string | null {
  const digitos = chave.replace(/\D/g, "")

  switch (tipo) {
    case "cpf":
      return digitos.length === 11 ? null : "CPF tem 11 dígitos."
    case "cnpj":
      return digitos.length === 14 ? null : "CNPJ tem 14 dígitos."
    case "telefone":
      return digitos.length >= 10 && digitos.length <= 13
        ? null
        : "Telefone com DDD, entre 10 e 13 dígitos."
    case "email":
      return /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(chave) ? null : "E-mail inválido."
    case "aleatoria":
      // A chave aleatória do Banco Central é um uuid.
      return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(chave)
        ? null
        : "A chave aleatória tem o formato de um UUID."
    default:
      return "Tipo de chave desconhecido."
  }
}
