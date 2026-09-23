/**
 * A coordenada da loja, a partir do CEP.
 *
 * `restaurants.latitude` e `longitude` existem desde a fundacao e nenhuma tela
 * jamais as escreveu: so a semente de demonstracao. Uma loja que se cadastrava
 * de verdade nascia sem coordenada — e sem ela a corrida nao tem distancia, o
 * mapa de coleta do entregador fica vazio e o raio de entrega nao tem centro.
 *
 * Usa a BrasilAPI v2, que devolve `location.coordinates` junto com o endereco.
 * E a mesma fonte que o aplicativo ja consulta para preencher endereco de
 * cliente, entao nao entra servico novo no projeto.
 *
 * **E o centro do CEP, nao a porta da loja.** Numa rua longa ou num CEP de
 * municipio inteiro, erra por quarteiroes. Serve para medir distancia de
 * corrida e desenhar o mapa; nao serve para o entregador achar a porta — para
 * isso ele tem o endereco escrito, que continua sendo o que vale.
 *
 * Nada aqui estoura. CEP invalido, servico fora, rede caida: devolve nulo, e
 * quem chamou segue sem coordenada, exatamente como era antes.
 */

export type Coordenadas = { latitude: number; longitude: number }

/**
 * Le a resposta da BrasilAPI v2.
 *
 * Separada da chamada de rede de proposito: e aqui que mora o que pode dar
 * errado — a API devolve os numeros como TEXTO, e ha CEP que volta sem
 * `location` nenhum. O teste cobre esta funcao sem tocar na internet.
 */
export function coordenadasDaResposta(corpo: unknown): Coordenadas | null {
  if (typeof corpo !== "object" || corpo === null) return null

  const local = (corpo as { location?: unknown }).location
  if (typeof local !== "object" || local === null) return null

  const par = (local as { coordinates?: unknown }).coordinates
  if (typeof par !== "object" || par === null) return null

  const { latitude, longitude } = par as { latitude?: unknown; longitude?: unknown }

  const lat = Number(latitude)
  const lon = Number(longitude)

  // Number("") e Number(null) dao 0, e zero e uma coordenada valida no meio do
  // Atlantico. Sem esta checagem, CEP sem coordenada viraria uma loja no mar.
  if (
    latitude === undefined ||
    longitude === undefined ||
    latitude === null ||
    longitude === null ||
    latitude === "" ||
    longitude === "" ||
    !Number.isFinite(lat) ||
    !Number.isFinite(lon)
  ) {
    return null
  }

  if (lat < -90 || lat > 90 || lon < -180 || lon > 180) return null

  return { latitude: lat, longitude: lon }
}

export async function coordenadasDoCep(cep: string): Promise<Coordenadas | null> {
  const digitos = cep.replace(/\D/g, "")
  if (digitos.length !== 8) return null

  try {
    // O tempo limite importa: isto roda no meio do cadastro da loja, e o
    // cadastro nao pode ficar pendurado esperando um servico externo.
    const resposta = await fetch(`https://brasilapi.com.br/api/cep/v2/${digitos}`, {
      signal: AbortSignal.timeout(5000),
    })
    if (!resposta.ok) return null
    return coordenadasDaResposta(await resposta.json())
  } catch {
    // Rede, tempo limite, JSON quebrado: nada disso pode impedir alguem de
    // abrir a loja. Fica sem coordenada, e se resolve depois.
    return null
  }
}
