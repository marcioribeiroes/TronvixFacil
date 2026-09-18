/**
 * A impressora térmica ligada nesta máquina.
 *
 * Fala ESC/POS direto pela porta serial (Web Serial), sem o driver do sistema
 * e sem janela de impressão. É o que um balcão em movimento precisa: o pedido
 * entra e o papel sai.
 *
 * O que funciona por aqui: impressora USB que aparece como porta COM — Elgin,
 * Bematech e boa parte das Epson instalam assim no Windows. O que NÃO funciona:
 * impressora de rede (o navegador não abre porta TCP crua) e impressora que só
 * existe como fila do sistema. Para essas fica o caminho do driver, que
 * continua no botão do lado.
 *
 * Web Serial existe no Chrome e no Edge, em computador. Não existe no Firefox,
 * no Safari nem em celular — e o balcão é um computador.
 */

export type Porta = {
  readable: ReadableStream | null
  writable: WritableStream | null
  open(opcoes: { baudRate: number }): Promise<void>
  close(): Promise<void>
  getInfo(): { usbVendorId?: number; usbProductId?: number }
}

type Serial = {
  requestPort(): Promise<Porta>
  getPorts(): Promise<Porta[]>
}

function serial(): Serial | null {
  const nav = navigator as unknown as { serial?: Serial }
  return nav.serial ?? null
}

export function temImpressoraDireta(): boolean {
  return serial() !== null
}

let portaAberta: Porta | null = null

/**
 * Pede a porta à pessoa. Só funciona dentro de um clique — é exigência do
 * navegador, e existe para que nenhuma página escolha sozinha um aparelho.
 */
export async function escolherImpressora(): Promise<boolean> {
  const s = serial()
  if (!s) return false

  try {
    const porta = await s.requestPort()
    // 9600 é o que quase toda térmica usa de fábrica. As que vêm em 115200
    // costumam aceitar 9600 também; quando não aceitam, sai texto embaralhado
    // e a pessoa troca na própria impressora.
    await porta.open({ baudRate: 9600 })
    portaAberta = porta
    return true
  } catch {
    // Cancelou a janela, ou a porta está ocupada por outro programa.
    return false
  }
}

/** Reaproveita a porta já autorizada, sem perguntar de novo. */
export async function reconectarImpressora(): Promise<boolean> {
  const s = serial()
  if (!s) return false

  try {
    const [porta] = await s.getPorts()
    if (!porta) return false
    await porta.open({ baudRate: 9600 })
    portaAberta = porta
    return true
  } catch {
    return false
  }
}

export function impressoraLigada(): boolean {
  return portaAberta?.writable != null
}

export async function desligarImpressora() {
  try {
    await portaAberta?.close()
  } catch {
    // Já fechada, ou o cabo saiu. Nos dois casos o resultado é o mesmo.
  }
  portaAberta = null
}

/**
 * Manda a fita de bytes.
 *
 * Em pedaços de 1 KB: a fila da porta serial é pequena, e empurrar a comanda
 * inteira de uma vez faz parte das impressoras engasgarem no meio — sai a
 * primeira metade, um espaço em branco, e o resto.
 */
export async function enviarParaImpressora(fita: Uint8Array): Promise<boolean> {
  if (!portaAberta?.writable) return false

  const escritor = portaAberta.writable.getWriter()
  try {
    for (let i = 0; i < fita.length; i += 1024) {
      await escritor.write(fita.slice(i, i + 1024))
    }
    return true
  } catch {
    return false
  } finally {
    escritor.releaseLock()
  }
}
