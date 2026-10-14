"use server"

import { revalidatePath } from "next/cache"
import { z } from "zod"

import { coordenadasDoCep } from "@/lib/geocodificar"
import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirUsuario } from "@/modules/auth/sessao"

/**
 * Os enderecos do cliente, pelo site.
 *
 * Ate aqui so o aplicativo cadastrava endereco: o link "Cadastrar" do carrinho
 * levava a uma pagina que nao existia, e quem pedia pelo navegador nao tinha
 * como receber em casa.
 *
 * A localizacao vem do CEP (BrasilAPI). E a do CEP, nao a da porta — numa
 * cidade, um CEP cobre um trecho de rua, e e precisao suficiente para a faixa
 * de taxa. Sem coordenada (CEP sem ponto, servico fora), o endereco salva do
 * mesmo jeito e paga a maior faixa da loja.
 */

export type ResultadoDaAcao = { ok: true } | { ok: false; erro: string }

const schemaDoEndereco = z.object({
  rotulo: z.string().trim().min(1, "Dê um nome ao endereço: Casa, Trabalho…").max(40),
  cep: z
    .string()
    .transform((v) => v.replace(/\D/g, ""))
    .refine((v) => v.length === 8, "CEP com 8 números."),
  rua: z.string().trim().min(2, "Informe a rua.").max(120),
  numero: z.string().trim().min(1, "Informe o número (ou S/N).").max(20),
  complemento: z.string().trim().max(80),
  bairro: z.string().trim().min(2, "Informe o bairro.").max(80),
  cidade: z.string().trim().min(2, "Informe a cidade.").max(80),
  uf: z
    .string()
    .trim()
    .toUpperCase()
    .refine((v) => /^[A-Z]{2}$/.test(v), "Estado com 2 letras, como GO."),
  referencia: z.string().trim().max(120),
  padrao: z.boolean(),
})

export type DadosDoEndereco = z.input<typeof schemaDoEndereco>

export async function salvarEndereco(dados: DadosDoEndereco): Promise<ResultadoDaAcao> {
  const contexto = await exigirUsuario("/conta/enderecos")

  const analise = schemaDoEndereco.safeParse(dados)
  if (!analise.success) {
    return { ok: false, erro: analise.error.issues[0]?.message ?? "Confira o endereço." }
  }
  const d = analise.data

  const supabase = await criarClienteDoServidor()
  const coordenadas = await coordenadasDoCep(d.cep)

  // Primeiro endereco vira o padrao sozinho: e o que o topo do site mostra e
  // o que a vitrine usa para dizer quem entrega.
  const { count } = await supabase
    .from("addresses")
    .select("id", { count: "exact", head: true })
    .eq("user_id", contexto.id)
    .is("deleted_at", null)
  const padrao = d.padrao || (count ?? 0) === 0

  // So um padrao por pessoa (indice unico): tira o anterior antes.
  if (padrao) {
    await supabase
      .from("addresses")
      .update({ is_default: false })
      .eq("user_id", contexto.id)
      .eq("is_default", true)
  }

  const { error } = await supabase.from("addresses").insert({
    user_id: contexto.id,
    label: d.rotulo,
    postal_code: d.cep,
    street: d.rua,
    number: d.numero,
    complement: d.complemento || null,
    district: d.bairro,
    city: d.cidade,
    state: d.uf,
    reference_point: d.referencia || null,
    latitude: coordenadas?.latitude ?? null,
    longitude: coordenadas?.longitude ?? null,
    is_default: padrao,
  })
  if (error) return { ok: false, erro: "Não deu para salvar o endereço. Tente de novo." }

  revalidarTudo()
  return { ok: true }
}

export async function tornarEnderecoPadrao(id: string): Promise<ResultadoDaAcao> {
  const contexto = await exigirUsuario("/conta/enderecos")
  if (!z.uuid().safeParse(id).success) return { ok: false, erro: "Endereço inválido." }

  const supabase = await criarClienteDoServidor()
  await supabase
    .from("addresses")
    .update({ is_default: false })
    .eq("user_id", contexto.id)
    .eq("is_default", true)
  const { error } = await supabase
    .from("addresses")
    .update({ is_default: true })
    .eq("id", id)
    .eq("user_id", contexto.id)
  if (error) return { ok: false, erro: "Não deu para mudar o endereço." }

  revalidarTudo()
  return { ok: true }
}

/** Apagar e esconder: pedido antigo continua apontando para onde foi entregue. */
export async function removerEndereco(id: string): Promise<ResultadoDaAcao> {
  const contexto = await exigirUsuario("/conta/enderecos")
  if (!z.uuid().safeParse(id).success) return { ok: false, erro: "Endereço inválido." }

  const supabase = await criarClienteDoServidor()
  const { error } = await supabase
    .from("addresses")
    .update({ deleted_at: new Date().toISOString(), is_default: false })
    .eq("id", id)
    .eq("user_id", contexto.id)
  if (error) return { ok: false, erro: "Não deu para apagar o endereço." }

  revalidarTudo()
  return { ok: true }
}

function revalidarTudo() {
  // O endereco padrao aparece no topo de toda tela do cliente e muda a
  // vitrine: o layout inteiro precisa refazer.
  revalidatePath("/", "layout")
}
