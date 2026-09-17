/**
 * Dinheiro no Tronvix Facil e sempre um inteiro de centavos.
 *
 * Nenhum valor monetario circula como number decimal em nenhuma camada: nem
 * no banco, nem na API, nem no estado do React. A razao e velha e continua
 * valendo - 0.1 + 0.2 === 0.30000000000000004 -, e numa plataforma de
 * delivery esse erro nao fica escondido: ele aparece na conferencia de caixa
 * do restaurante no fim do dia e na comissao que a plataforma retem.
 *
 * A conversao para decimal acontece uma unica vez, na borda de exibicao.
 */

/** Centavos. O tipo e nominal so por documentacao; o runtime e number. */
export type Centavos = number

const REAIS = new Intl.NumberFormat("pt-BR", {
  style: "currency",
  currency: "BRL",
})

/** Formata centavos como moeda brasileira: 2790 -> "R$ 27,90". */
export function formatarReais(centavos: Centavos): string {
  return REAIS.format(centavos / 100)
}

/** Formata sem o simbolo, para tabelas e campos: 2790 -> "27,90". */
export function formatarValor(centavos: Centavos): string {
  return (centavos / 100).toFixed(2).replace(".", ",")
}

/**
 * Converte o que o usuario digitou em centavos.
 *
 * Aceita as formas que aparecem de verdade num campo de preco: "27,90",
 * "R$ 27,90", "1.234,56", "27.90" e "2790,00". Devolve null quando nao da
 * para entender - quem chama decide se isso e erro de formulario ou zero.
 */
export function paraCentavos(entrada: string | number | null | undefined): Centavos | null {
  if (entrada === null || entrada === undefined) return null

  if (typeof entrada === "number") {
    if (!Number.isFinite(entrada)) return null
    return Math.round(entrada * 100)
  }

  const limpo = entrada.trim().replace(/[R$\s]/g, "")
  if (limpo === "") return null

  const temVirgula = limpo.includes(",")
  const temPonto = limpo.includes(".")

  let normalizado: string
  if (temVirgula && temPonto) {
    // "1.234,56" - o ponto e separador de milhar.
    normalizado = limpo.replace(/\./g, "").replace(",", ".")
  } else if (temVirgula) {
    normalizado = limpo.replace(",", ".")
  } else {
    normalizado = limpo
  }

  const numero = Number(normalizado)
  if (!Number.isFinite(numero)) return null

  return Math.round(numero * 100)
}

/**
 * Aplica um percentual expresso em pontos base.
 *
 * Pontos base (1500 = 15,00%) sao inteiros de proposito: guardar "15.5%" como
 * float traz de volta o problema que os centavos resolveram. O arredondamento
 * e half-up, o mesmo que o cliente faz de cabeca ao conferir a conta.
 */
export function aplicarPontosBase(centavos: Centavos, pontosBase: number): Centavos {
  return Math.round((centavos * pontosBase) / 10_000)
}

/** Converte percentual legivel em pontos base: 15 -> 1500. */
export function percentualParaPontosBase(percentual: number): number {
  return Math.round(percentual * 100)
}

/** Converte pontos base em percentual legivel: 1500 -> 15. */
export function pontosBaseParaPercentual(pontosBase: number): number {
  return pontosBase / 100
}

/** Soma centavos sem deixar escapar NaN de um item mal formado. */
export function somar(...valores: Centavos[]): Centavos {
  return valores.reduce<number>((total, valor) => total + (Number.isFinite(valor) ? valor : 0), 0)
}

/** Nunca deixa um valor monetario ficar negativo (desconto maior que o total). */
export function naoNegativo(centavos: Centavos): Centavos {
  return centavos < 0 ? 0 : centavos
}
