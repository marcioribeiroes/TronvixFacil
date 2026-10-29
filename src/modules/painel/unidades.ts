/**
 * As unidades de ingrediente. Espelho do check de `ingredients.unit`: uma
 * lista curta de proposito - "kg" e "quilo" na mesma loja dividiriam o mesmo
 * tomate em dois saldos.
 */
export const UNIDADES = ["kg", "g", "L", "ml", "un"] as const

export type Unidade = (typeof UNIDADES)[number]

/** "2.5" para "2,5", sem zeros sobrando: "3,000" vira "3". */
export function emQuantidade(valor: number, unidade?: string | null) {
  const numero = valor.toLocaleString("pt-BR", { maximumFractionDigits: 3 })
  return unidade ? `${numero} ${unidade}` : numero
}
