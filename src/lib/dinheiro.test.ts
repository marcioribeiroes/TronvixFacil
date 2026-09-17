import { describe, expect, it } from "vitest"

import {
  aplicarPontosBase,
  formatarReais,
  formatarValor,
  naoNegativo,
  paraCentavos,
  percentualParaPontosBase,
  pontosBaseParaPercentual,
  somar,
} from "./dinheiro"

describe("dinheiro", () => {
  it("formata centavos como moeda brasileira", () => {
    expect(formatarReais(2790)).toBe("R$ 27,90")
    expect(formatarReais(0)).toBe("R$ 0,00")
    expect(formatarReais(123456)).toBe("R$ 1.234,56")
  })

  it("formata valor sem simbolo para campos e tabelas", () => {
    expect(formatarValor(2790)).toBe("27,90")
    expect(formatarValor(5)).toBe("0,05")
  })

  it("entende as formas que o usuario realmente digita", () => {
    expect(paraCentavos("27,90")).toBe(2790)
    expect(paraCentavos("R$ 27,90")).toBe(2790)
    expect(paraCentavos("27.90")).toBe(2790)
    expect(paraCentavos("1.234,56")).toBe(123456)
    expect(paraCentavos("  10  ")).toBe(1000)
    expect(paraCentavos(27.9)).toBe(2790)
  })

  it("devolve null quando nao da para entender o que foi digitado", () => {
    expect(paraCentavos("")).toBeNull()
    expect(paraCentavos("abc")).toBeNull()
    expect(paraCentavos(null)).toBeNull()
    expect(paraCentavos(undefined)).toBeNull()
    expect(paraCentavos(Number.NaN)).toBeNull()
  })

  it("nao arrasta imprecisao de ponto flutuante", () => {
    // O caso classico: 0.1 + 0.2 em decimal nao fecha. Em centavos, fecha.
    expect(somar(paraCentavos("0,10")!, paraCentavos("0,20")!)).toBe(30)
    expect(formatarReais(somar(10, 20))).toBe("R$ 0,30")
  })

  it("calcula comissao em pontos base", () => {
    // 12% de R$ 32,90 = R$ 3,948 -> R$ 3,95
    expect(aplicarPontosBase(3290, 1200)).toBe(395)
    expect(aplicarPontosBase(10000, 1000)).toBe(1000)
    expect(aplicarPontosBase(0, 1500)).toBe(0)
  })

  it("converte percentual legivel e pontos base nos dois sentidos", () => {
    expect(percentualParaPontosBase(15)).toBe(1500)
    expect(percentualParaPontosBase(12.5)).toBe(1250)
    expect(pontosBaseParaPercentual(1500)).toBe(15)
    expect(pontosBaseParaPercentual(1250)).toBe(12.5)
  })

  it("ignora valores quebrados na soma em vez de propagar NaN", () => {
    // Um item mal formado nao pode transformar o total do carrinho em NaN na
    // tela do cliente.
    expect(somar(1000, Number.NaN, 500)).toBe(1500)
  })

  it("nao deixa valor monetario ficar negativo", () => {
    expect(naoNegativo(-500)).toBe(0)
    expect(naoNegativo(500)).toBe(500)
  })
})
