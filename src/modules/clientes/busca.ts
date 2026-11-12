import { normalizar } from "@/modules/cardapio/busca"

/**
 * Achar um cliente do caderno pelo que o balcao digita: um pedaco do nome,
 * sem acento ("joao" acha "João"), ou um pedaco do telefone, com ou sem
 * mascara ("99999" ou "(62) 9999").
 */
export function clienteCombina(
  c: { nome: string; telefone: string | null },
  digitado: string,
): boolean {
  const termo = normalizar(digitado)
  if (termo === "") return true

  const digitos = termo.replace(/\D/g, "")
  if (digitos.length >= 3 && c.telefone?.includes(digitos)) return true

  const nome = normalizar(c.nome)
  return termo.split(/\s+/).every((palavra) => nome.includes(palavra))
}
