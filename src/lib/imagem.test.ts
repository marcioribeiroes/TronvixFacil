import { describe, expect, it } from "vitest"

import { ehImagemAceita, MEDIDA_DA_LOGO, MEDIDA_DO_PRODUTO } from "./imagem"

/** File não existe no ambiente de teste do Node sem DOM; um objeto basta. */
function arquivo(tipo: string): File {
  return { type: tipo, name: "foto", size: 1 } as File
}

describe("imagem", () => {
  it("aceita os formatos que o balde aceita", () => {
    for (const t of ["image/jpeg", "image/png", "image/webp", "image/avif"]) {
      expect(ehImagemAceita(arquivo(t))).toBe(true)
    }
  })

  it("recusa o que não é imagem", () => {
    // O PDF do cardápio inteiro e o vídeo mandado por engano: os dois casos
    // reais de quem clica em "escolher arquivo" com pressa.
    expect(ehImagemAceita(arquivo("application/pdf"))).toBe(false)
    expect(ehImagemAceita(arquivo("video/mp4"))).toBe(false)
    expect(ehImagemAceita(arquivo("image/heic"))).toBe(false)
  })

  it("a logo é menor que a foto do produto", () => {
    // A logo aparece num quadradinho de lista; o produto ocupa a largura da
    // tela. Guardar as duas no mesmo tamanho é pagar banda à toa.
    expect(MEDIDA_DA_LOGO.maiorLado).toBeLessThan(MEDIDA_DO_PRODUTO.maiorLado)
  })
})
