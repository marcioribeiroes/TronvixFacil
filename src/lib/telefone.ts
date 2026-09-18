/**
 * Telefone brasileiro, para ler e para discar.
 *
 * O banco guarda so digitos - e a unica forma que nao depende de como cada
 * tela resolveu escrever. A mascara e da borda de exibicao, como a de dinheiro.
 */

/** 62990000006 -> "(62) 99000-0006"; 6232000001 -> "(62) 3200-0001". */
export function formatarTelefone(bruto: string | null | undefined): string {
  if (!bruto) return ""

  const d = bruto.replace(/\D/g, "")
  // Numero vindo com o 55 na frente: tira, senao a mascara desloca tudo.
  const n = d.length > 11 && d.startsWith("55") ? d.slice(2) : d

  if (n.length === 11) return `(${n.slice(0, 2)}) ${n.slice(2, 7)}-${n.slice(7)}`
  if (n.length === 10) return `(${n.slice(0, 2)}) ${n.slice(2, 6)}-${n.slice(6)}`
  if (n.length === 9) return `${n.slice(0, 5)}-${n.slice(5)}`
  if (n.length === 8) return `${n.slice(0, 4)}-${n.slice(4)}`

  // Fora dos formatos conhecidos, devolve o que veio: inventar mascara em cima
  // de um numero estranho esconde o erro de cadastro em vez de mostra-lo.
  return bruto
}

/** So os digitos, para href="tel:". */
export function paraDiscagem(bruto: string): string {
  return bruto.replace(/\D/g, "")
}
