/**
 * A busca de produto no cardapio do balcao.
 *
 * Quem atende digita do jeito que fala - "coca", "file parmegiana", sem
 * acento - ou passa o leitor no codigo de barras da lata. As duas coisas cabem
 * no mesmo campo: texto procura no nome e na descricao; numero procura tambem
 * no codigo de barras.
 */

/** Sem acento, sem maiuscula e sem espaco sobrando: "Filé " vira "file". */
export function normalizar(texto: string): string {
  return texto.normalize("NFD").replace(/\p{Diacritic}/gu, "").toLowerCase().trim()
}

type Pesquisavel = {
  name: string
  description: string | null
  barcode?: string | null
}

/**
 * O produto combina com o que foi digitado?
 *
 * Cada palavra tem de aparecer no nome ou na descricao, em qualquer ordem:
 * "parmegiana file" acha "File a parmegiana". Numero com tres digitos ou mais
 * tambem vale como pedaco do codigo de barras.
 */
export function produtoCombina(p: Pesquisavel, digitado: string): boolean {
  const termo = normalizar(digitado)
  if (termo === "") return true

  const digitos = termo.replace(/\D/g, "")
  if (p.barcode && digitos.length >= 3 && digitos === termo.replace(/\s/g, "")) {
    if (p.barcode.includes(digitos)) return true
  }

  const texto = normalizar(`${p.name} ${p.description ?? ""}`)
  return termo.split(/\s+/).every((palavra) => texto.includes(palavra))
}

/**
 * O produto que o leitor de codigo de barras apontou: o unico com aquele
 * codigo exato. Dois produtos com o mesmo codigo nao abrem nenhum - escolher
 * um no lugar do outro e lancar o item errado sem ninguem ver.
 */
export function produtoDoCodigo<T extends Pesquisavel>(produtos: T[], digitado: string): T | null {
  const codigo = digitado.trim()
  if (!/^\d{6,}$/.test(codigo)) return null
  const achados = produtos.filter((p) => p.barcode === codigo)
  return achados.length === 1 ? achados[0] : null
}
