/**
 * Reduzir a foto antes de enviar.
 *
 * Foto de celular moderno tem 4000 pixels de largura e 8 MB. O balde recusa
 * acima de 5 MB, e mesmo que aceitasse seria um desperdicio: a maior area onde
 * a imagem aparece tem 1200 pixels, e o cliente que abre o cardapio no 4G paga
 * cada byte.
 *
 * Roda no NAVEGADOR, com canvas. Reduzir no servidor exigiria mandar os 8 MB
 * primeiro — exatamente o que se quer evitar.
 */

export type MedidaDaImagem = {
  /** Maior lado, em pixels. O menor acompanha, mantendo a proporcao. */
  maiorLado: number
  /** 0 a 1. 0,82 e o ponto onde o JPEG para de melhorar aos olhos. */
  qualidade?: number
}

export const MEDIDA_DA_LOGO: MedidaDaImagem = { maiorLado: 512 }
export const MEDIDA_DA_CAPA: MedidaDaImagem = { maiorLado: 1600 }
export const MEDIDA_DO_PRODUTO: MedidaDaImagem = { maiorLado: 1200 }

/** Extensoes aceitas, espelhando o que o balde permite. */
export const TIPOS_ACEITOS = ["image/jpeg", "image/png", "image/webp", "image/avif"]

export function ehImagemAceita(arquivo: File): boolean {
  return TIPOS_ACEITOS.includes(arquivo.type)
}

/**
 * Le, reduz e devolve um JPEG.
 *
 * Sempre JPEG: PNG de foto fica maior que o original, e AVIF nao e gerado por
 * todo navegador. A transparencia de um PNG de logo se perde — e um logo com
 * fundo transparente sobre o card branco do cardapio fica igual de qualquer
 * jeito.
 */
export async function reduzirImagem(
  arquivo: File,
  medida: MedidaDaImagem,
): Promise<Blob> {
  const bitmap = await createImageBitmap(arquivo)

  const maior = Math.max(bitmap.width, bitmap.height)
  // Imagem que ja e menor que o alvo nao cresce: ampliar nao inventa detalhe,
  // so aumenta o arquivo.
  const escala = maior > medida.maiorLado ? medida.maiorLado / maior : 1

  const largura = Math.round(bitmap.width * escala)
  const altura = Math.round(bitmap.height * escala)

  const tela = document.createElement("canvas")
  tela.width = largura
  tela.height = altura

  const pincel = tela.getContext("2d")
  if (!pincel) throw new Error("Não consegui preparar a imagem neste navegador.")

  // Fundo branco: JPEG não tem transparência, e sem isto um PNG transparente
  // vira preto.
  pincel.fillStyle = "#ffffff"
  pincel.fillRect(0, 0, largura, altura)
  pincel.drawImage(bitmap, 0, 0, largura, altura)
  bitmap.close()

  return new Promise((resolver, recusar) => {
    tela.toBlob(
      (blob) => (blob ? resolver(blob) : recusar(new Error("Não consegui converter a imagem."))),
      "image/jpeg",
      medida.qualidade ?? 0.82,
    )
  })
}
