"use server"

import { revalidatePath } from "next/cache"
import { redirect } from "next/navigation"

import { ambientePublico } from "@/lib/ambiente"
import { criarClienteDoServidor } from "@/lib/supabase/servidor"

import { rotaInicialDe, obterContexto } from "./sessao"
import {
  schemaDeCadastro,
  schemaDeLogin,
  schemaDeNovaSenha,
  schemaDeRecuperacao,
} from "./schema"

/**
 * Server Actions de autenticacao.
 *
 * Contrato de retorno: { erro } quando algo impede a operacao, { sucesso }
 * quando o formulario deve mostrar confirmacao, e redirect() quando a pessoa
 * precisa sair da tela. Nunca lancam excecao para a tela tratar - um erro de
 * login e um estado normal do formulario, nao uma falha do sistema.
 */

export type ResultadoDaAcao =
  | { ok: true; mensagem?: string }
  | { ok: false; erro: string; campo?: string }

/**
 * Mensagens de erro do Supabase traduzidas.
 *
 * "Credenciais invalidas" e proposital: nao dizemos se foi o e-mail ou a senha
 * que errou. Dizer qual dos dois confirma para quem esta tentando adivinhar
 * que aquele e-mail tem conta na plataforma.
 */
function traduzirErro(mensagem: string): string {
  const conhecidos: Record<string, string> = {
    "Invalid login credentials": "E-mail ou senha incorretos.",
    "Email not confirmed": "Confirme seu e-mail antes de entrar.",
    "User already registered": "Ja existe uma conta com este e-mail.",
    "Password should be at least 6 characters": "A senha e muito curta.",
    "Email rate limit exceeded": "Muitas tentativas. Aguarde alguns minutos.",
    "Auth session missing!": "Sua sessao expirou. Entre novamente.",
  }
  return conhecidos[mensagem] ?? "Nao foi possivel concluir. Tente novamente."
}

export async function entrar(_anterior: unknown, formulario: FormData): Promise<ResultadoDaAcao> {
  const analise = schemaDeLogin.safeParse({
    email: formulario.get("email"),
    senha: formulario.get("senha"),
    voltarPara: formulario.get("voltar_para") ?? undefined,
  })

  if (!analise.success) {
    const primeiro = analise.error.issues[0]
    return { ok: false, erro: primeiro.message, campo: String(primeiro.path[0] ?? "") }
  }

  const supabase = await criarClienteDoServidor()
  const { error } = await supabase.auth.signInWithPassword({
    email: analise.data.email,
    password: analise.data.senha,
  })

  if (error) return { ok: false, erro: traduzirErro(error.message) }

  const contexto = await obterContexto()
  revalidatePath("/", "layout")

  // So aceitamos destino interno. Sem esta checagem, um link com
  // ?voltar_para=https://site-falso funcionaria como redirecionamento aberto,
  // usando o dominio da plataforma para dar credibilidade a uma pagina de
  // phishing.
  const pedido = analise.data.voltarPara
  const destinoSeguro = pedido && pedido.startsWith("/") && !pedido.startsWith("//") ? pedido : null

  redirect(destinoSeguro ?? (contexto ? rotaInicialDe(contexto) : "/"))
}

export async function criarConta(
  _anterior: unknown,
  formulario: FormData,
): Promise<ResultadoDaAcao> {
  const analise = schemaDeCadastro.safeParse({
    nome: formulario.get("nome"),
    email: formulario.get("email"),
    telefone: formulario.get("telefone"),
    senha: formulario.get("senha"),
    confirmacao: formulario.get("confirmacao"),
  })

  if (!analise.success) {
    const primeiro = analise.error.issues[0]
    return { ok: false, erro: primeiro.message, campo: String(primeiro.path[0] ?? "") }
  }

  const supabase = await criarClienteDoServidor()

  // O papel vai nos metadados e e lido pelo gatilho app.handle_new_user, que
  // cria o perfil na mesma transacao do usuario. Fixamos 'customer' aqui: o
  // cadastro publico nunca cria entregador nem administrador.
  const { error } = await supabase.auth.signUp({
    email: analise.data.email,
    password: analise.data.senha,
    options: {
      data: {
        full_name: analise.data.nome,
        phone: analise.data.telefone,
        platform_role: "customer",
      },
      emailRedirectTo: `${ambientePublico.urlDoSite}/entrar`,
    },
  })

  if (error) return { ok: false, erro: traduzirErro(error.message) }

  revalidatePath("/", "layout")
  redirect("/")
}

export async function sair(): Promise<void> {
  const supabase = await criarClienteDoServidor()
  await supabase.auth.signOut()
  revalidatePath("/", "layout")
  redirect("/entrar")
}

export async function pedirRecuperacao(
  _anterior: unknown,
  formulario: FormData,
): Promise<ResultadoDaAcao> {
  const analise = schemaDeRecuperacao.safeParse({ email: formulario.get("email") })

  if (!analise.success) {
    return { ok: false, erro: analise.error.issues[0].message, campo: "email" }
  }

  const supabase = await criarClienteDoServidor()
  await supabase.auth.resetPasswordForEmail(analise.data.email, {
    redirectTo: `${ambientePublico.urlDoSite}/nova-senha`,
  })

  // Resposta igual existindo a conta ou nao. Confirmar a existencia
  // transformaria esta tela num verificador de e-mails cadastrados.
  return {
    ok: true,
    mensagem: "Se houver uma conta com este e-mail, o link de recuperacao chegara em instantes.",
  }
}

export async function definirNovaSenha(
  _anterior: unknown,
  formulario: FormData,
): Promise<ResultadoDaAcao> {
  const analise = schemaDeNovaSenha.safeParse({
    senha: formulario.get("senha"),
    confirmacao: formulario.get("confirmacao"),
  })

  if (!analise.success) {
    const primeiro = analise.error.issues[0]
    return { ok: false, erro: primeiro.message, campo: String(primeiro.path[0] ?? "") }
  }

  const supabase = await criarClienteDoServidor()
  const { error } = await supabase.auth.updateUser({ password: analise.data.senha })

  if (error) return { ok: false, erro: traduzirErro(error.message) }

  revalidatePath("/", "layout")
  return { ok: true, mensagem: "Senha alterada. Voce ja pode entrar com ela." }
}

/**
 * Apaga a conta de quem esta conectado.
 *
 * O caminho e exigido pela Play Store — aplicativo que deixa criar conta tem
 * de deixar apagar, por dentro e por uma pagina publica — e pela LGPD. Quem
 * decide o que pode sair e o BANCO: `apagar_minha_conta` recusa dono de loja,
 * entregador e quem tem pedido em andamento, e anonimiza os pedidos antigos em
 * vez de apaga-los, porque a venda e do restaurante.
 *
 * Aqui em cima sobra o resto: derrubar a sessao, que senao fica um cookie
 * apontando para um usuario que nao existe mais.
 */
export async function apagarMinhaConta(): Promise<ResultadoDaAcao> {
  const supabase = await criarClienteDoServidor()

  const { error } = await supabase.rpc("apagar_minha_conta")
  if (error) return { ok: false, erro: error.message }

  await supabase.auth.signOut()
  revalidatePath("/", "layout")
  return { ok: true }
}
