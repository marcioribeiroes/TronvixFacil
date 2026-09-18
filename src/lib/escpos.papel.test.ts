import { describe, expect, it } from "vitest"

import { Comanda, DE_CP850 } from "./escpos"

/**
 * A comanda como a impressora a recebe.
 *
 * Este teste não tem muitas asserções de propósito: ele existe para que dê
 * para VER a fita, byte a byte, com os comandos à mostra. Sem impressora na
 * mesa, é o mais perto que se chega do papel — e foi assim que se conferiu que
 * o corte avança o papel e que o acento vira um byte só.
 */
function legivel(fita: Uint8Array): string {
  const nomes: Record<number, string> = { 0x1b: "ESC", 0x1d: "GS" }
  let saida = ""
  let i = 0

  while (i < fita.length) {
    const b = fita[i]
    if (b === 0x1b || b === 0x1d) {
      const letra = String.fromCharCode(fita[i + 1])
      saida += `\n[${nomes[b]} ${letra} ${fita[i + 2]}]`
      i += b === 0x1d && letra === "V" ? 4 : 3
      continue
    }
    // CP850 de volta, e não latin1: em latin1 o "ã" (198) aparece como "Æ" e
    // faria parecer defeito onde o byte está certo.
    saida += b === 10 ? "\n" : (DE_CP850[b] ?? String.fromCharCode(b))
    i++
  }
  return saida
}

describe("a comanda no papel", () => {
  it("sai na ordem e com a largura certas", () => {
    const c = new Comanda(48)
    c.alinhar("centro")
    c.negrito(true).linha("BURGER HOUSE").negrito(false)
    c.tamanho(2).linha("No 12").tamanho(1)
    c.negrito(true).linha("ENTREGA").negrito(false)
    c.alinhar("esquerda").separador()
    c.negrito(true).linha("João Silva").negrito(false)
    c.linha("Rua das Palmeiras, 120 - Setor Bueno - Goiânia")
    c.separador()
    c.entre("2x X-Tudo", "R$ 59,80")
    c.linha("   + Bacon")
    c.negrito(true).linha("   ** SEM CEBOLA").negrito(false)
    c.separador()
    c.entre("Subtotal", "R$ 59,80")
    c.entre("Entrega", "R$ 5,00")
    c.negrito(true).entre("TOTAL", "R$ 64,80").negrito(false)
    c.separador()
    c.negrito(true).linha("RECEBER NA ENTREGA").negrito(false)
    c.linha("TROCO PARA R$ 100,00 = R$ 35,20")
    c.cortar()

    const papel = legivel(c.bytes())

    // O que se confere de verdade, e que uma foto não provaria:
    for (const linha of papel.split("\n")) {
      const semComando = linha.replace(/\[(ESC|GS) . \d+\]/g, "")
      expect(semComando.length).toBeLessThanOrEqual(48)
    }

    expect(papel).toContain("[GS ! 17]") // número do pedido dobrado
    expect(papel).toContain("[ESC d 6]") // avança antes de cortar
    expect(papel).toContain("[GS V 66]") // corte parcial
    expect(papel).toContain("Goiânia".normalize()) // acento sobreviveu

    // "TOTAL" e o valor encostados nas duas margens.
    const total = papel.split("\n").find((l) => l.includes("TOTAL"))!
    expect(total.replace(/\[(ESC|GS) . \d+\]/g, "").length).toBe(48)

    // Imprime a fita quando se roda com --reporter=verbose: é o retrato do
    // papel, e é para isso que este teste serve.
    if (process.env.VER_COMANDA) console.log(papel)
  })
})
