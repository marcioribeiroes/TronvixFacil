/**
 * O BR Code do Pix — o "copia e cola".
 *
 * Formato EMV® QRCPS, como o Banco Central especifica: campos no padrao
 * tamanho-valor, cada um com id de dois digitos e tamanho de dois digitos, e um
 * CRC16 no fim. O banco do cliente recusa o codigo inteiro se um byte estiver
 * errado — nao ha "quase certo" aqui.
 *
 * Isto e um Pix ESTATICO com valor: nenhuma conta de provedor, nenhuma taxa por
 * transacao, e o dinheiro cai direto na conta do restaurante. O que ele nao tem
 * e confirmacao automatica — quem confirma e o balcao, vendo o dinheiro entrar.
 */

/** Um campo do BR Code: id, tamanho em dois digitos, valor. */
function campo(id: string, valor: string): string {
  return id + String(valor.length).padStart(2, "0") + valor
}

/**
 * CRC16/CCITT-FALSE, como o padrao exige.
 *
 * Polinomio 0x1021, valor inicial 0xFFFF, sem reflexao, sem XOR final. Calculado
 * sobre o codigo inteiro JA com "6304" no fim — o proprio identificador do CRC
 * entra na conta, e esquecer isso e o erro classico.
 */
export function crc16(texto: string): string {
  let crc = 0xffff

  for (let i = 0; i < texto.length; i++) {
    crc ^= texto.charCodeAt(i) << 8
    for (let bit = 0; bit < 8; bit++) {
      crc = crc & 0x8000 ? ((crc << 1) ^ 0x1021) & 0xffff : (crc << 1) & 0xffff
    }
  }

  return crc.toString(16).toUpperCase().padStart(4, "0")
}

/**
 * Tira acento e o que o padrao nao aceita.
 *
 * Nome e cidade aparecem no aplicativo do banco na hora de confirmar. Acento
 * vira caractere estranho em parte dos bancos, e o padrao limita o tamanho:
 * 25 para o nome, 15 para a cidade.
 */
function limpar(texto: string, limite: number): string {
  return texto
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/[^A-Za-z0-9 .\-]/g, "")
    .trim()
    .slice(0, limite)
    .toUpperCase()
}

/** Chave Pix como o BR Code a quer: só dígitos em CPF, CNPJ e telefone. */
export function normalizarChave(
  chave: string,
  tipo: "cpf" | "cnpj" | "email" | "telefone" | "aleatoria",
): string {
  const limpa = chave.trim()
  switch (tipo) {
    case "cpf":
    case "cnpj":
      return limpa.replace(/\D/g, "")
    case "telefone": {
      // O padrão pede o formato internacional: +5562990000000.
      const d = limpa.replace(/\D/g, "")
      const semPais = d.length > 11 && d.startsWith("55") ? d.slice(2) : d
      return `+55${semPais}`
    }
    case "email":
      return limpa.toLowerCase()
    default:
      return limpa
  }
}

export type DadosDoPix = {
  chave: string
  tipo: "cpf" | "cnpj" | "email" | "telefone" | "aleatoria"
  nomeDoRecebedor: string
  cidade: string
  centavos: number
  /**
   * Identificador da transacao. Vai no campo 62-05 e volta no extrato do
   * recebedor, o que e o unico jeito de casar um Pix com o pedido certo quando
   * tres mesas pagam ao mesmo tempo.
   */
  identificador?: string
}

export function gerarBrCode(dados: DadosDoPix): string {
  const chave = normalizarChave(dados.chave, dados.tipo)

  const conta =
    campo("00", "br.gov.bcb.pix") + campo("01", chave)

  // O identificador aceita só letras e números; "***" é o valor que o padrão
  // define para "sem identificador".
  const txid =
    (dados.identificador ?? "").replace(/[^A-Za-z0-9]/g, "").slice(0, 25) || "***"

  const semCrc =
    campo("00", "01") +
    // 26 é a conta do recebedor; 52 é o ramo de atividade (0000 = não
    // informado), 53 a moeda (986 = real).
    campo("26", conta) +
    campo("52", "0000") +
    campo("53", "986") +
    campo("54", (dados.centavos / 100).toFixed(2)) +
    campo("58", "BR") +
    campo("59", limpar(dados.nomeDoRecebedor, 25)) +
    campo("60", limpar(dados.cidade, 15)) +
    campo("62", campo("05", txid)) +
    "6304"

  return semCrc + crc16(semCrc)
}
