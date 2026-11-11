/**
 * O "dia" de uma loja, para filtrar pedidos por data.
 *
 * O servidor roda em UTC; a loja, nao. Meia-noite calculada no servidor e
 * 21h em Sao Paulo: o pedido das 22h caia no dia seguinte e o placar de "hoje"
 * zerava no meio do jantar. Aqui o dia e sempre o da loja, no fuso dela
 * (`restaurants.timezone`).
 */

export const FORMATO_DO_DIA = /^\d{4}-\d{2}-\d{2}$/

/** AAAA-MM-DD valido de verdade: "2026-02-31" nao passa. */
export function diaValido(dia: unknown): dia is string {
  if (typeof dia !== "string" || !FORMATO_DO_DIA.test(dia)) return false
  const [ano, mes, d] = dia.split("-").map(Number)
  const data = new Date(Date.UTC(ano, mes - 1, d))
  return (
    data.getUTCFullYear() === ano && data.getUTCMonth() === mes - 1 && data.getUTCDate() === d
  )
}

/** O dia de hoje na loja, como AAAA-MM-DD. */
export function diaDeHoje(fuso: string, agora: Date = new Date()): string {
  // "en-CA" escreve a data ja no formato AAAA-MM-DD.
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: fuso,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(agora)
}

/** "-03:00" para Sao Paulo naquele instante. */
function deslocamento(fuso: string, instante: Date): string {
  const nome =
    new Intl.DateTimeFormat("en-US", { timeZone: fuso, timeZoneName: "longOffset" })
      .formatToParts(instante)
      .find((p) => p.type === "timeZoneName")?.value ?? "GMT"
  // "GMT" sozinho e o proprio UTC.
  return nome === "GMT" ? "+00:00" : nome.replace("GMT", "")
}

function diaSeguinte(dia: string): string {
  const [ano, mes, d] = dia.split("-").map(Number)
  return new Date(Date.UTC(ano, mes - 1, d + 1)).toISOString().slice(0, 10)
}

function meiaNoite(dia: string, fuso: string): string {
  // O deslocamento lido ao meio-dia em UTC do proprio dia: longe o bastante da
  // virada para nao pegar o fuso da vespera.
  const meioDia = new Date(`${dia}T12:00:00Z`)
  return new Date(`${dia}T00:00:00${deslocamento(fuso, meioDia)}`).toISOString()
}

/**
 * O intervalo do dia, em ISO, para a consulta: `inicio` entra, `fim` nao
 * (`gte(inicio)` e `lt(fim)`).
 */
export function limitesDoDia(dia: string, fuso: string): { inicio: string; fim: string } {
  return { inicio: meiaNoite(dia, fuso), fim: meiaNoite(diaSeguinte(dia), fuso) }
}

/** "2026-10-13" -> "13/10/2026", sem passar por Date e sem fuso no caminho. */
export function diaPorExtenso(dia: string): string {
  const [ano, mes, d] = dia.split("-")
  return `${d}/${mes}/${ano}`
}
