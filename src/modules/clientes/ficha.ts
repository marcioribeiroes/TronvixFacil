import { z } from "zod"

/**
 * A ficha de um cliente no caderno da loja (`restaurant_customers`).
 *
 * A validacao mora aqui, fora da Server Action, para ser testada sem banco. O
 * banco confere de novo (nome, telefone so com digitos, telefone unico na
 * loja): esta e a primeira linha, com mensagem que o balcao entende.
 */

/** Texto opcional: vazio vira null, para nao gravar "" no lugar de nada. */
const opcional = (maximo: number, rotulo: string) =>
  z
    .string()
    .trim()
    .max(maximo, `${rotulo}: no máximo ${maximo} caracteres.`)
    .transform((v) => (v === "" ? null : v))

export const schemaDaFicha = z.object({
  nome: z
    .string()
    .trim()
    .min(1, "O cliente precisa de um nome.")
    .max(120, "Nome: no máximo 120 caracteres."),
  // Guarda so os digitos, como o lancamento de pedido: e por eles que a ficha
  // se encontra com os pedidos do cliente. Com DDD, 10 ou 11 digitos (ate 13
  // com o 55 do pais).
  telefone: z
    .string()
    .transform((v) => v.replace(/\D/g, ""))
    .refine((v) => v === "" || (v.length >= 10 && v.length <= 13), {
      message: "Telefone com DDD: (62) 99999-0000.",
    })
    .transform((v) => (v === "" ? null : v)),
  rua: opcional(200, "Rua"),
  numero: opcional(20, "Número"),
  complemento: opcional(100, "Complemento"),
  bairro: opcional(100, "Bairro"),
  cidade: opcional(100, "Cidade"),
  observacao: opcional(500, "Observação"),
})

export type FichaDigitada = z.input<typeof schemaDaFicha>
export type Ficha = z.output<typeof schemaDaFicha>

/** A ficha no formato da tabela. */
export function paraLinha(f: Ficha) {
  return {
    name: f.nome,
    phone: f.telefone,
    address_street: f.rua,
    address_number: f.numero,
    address_complement: f.complemento,
    address_district: f.bairro,
    address_city: f.cidade,
    notes: f.observacao,
  }
}

/** O endereco numa linha so, para a lista: "Rua das Flores, 30 - Centro". */
export function enderecoEmUmaLinha(f: {
  rua: string | null
  numero: string | null
  complemento: string | null
  bairro: string | null
}): string {
  const rua = [f.rua, f.numero].filter(Boolean).join(", ")
  return [rua, f.complemento, f.bairro].filter(Boolean).join(" · ")
}
