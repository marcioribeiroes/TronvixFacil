import { z } from "zod"

/**
 * Validacao das entradas de autenticacao.
 *
 * Os mesmos schemas rodam no formulario (feedback imediato) e na Server Action
 * (a validacao que vale). O navegador nunca e a ultima palavra: o que chega ao
 * servidor e revalidado aqui antes de tocar o banco.
 */

const SENHA_MINIMA = 8

export const telefone = z
  .string()
  .trim()
  .transform((valor) => valor.replace(/\D/g, ""))
  .refine((valor) => valor.length >= 10 && valor.length <= 13, {
    message: "Informe o telefone com DDD.",
  })

export const schemaDeLogin = z.object({
  email: z.string().trim().toLowerCase().email("Informe um e-mail valido."),
  senha: z.string().min(1, "Informe sua senha."),
  voltarPara: z.string().optional(),
})

export const schemaDeCadastro = z
  .object({
    nome: z
      .string()
      .trim()
      .min(3, "Informe seu nome completo.")
      .max(120, "Nome muito longo."),
    email: z.string().trim().toLowerCase().email("Informe um e-mail valido."),
    telefone,
    senha: z
      .string()
      .min(SENHA_MINIMA, `A senha precisa de pelo menos ${SENHA_MINIMA} caracteres.`)
      // Exigencia moderada de proposito: regras longas demais empurram a
      // pessoa para senhas anotadas em papel.
      .refine((valor) => /[a-zA-Z]/.test(valor) && /[0-9]/.test(valor), {
        message: "Use letras e numeros na senha.",
      }),
    confirmacao: z.string(),
  })
  .refine((dados) => dados.senha === dados.confirmacao, {
    message: "As senhas nao conferem.",
    path: ["confirmacao"],
  })

export const schemaDeRecuperacao = z.object({
  email: z.string().trim().toLowerCase().email("Informe um e-mail valido."),
})

export const schemaDeNovaSenha = z
  .object({
    senha: z
      .string()
      .min(SENHA_MINIMA, `A senha precisa de pelo menos ${SENHA_MINIMA} caracteres.`)
      .refine((valor) => /[a-zA-Z]/.test(valor) && /[0-9]/.test(valor), {
        message: "Use letras e numeros na senha.",
      }),
    confirmacao: z.string(),
  })
  .refine((dados) => dados.senha === dados.confirmacao, {
    message: "As senhas nao conferem.",
    path: ["confirmacao"],
  })

export type DadosDeLogin = z.infer<typeof schemaDeLogin>
export type DadosDeCadastro = z.infer<typeof schemaDeCadastro>
export type DadosDeRecuperacao = z.infer<typeof schemaDeRecuperacao>
export type DadosDeNovaSenha = z.infer<typeof schemaDeNovaSenha>
