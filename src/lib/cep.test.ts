import { describe, expect, it } from "vitest"

import { cepCompleto, digitosDoCep, formatarCep, lerRespostaDoCep } from "./cep"

describe("CEP", () => {
  it("tira a formatação", () => {
    expect(digitosDoCep("74230-035")).toBe("74230035")
  })

  it("põe a máscara enquanto se digita", () => {
    expect(formatarCep("74230")).toBe("74230")
    expect(formatarCep("742300")).toBe("74230-0")
    expect(formatarCep("74230035")).toBe("74230-035")
    expect(formatarCep("742300351234")).toBe("74230-035")
  })

  it("só considera completo com oito dígitos", () => {
    expect(cepCompleto("7423003")).toBe(false)
    expect(cepCompleto("74230-035")).toBe(true)
  })

  it("lê um endereço completo", () => {
    expect(
      lerRespostaDoCep({
        logradouro: "Avenida T-4",
        bairro: "Setor Bueno",
        localidade: "Goiânia",
        uf: "GO",
      }),
    ).toEqual({ rua: "Avenida T-4", bairro: "Setor Bueno", cidade: "Goiânia", estado: "GO" })
  })

  it("aceita CEP de cidade inteira, sem rua nem bairro", () => {
    expect(lerRespostaDoCep({ localidade: "Britânia", uf: "GO" })).toEqual({
      rua: "",
      bairro: "",
      cidade: "Britânia",
      estado: "GO",
    })
  })

  it("trata o erro do ViaCEP, que vem com HTTP 200", () => {
    expect(lerRespostaDoCep({ erro: true })).toBeNull()
    expect(lerRespostaDoCep({ erro: "true" })).toBeNull()
  })

  it("devolve nulo quando falta cidade ou estado", () => {
    expect(lerRespostaDoCep({ logradouro: "Rua X" })).toBeNull()
    expect(lerRespostaDoCep(null)).toBeNull()
  })
})
