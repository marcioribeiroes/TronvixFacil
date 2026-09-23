import { describe, expect, it } from "vitest"

import { coordenadasDaResposta } from "./geocodificar"

/**
 * A resposta real da BrasilAPI v2 para 29016260 (Vitoria-ES), reduzida ao que
 * esta funcao le. Os numeros vem como TEXTO — e o detalhe que quebra quem
 * assume `number`.
 */
const RESPOSTA_REAL = {
  cep: "29016260",
  state: "ES",
  city: "Vitória",
  location: {
    type: "Point",
    coordinates: { longitude: "-40.33778", latitude: "-20.31944" },
  },
}

describe("coordenadas a partir do CEP", () => {
  it("le a resposta da BrasilAPI, com os numeros em texto", () => {
    expect(coordenadasDaResposta(RESPOSTA_REAL)).toEqual({
      latitude: -20.31944,
      longitude: -40.33778,
    })
  })

  it("devolve nulo quando o CEP volta sem localizacao", () => {
    // Acontece de verdade: CEP de municipio inteiro costuma vir sem o ponto.
    expect(coordenadasDaResposta({ cep: "29016260", state: "ES" })).toBeNull()
    expect(coordenadasDaResposta({ location: {} })).toBeNull()
    expect(coordenadasDaResposta({ location: { coordinates: {} } })).toBeNull()
  })

  it("nao transforma vazio em loja no meio do Atlantico", () => {
    // Number("") e Number(null) dao 0, e (0, 0) e um ponto valido no golfo da
    // Guine. Sem cuidado, o CEP sem coordenada viraria uma loja no mar.
    expect(
      coordenadasDaResposta({ location: { coordinates: { latitude: "", longitude: "" } } }),
    ).toBeNull()
    expect(
      coordenadasDaResposta({ location: { coordinates: { latitude: null, longitude: null } } }),
    ).toBeNull()
  })

  it("recusa numero que nao e coordenada", () => {
    expect(
      coordenadasDaResposta({ location: { coordinates: { latitude: "abc", longitude: "-40" } } }),
    ).toBeNull()
    expect(
      coordenadasDaResposta({ location: { coordinates: { latitude: "91", longitude: "-40" } } }),
    ).toBeNull()
    expect(
      coordenadasDaResposta({ location: { coordinates: { latitude: "-20", longitude: "181" } } }),
    ).toBeNull()
  })

  it("aguenta lixo sem estourar", () => {
    for (const entrada of [null, undefined, "", 0, [], "texto solto"]) {
      expect(coordenadasDaResposta(entrada)).toBeNull()
    }
  })
})
