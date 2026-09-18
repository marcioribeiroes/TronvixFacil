import { describe, expect, it } from "vitest"

import { Comanda, paraCp850 } from "./escpos"

/** Os bytes de uma comanda recém-criada: ESC @ e ESC t 2. */
const CABECALHO = [0x1b, 0x40, 0x1b, 0x74, 2]

describe("CP850", () => {
  it("passa o ASCII direto", () => {
    expect([...paraCp850("ABC 123")]).toEqual([65, 66, 67, 32, 49, 50, 51])
  })

  it("traduz o acento que a impressora conhece", () => {
    // "ç" é 135 na CP850, e "ã" é 198. Em UTF-8 seriam dois bytes cada, e a
    // impressora cuspiria dois símbolos errados.
    expect([...paraCp850("ç")]).toEqual([135])
    expect([...paraCp850("ã")]).toEqual([198])
    expect([...paraCp850("Goiânia")].length).toBe(7)
  })

  it("tira o acento do que não está no mapa, em vez de imprimir lixo", () => {
    // Um caractere fora da página de código vira a letra sem acento; byte solto
    // pode ser lido como comando pela impressora.
    const bytes = [...paraCp850("Ẽ")]
    expect(bytes.length).toBe(1)
    expect(bytes[0]).toBe(0x3f) // "?"
  })

  it("não deixa passar byte acima de 255", () => {
    for (const b of paraCp850("çãõáéíóúÇÃÕ€🍔")) {
      expect(b).toBeGreaterThanOrEqual(0)
      expect(b).toBeLessThanOrEqual(255)
    }
  })
})

describe("Comanda", () => {
  it("começa zerando a impressora e escolhendo a página de código", () => {
    // Sem o ESC @, ela herda negrito ou tamanho dobrado de um trabalho anterior
    // que terminou mal — e a comanda inteira sai gigante.
    expect([...new Comanda().bytes()]).toEqual(CABECALHO)
  })

  it("alinha ao centro e volta", () => {
    const c = new Comanda().alinhar("centro").texto("X").alinhar("esquerda")
    expect([...c.bytes()]).toEqual([...CABECALHO, 0x1b, 0x61, 1, 88, 0x1b, 0x61, 0])
  })

  it("dobra o tamanho nos dois eixos", () => {
    // GS ! 0x11: largura dobrada no meio byte alto, altura no baixo.
    const c = new Comanda().tamanho(2)
    expect([...c.bytes()].slice(-3)).toEqual([0x1d, 0x21, 0x11])
  })

  it("encosta o valor na margem direita", () => {
    const c = new Comanda(20)
    c.entre("TOTAL", "R$ 64,80")
    const texto = new TextDecoder("latin1").decode(c.bytes()).slice(CABECALHO.length)
    expect(texto).toBe("TOTAL       R$ 64,80\n")
    expect(texto.trimEnd().length).toBe(20)
  })

  it("não quebra quando os dois lados não cabem", () => {
    const c = new Comanda(10)
    c.entre("UM ROTULO MUITO LONGO", "R$ 1,00")
    const texto = new TextDecoder("latin1").decode(c.bytes()).slice(CABECALHO.length)
    expect(texto).toBe("UM ROTULO MUITO LONGO R$ 1,00\n")
  })

  it("o separador tem a largura do papel", () => {
    expect(
      new TextDecoder("latin1")
        .decode(new Comanda(32).separador().bytes())
        .slice(CABECALHO.length)
        .trimEnd().length,
    ).toBe(32)
  })

  it("avança o papel antes de cortar", () => {
    // A lâmina fica acima da cabeça de impressão: sem o avanço, o corte come as
    // últimas linhas da comanda.
    const bytes = [...new Comanda().cortar().bytes()].slice(CABECALHO.length)
    expect(bytes).toEqual([0x1b, 0x64, 6, 0x1d, 0x56, 66, 0])
  })

  it("monta a fita inteira na ordem em que foi escrita", () => {
    const c = new Comanda(20)
    c.alinhar("centro").negrito(true).linha("OI").negrito(false)
    const texto = new TextDecoder("latin1").decode(c.bytes())
    expect(texto).toContain("OI\n")
    expect(texto.indexOf("OI")).toBeGreaterThan(0)
  })
})
