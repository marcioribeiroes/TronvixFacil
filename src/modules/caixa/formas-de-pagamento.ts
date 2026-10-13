/**
 * As formas de pagamento, como o caixa fala delas.
 *
 * A ordem e a da gaveta para a maquininha: dinheiro primeiro, porque e o que
 * alguem conta na mao no fim do turno.
 */

export const FORMAS_DE_PAGAMENTO = [
  "cash",
  "debit_card",
  "credit_card",
  "pix",
  "meal_voucher",
] as const

export type FormaDePagamento = (typeof FORMAS_DE_PAGAMENTO)[number]

export const ROTULO_DA_FORMA: Record<FormaDePagamento, string> = {
  cash: "Dinheiro",
  debit_card: "Débito",
  credit_card: "Crédito",
  pix: "Pix",
  meal_voucher: "Vale-refeição",
}

export function formaDePagamento(valor: string): FormaDePagamento | null {
  return (FORMAS_DE_PAGAMENTO as readonly string[]).includes(valor)
    ? (valor as FormaDePagamento)
    : null
}
