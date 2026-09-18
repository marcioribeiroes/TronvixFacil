import { describe, expect, it } from "vitest"

import { crc16, gerarBrCode, normalizarChave } from "./pix"

describe("BR Code do Pix", () => {
  it("é o CRC16/CCITT-FALSE, conferido pela constante do próprio algoritmo", () => {
    // 0x29B1 é o valor de conferência publicado do CRC-16/CCITT-FALSE para a
    // entrada "123456789" — polinômio 0x1021, inicial 0xFFFF, sem reflexão,
    // sem XOR final. É o mesmo que o BR Code exige, e é verificável sem
    // depender de eu ter copiado certo um exemplo de documento.
    expect(crc16("123456789")).toBe("29B1")
  })

  it("monta um código com os campos na ordem certa", () => {
    const codigo = gerarBrCode({
      chave: "12345678901",
      tipo: "cpf",
      nomeDoRecebedor: "Burger House",
      cidade: "Goiânia",
      centavos: 6480,
    })

    expect(codigo.startsWith("000201")).toBe(true)
    expect(codigo).toContain("br.gov.bcb.pix")
    expect(codigo).toContain("12345678901")
    // O valor entra com duas casas, em reais.
    expect(codigo).toContain("540564.80")
    expect(codigo).toContain("5802BR")
    // Acento sai, e o texto sobe para maiúscula.
    expect(codigo).toContain("GOIANIA")
    expect(codigo).toContain("BURGER HOUSE")
  })

  it("fecha com um CRC que confere", () => {
    const codigo = gerarBrCode({
      chave: "loja@exemplo.com.br",
      tipo: "email",
      nomeDoRecebedor: "Loja",
      cidade: "Goiania",
      centavos: 1000,
    })

    // O CRC é calculado sobre tudo, inclusive o "6304" que o antecede. É o
    // erro clássico de quem implementa este formato pela primeira vez.
    const semCrc = codigo.slice(0, -4)
    expect(codigo.slice(-4)).toBe(crc16(semCrc))
  })

  it("normaliza cada tipo de chave como o padrão quer", () => {
    expect(normalizarChave("123.456.789-01", "cpf")).toBe("12345678901")
    expect(normalizarChave("12.345.678/0001-90", "cnpj")).toBe("12345678000190")
    expect(normalizarChave("(62) 99000-0000", "telefone")).toBe("+5562990000000")
    expect(normalizarChave("+5562990000000", "telefone")).toBe("+5562990000000")
    expect(normalizarChave("  LOJA@Exemplo.com ", "email")).toBe("loja@exemplo.com")
    expect(normalizarChave(" abc-123 ", "aleatoria")).toBe("abc-123")
  })

  it("aceita valor com centavos quebrados", () => {
    const codigo = gerarBrCode({
      chave: "x",
      tipo: "aleatoria",
      nomeDoRecebedor: "L",
      cidade: "C",
      centavos: 1,
    })
    expect(codigo).toContain("54040.01")
  })

  it("usa *** quando não há identificador, como o padrão define", () => {
    const codigo = gerarBrCode({
      chave: "x",
      tipo: "aleatoria",
      nomeDoRecebedor: "L",
      cidade: "C",
      centavos: 100,
    })
    expect(codigo).toContain("62070503***")
  })

  it("leva o número do pedido no identificador, para casar no extrato", () => {
    const codigo = gerarBrCode({
      chave: "x",
      tipo: "aleatoria",
      nomeDoRecebedor: "L",
      cidade: "C",
      centavos: 100,
      identificador: "PEDIDO-42",
    })
    expect(codigo).toContain("PEDIDO42")
  })
})
