/**
 * Endereco a partir do CEP.
 *
 * Usa o ViaCEP, que e publico e nao pede chave. A busca roda no NAVEGADOR, de
 * proposito: e o unico lugar onde o custo de uma consulta a mais e zero, e o
 * servidor nao vira intermediario de um dado que ja e publico.
 *
 * Quem chama trata o nulo como "nao achei" e deixa a pessoa digitar - CEP novo,
 * CEP de zona rural e CEP unico de empresa nao estao todos na base, e recusar o
 * cadastro por isso seria pior do que nao ter a busca.
 */

export type EnderecoDoCep = {
  rua: string
  bairro: string
  cidade: string
  estado: string
}

/** Deixa so os digitos: "74230-035" -> "74230035". */
export function digitosDoCep(bruto: string): string {
  return bruto.replace(/\D/g, "")
}

/** CEP brasileiro tem oito digitos. Nem todos existem, mas todos tem oito. */
export function cepCompleto(bruto: string): boolean {
  return digitosDoCep(bruto).length === 8
}

/** Mascara de exibicao: "74230035" -> "74230-035". */
export function formatarCep(bruto: string): string {
  const d = digitosDoCep(bruto).slice(0, 8)
  return d.length > 5 ? `${d.slice(0, 5)}-${d.slice(5)}` : d
}

/**
 * O formato que o ViaCEP devolve. `erro` vem quando o CEP nao existe - e vem
 * com HTTP 200, entao conferir o status nao basta.
 */
type RespostaDoViaCep = {
  logradouro?: string
  bairro?: string
  localidade?: string
  uf?: string
  erro?: boolean | string
}

/** Traduz a resposta crua. Separado da rede para poder ser testado. */
export function lerRespostaDoCep(dados: RespostaDoViaCep | null): EnderecoDoCep | null {
  if (!dados) return null
  // O campo `erro` ja veio como boolean e como a string "true"; aceitar os dois
  // e mais barato do que descobrir qual e na hora errada.
  if (dados.erro === true || dados.erro === "true") return null
  if (!dados.localidade || !dados.uf) return null

  return {
    // Logradouro e bairro vem vazios em CEP de cidade inteira (os terminados
    // em -000 de municipio pequeno). Cidade e estado, esses sempre vem.
    rua: dados.logradouro ?? "",
    bairro: dados.bairro ?? "",
    cidade: dados.localidade,
    estado: dados.uf,
  }
}

export async function buscarCep(bruto: string): Promise<EnderecoDoCep | null> {
  const cep = digitosDoCep(bruto)
  if (cep.length !== 8) return null

  try {
    const resposta = await fetch(`https://viacep.com.br/ws/${cep}/json/`)
    if (!resposta.ok) return null
    return lerRespostaDoCep(await resposta.json())
  } catch {
    // Sem rede, a pessoa digita. Um cadastro nao pode depender de um serviço
    // de terceiro estar no ar.
    return null
  }
}
