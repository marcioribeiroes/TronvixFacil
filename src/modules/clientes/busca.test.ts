import { describe, expect, it } from "vitest"

import { clienteCombina } from "./busca"

const joao = { nome: "Seu João da Silva", telefone: "62999990000" }
const semFone = { nome: "Maria", telefone: null }

describe("clienteCombina", () => {
  it("acha pelo nome, sem acento e em qualquer ordem", () => {
    expect(clienteCombina(joao, "joao")).toBe(true)
    expect(clienteCombina(joao, "silva joao")).toBe(true)
    expect(clienteCombina(joao, "pedro")).toBe(false)
  })

  it("acha pelo telefone, com ou sem mascara", () => {
    expect(clienteCombina(joao, "99999")).toBe(true)
    expect(clienteCombina(joao, "(62) 9999")).toBe(true)
    expect(clienteCombina(semFone, "99999")).toBe(false)
  })

  it("campo vazio mostra todos", () => {
    expect(clienteCombina(semFone, "  ")).toBe(true)
  })
})
