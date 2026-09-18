/**
 * A comanda em ESC/POS, os bytes que a impressora térmica entende.
 *
 * ESC/POS é da Epson e virou o padrão de fato: Elgin, Bematech, Daruma e os
 * clones chineses aceitam o mesmo conjunto básico — inicializar, alinhar,
 * dobrar o tamanho, negrito, cortar. É esse conjunto básico que está aqui, e
 * só ele. Comando exótico de um fabricante funciona numa impressora e trava
 * outra.
 *
 * Por que isto existe, se a impressão pelo driver já funciona: pelo driver o
 * navegador sempre abre a janela de impressão. Por aqui a comanda sai sem
 * ninguém tocar em nada — que é o que um balcão em movimento precisa.
 */

const ESC = 0x1b
const GS = 0x1d

/**
 * CP850, a página de código que as térmicas brasileiras trazem de fábrica.
 *
 * UTF-8 não serve: a impressora lê um byte por caractere. "Ã" em UTF-8 são dois
 * bytes e sairiam como dois símbolos errados. Só o que aparece em português
 * está no mapa; o resto vira a letra sem acento, que é melhor do que um
 * quadrado preto no meio do nome do cliente.
 */
const CP850: Record<string, number> = {
  "Ç": 128, "ü": 129, "é": 130, "â": 131, "ä": 132, "à": 133, "å": 134, "ç": 135,
  "ê": 136, "ë": 137, "è": 138, "ï": 139, "î": 140, "ì": 141, "Ä": 142, "Å": 143,
  "É": 144, "æ": 145, "Æ": 146, "ô": 147, "ö": 148, "ò": 149, "û": 150, "ù": 151,
  "ÿ": 152, "Ö": 153, "Ü": 154, "ø": 155, "£": 156, "Ø": 157, "×": 158, "ƒ": 159,
  "á": 160, "í": 161, "ó": 162, "ú": 163, "ñ": 164, "Ñ": 165, "ª": 166, "º": 167,
  "¿": 168, "®": 169, "Á": 181, "Â": 182, "À": 183, "©": 184, "ã": 198, "Ã": 199,
  "Ê": 210, "Ë": 211, "È": 212, "Í": 214, "Î": 215, "Ï": 216, "Ì": 222,
  "Ó": 224, "ß": 225, "Ô": 226, "Ò": 227, "õ": 228, "Õ": 229, "µ": 230,
  "Ú": 233, "Û": 234, "Ù": 235, "ý": 236, "Ý": 237, "¯": 238, "´": 239,
  "±": 241, "¾": 243, "¶": 244, "§": 245, "÷": 246, "°": 248, "¨": 249,
  "·": 250, "¹": 251, "³": 252, "²": 253,
}

/**
 * O caminho de volta: byte da CP850 para o caractere.
 *
 * Serve para conferir a fita sem impressora — decodificar em latin1 mostra "ã"
 * como "Æ" e faz parecer defeito onde o byte está certo.
 */
export const DE_CP850: Record<number, string> = Object.fromEntries(
  Object.entries(CP850).map(([letra, byte]) => [byte, letra]),
)

/** Sem acento, para o que não estiver no mapa. */
const SEM_ACENTO = "AAAAAAaaaaaaEEEEeeeeIIIIiiiiOOOOOooooUUUUuuuuCcNn"
const COM_ACENTO = "ÁÀÂÃÄÅáàâãäåÉÈÊËéèêëÍÌÎÏíìîïÓÒÔÕÖóòôõöÚÙÛÜúùûüÇçÑñ"

export function paraCp850(texto: string): Uint8Array {
  const bytes: number[] = []

  for (const c of texto) {
    const codigo = c.codePointAt(0)!
    if (codigo < 128) {
      bytes.push(codigo)
      continue
    }
    if (CP850[c] !== undefined) {
      bytes.push(CP850[c])
      continue
    }
    const i = COM_ACENTO.indexOf(c)
    // Fora do mapa e sem equivalente: interrogação, e não um byte qualquer —
    // byte solto pode ser interpretado como comando pela impressora.
    bytes.push(i >= 0 ? SEM_ACENTO.charCodeAt(i) : 0x3f)
  }

  return Uint8Array.from(bytes)
}

/** Monta a fita de bytes de uma comanda. */
export class Comanda {
  private readonly partes: Uint8Array[] = []

  /** Largura em caracteres: 48 no papel de 80mm, 32 no de 58mm. */
  constructor(private readonly colunas = 48) {
    // ESC @ — zera a impressora. Sem isto, ela herda negrito ou tamanho dobrado
    // de um trabalho anterior que terminou mal.
    this.cru(ESC, 0x40)
    // ESC t 2 — seleciona a CP850.
    this.cru(ESC, 0x74, 2)
  }

  private cru(...bytes: number[]) {
    this.partes.push(Uint8Array.from(bytes))
    return this
  }

  texto(t: string) {
    this.partes.push(paraCp850(t))
    return this
  }

  linha(t = "") {
    return this.texto(`${t}\n`)
  }

  /** ESC a — 0 esquerda, 1 centro, 2 direita. */
  alinhar(onde: "esquerda" | "centro" | "direita") {
    const n = onde === "centro" ? 1 : onde === "direita" ? 2 : 0
    return this.cru(ESC, 0x61, n)
  }

  /** ESC E — negrito. */
  negrito(ligado: boolean) {
    return this.cru(ESC, 0x45, ligado ? 1 : 0)
  }

  /**
   * GS ! — tamanho. O byte junta largura e altura em meio byte cada, então
   * 0x11 é "o dobro nos dois". É assim que o número do pedido fica legível a um
   * metro de distância, que é de onde o balcão olha.
   */
  tamanho(multiplo: 1 | 2 | 3) {
    const n = (multiplo - 1) * 0x10 + (multiplo - 1)
    return this.cru(GS, 0x21, n)
  }

  /** Uma linha de tracinhos, da largura do papel. */
  separador() {
    return this.linha("-".repeat(this.colunas))
  }

  /**
   * Rótulo à esquerda e valor à direita, na mesma linha.
   *
   * Sem isto, alinhar valores exigiria contar espaços à mão em cada chamada —
   * e um total desalinhado num papel de conferência é o tipo de coisa que faz
   * o dono desconfiar da conta.
   */
  entre(esquerda: string, direita: string) {
    const espaco = this.colunas - esquerda.length - direita.length
    return this.linha(
      espaco > 0 ? esquerda + " ".repeat(espaco) + direita : `${esquerda} ${direita}`,
    )
  }

  /**
   * Corta o papel.
   *
   * Avança seis linhas antes: a lâmina fica alguns milímetros acima da cabeça
   * de impressão, e sem o avanço o corte come as últimas linhas.
   */
  cortar() {
    this.cru(0x1b, 0x64, 6) // ESC d 6 — avança 6 linhas
    // GS V 66 0 — corte parcial, que é o que quase toda térmica faz. Corte
    // total existe em menos modelos e trava nos que não têm.
    return this.cru(GS, 0x56, 66, 0)
  }

  /** Abre a gaveta de dinheiro, quando houver uma ligada na impressora. */
  abrirGaveta() {
    return this.cru(ESC, 0x70, 0, 25, 250)
  }

  bytes(): Uint8Array {
    const total = this.partes.reduce((s, p) => s + p.length, 0)
    const fita = new Uint8Array(total)
    let i = 0
    for (const p of this.partes) {
      fita.set(p, i)
      i += p.length
    }
    return fita
  }
}
