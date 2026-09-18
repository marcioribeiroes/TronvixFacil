import { describe, expect, it } from "vitest"

import { formatarTelefone, paraDiscagem } from "./telefone"

describe("formatarTelefone", () => {
  it("põe a máscara do celular de nove dígitos", () => {
    expect(formatarTelefone("62990000006")).toBe("(62) 99000-0006")
  })

  it("põe a máscara do fixo de oito dígitos", () => {
    expect(formatarTelefone("6232000001")).toBe("(62) 3200-0001")
  })

  it("tira o 55 do número internacional", () => {
    expect(formatarTelefone("5562990000006")).toBe("(62) 99000-0006")
  })

  it("aceita o que já veio formatado", () => {
    expect(formatarTelefone("(62) 99000-0006")).toBe("(62) 99000-0006")
  })

  it("devolve o original quando não reconhece o formato", () => {
    expect(formatarTelefone("123")).toBe("123")
  })

  it("devolve vazio para nulo", () => {
    expect(formatarTelefone(null)).toBe("")
    expect(formatarTelefone(undefined)).toBe("")
    expect(formatarTelefone("")).toBe("")
  })

  it("deixa só dígitos para discar", () => {
    expect(paraDiscagem("(62) 99000-0006")).toBe("62990000006")
  })
})
