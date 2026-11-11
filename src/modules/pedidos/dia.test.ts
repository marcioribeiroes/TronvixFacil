import { describe, expect, it } from "vitest"

import { diaDeHoje, diaPorExtenso, diaValido, limitesDoDia } from "./dia"

describe("diaValido", () => {
  it("aceita AAAA-MM-DD que existe", () => {
    expect(diaValido("2026-11-10")).toBe(true)
    expect(diaValido("2028-02-29")).toBe(true)
  })

  it("recusa formato errado, dia que nao existe e o que nao e texto", () => {
    expect(diaValido("2026-02-31")).toBe(false)
    expect(diaValido("10/11/2026")).toBe(false)
    expect(diaValido("2026-11-10T00:00")).toBe(false)
    expect(diaValido(undefined)).toBe(false)
    expect(diaValido(["2026-11-10"])).toBe(false)
  })
})

describe("diaDeHoje", () => {
  it("usa o fuso da loja, nao o do servidor", () => {
    // 23h30 de 10/11 em Sao Paulo ja e 11/11 em UTC.
    const agora = new Date("2026-11-11T02:30:00Z")
    expect(diaDeHoje("America/Sao_Paulo", agora)).toBe("2026-11-10")
    expect(diaDeHoje("UTC", agora)).toBe("2026-11-11")
  })
})

describe("limitesDoDia", () => {
  it("vai da meia-noite local ate a meia-noite seguinte", () => {
    expect(limitesDoDia("2026-11-10", "America/Sao_Paulo")).toEqual({
      inicio: "2026-11-10T03:00:00.000Z",
      fim: "2026-11-11T03:00:00.000Z",
    })
  })

  it("atravessa o fim do mes e o fuso UTC", () => {
    expect(limitesDoDia("2026-12-31", "UTC")).toEqual({
      inicio: "2026-12-31T00:00:00.000Z",
      fim: "2027-01-01T00:00:00.000Z",
    })
  })
})

describe("diaPorExtenso", () => {
  it("escreve como o balcao le", () => {
    expect(diaPorExtenso("2026-11-10")).toBe("10/11/2026")
  })
})
