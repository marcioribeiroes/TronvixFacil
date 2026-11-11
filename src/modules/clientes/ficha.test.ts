import { describe, expect, it } from "vitest"

import { enderecoEmUmaLinha, schemaDaFicha } from "./ficha"

const vazia = {
  nome: "",
  telefone: "",
  rua: "",
  numero: "",
  complemento: "",
  bairro: "",
  cidade: "",
  observacao: "",
}

describe("schemaDaFicha", () => {
  it("guarda o telefone so com digitos e o vazio como nada", () => {
    const r = schemaDaFicha.parse({
      ...vazia,
      nome: "  Seu João  ",
      telefone: "(62) 99999-0000",
      bairro: "Centro",
    })
    expect(r.nome).toBe("Seu João")
    expect(r.telefone).toBe("62999990000")
    expect(r.bairro).toBe("Centro")
    expect(r.rua).toBeNull()
    expect(r.observacao).toBeNull()
  })

  it("aceita cliente sem telefone", () => {
    expect(schemaDaFicha.parse({ ...vazia, nome: "Maria" }).telefone).toBeNull()
  })

  it("recusa sem nome e telefone sem DDD", () => {
    expect(schemaDaFicha.safeParse({ ...vazia, nome: "   " }).success).toBe(false)
    expect(schemaDaFicha.safeParse({ ...vazia, nome: "Maria", telefone: "99999-0000" }).success).toBe(
      false,
    )
  })
})

describe("enderecoEmUmaLinha", () => {
  it("junta so o que foi preenchido", () => {
    expect(
      enderecoEmUmaLinha({ rua: "Rua das Flores", numero: "30", complemento: null, bairro: "Centro" }),
    ).toBe("Rua das Flores, 30 · Centro")
    expect(enderecoEmUmaLinha({ rua: null, numero: null, complemento: null, bairro: null })).toBe("")
  })
})
