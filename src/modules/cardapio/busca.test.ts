import { describe, expect, it } from "vitest"

import { normalizar, produtoCombina, produtoDoCodigo } from "./busca"

const file = { name: "Filé à parmegiana", description: "Com arroz e fritas", barcode: null }
const coca = { name: "Coca-Cola lata", description: null, barcode: "7894900011517" }

describe("normalizar", () => {
  it("tira acento, maiuscula e espaco", () => {
    expect(normalizar("  Filé À ")).toBe("file a")
  })
})

describe("produtoCombina", () => {
  it("acha pelo nome, sem acento e em qualquer ordem", () => {
    expect(produtoCombina(file, "file")).toBe(true)
    expect(produtoCombina(file, "parmegiana file")).toBe(true)
    expect(produtoCombina(file, "frango")).toBe(false)
  })

  it("acha pela descricao", () => {
    expect(produtoCombina(file, "fritas")).toBe(true)
  })

  it("acha pelo codigo de barras, inteiro ou pedaco", () => {
    expect(produtoCombina(coca, "7894900011517")).toBe(true)
    expect(produtoCombina(coca, "11517")).toBe(true)
    expect(produtoCombina(file, "11517")).toBe(false)
  })

  it("campo vazio mostra tudo", () => {
    expect(produtoCombina(file, "   ")).toBe(true)
  })
})

describe("produtoDoCodigo", () => {
  it("abre o unico produto com o codigo exato", () => {
    expect(produtoDoCodigo([file, coca], "7894900011517")).toBe(coca)
  })

  it("nao abre nada com codigo repetido, pedaco ou texto", () => {
    expect(produtoDoCodigo([coca, { ...coca, name: "Outra" }], "7894900011517")).toBeNull()
    expect(produtoDoCodigo([coca], "11517")).toBeNull()
    expect(produtoDoCodigo([coca], "coca")).toBeNull()
  })
})
