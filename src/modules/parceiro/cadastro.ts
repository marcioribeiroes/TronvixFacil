"use server"

import { revalidatePath } from "next/cache"

import { coordenadasDoCep } from "@/lib/geocodificar"
import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirUsuario } from "@/modules/auth/sessao"

/**
 * O dono cadastra o proprio estabelecimento.
 *
 * Esta acao nao monta o INSERT: ela chama `cadastrar_estabelecimento`, e todas
 * as regras vivem la dentro - a loja nasce esperando aprovacao, fechada, com a
 * comissao padrao da plataforma, e quem chamou vira dono. A tabela
 * `restaurants` continua fechada a INSERT de quem nao e administrador.
 *
 * Por que isso importa: se a regra estivesse aqui, bastaria alguem chamar a API
 * do Supabase direto, com a chave anonima que vai publicada em todo aplicativo
 * instalado, para nascer aprovado e sem comissao.
 */

export type ResultadoDoCadastro =
  | { ok: true; slug: string }
  | { ok: false; erro: string; campo?: string }

export async function cadastrarEstabelecimento(dados: {
  nome: string
  telefone: string
  documento?: string
  descricao?: string
  email?: string
  cep?: string
  rua: string
  numero: string
  complemento?: string
  bairro: string
  cidade: string
  estado: string
}): Promise<ResultadoDoCadastro> {
  await exigirUsuario("/cadastrar-restaurante")
  const supabase = await criarClienteDoServidor()

  // Conferencia de borda, so para adiantar a mensagem. Quem recusa de verdade e
  // a funcao no banco - e ela recusa a mesma coisa, pelos mesmos motivos.
  if (dados.nome.trim().length < 2) {
    return { ok: false, erro: "O estabelecimento precisa de um nome.", campo: "nome" }
  }
  const telefone = dados.telefone.replace(/\D/g, "")
  if (telefone.length < 10 || telefone.length > 13) {
    return { ok: false, erro: "Informe DDD e número.", campo: "telefone" }
  }
  for (const [campo, valor, rotulo] of [
    ["rua", dados.rua, "a rua"],
    ["numero", dados.numero, "o número"],
    ["bairro", dados.bairro, "o bairro"],
    ["cidade", dados.cidade, "a cidade"],
  ] as const) {
    if (valor.trim() === "") {
      return { ok: false, erro: `Falta ${rotulo}: é de onde o pedido sai.`, campo }
    }
  }

  const { data, error } = await supabase.rpc("cadastrar_estabelecimento", {
    p_nome: dados.nome,
    p_telefone: dados.telefone,
    p_rua: dados.rua,
    p_numero: dados.numero,
    p_bairro: dados.bairro,
    p_cidade: dados.cidade,
    p_estado: dados.estado,
    p_cep: dados.cep || undefined,
    p_complemento: dados.complemento || undefined,
    p_documento: dados.documento || undefined,
    p_descricao: dados.descricao || undefined,
    p_email: dados.email || undefined,
  })

  if (error) return { ok: false, erro: error.message }

  const criado = data?.[0]
  if (!criado) return { ok: false, erro: "O cadastro não voltou do banco. Tente de novo." }

  /**
   * Onde a loja fica, a partir do CEP.
   *
   * Sem coordenada a corrida nasce sem distância, o mapa de coleta do
   * entregador fica vazio e o raio de entrega não tem centro. Até aqui nenhuma
   * tela escrevia esses campos — só a semente de demonstração — e toda loja de
   * verdade nascia cega.
   *
   * Depois do cadastro, e não dentro dele, de propósito: é serviço externo, e
   * ninguém pode deixar de abrir a loja porque a BrasilAPI está fora do ar.
   * Falhando, a loja existe do mesmo jeito e a coordenada se resolve depois.
   */
  if (dados.cep) {
    const onde = await coordenadasDoCep(dados.cep)
    if (onde) {
      await supabase
        .from("restaurants")
        .update({ latitude: onde.latitude, longitude: onde.longitude })
        .eq("id", criado.id)
    }
  }

  revalidatePath("/painel")
  revalidatePath("/admin/restaurantes")
  revalidatePath("/admin")

  return { ok: true, slug: criado.slug }
}
