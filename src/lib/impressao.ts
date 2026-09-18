/**
 * Mandar a comanda para a impressora.
 *
 * O caminho e o driver do sistema, e nao ESC/POS direto. Falar ESC/POS pela
 * USB funcionaria sem diálogo, mas exigiria conhecer o modelo da impressora de
 * cada cliente — Epson, Elgin e Bematech respondem a comandos diferentes, e
 * cada uma tem a sua peculiaridade de corte e gaveta. Pelo driver, funciona com
 * qualquer impressora que o computador ja imprime.
 *
 * A comanda vai num iframe escondido, carregando a pagina /painel/comanda/<id>.
 * Imprimir a propria pagina exigiria esconder o quadro inteiro no CSS de
 * impressao e torcer para nao ter esquecido nada; o iframe imprime so o que
 * esta dentro dele.
 */

/** Quanto esperar a comanda carregar antes de desistir. */
const LIMITE = 12_000

export function imprimirComanda(pedidoId: string): Promise<boolean> {
  return new Promise((resolver) => {
    const quadro = document.createElement("iframe")
    quadro.style.position = "fixed"
    quadro.style.right = "0"
    quadro.style.bottom = "0"
    quadro.style.width = "0"
    quadro.style.height = "0"
    quadro.style.border = "0"
    // Sem isto, alguns navegadores recusam imprimir de um iframe sem foco.
    quadro.setAttribute("aria-hidden", "true")

    let terminou = false

    function encerrar(ok: boolean) {
      if (terminou) return
      terminou = true
      // Um respiro antes de remover: arrancar o iframe no mesmo instante da
      // chamada de impressao cancela o trabalho em parte dos navegadores.
      setTimeout(() => quadro.remove(), 1000)
      resolver(ok)
    }

    quadro.onload = () => {
      try {
        const janela = quadro.contentWindow
        if (!janela) return encerrar(false)
        janela.focus()
        janela.print()
        encerrar(true)
      } catch {
        encerrar(false)
      }
    }

    quadro.onerror = () => encerrar(false)
    setTimeout(() => encerrar(false), LIMITE)

    quadro.src = `/painel/comanda/${pedidoId}`
    document.body.appendChild(quadro)
  })
}

/**
 * Quais comandas ja sairam, neste navegador.
 *
 * Sem isto, recarregar a pagina reimprime tudo que ainda esta esperando — e o
 * balcao acorda com trinta comandas no chao. Fica no proprio aparelho porque a
 * pergunta e local: "esta impressora ja cuspiu este pedido?".
 */
const CHAVE = "tronvix_comandas_impressas"

export function jaImpressos(): Set<string> {
  try {
    return new Set(JSON.parse(localStorage.getItem(CHAVE) ?? "[]") as string[])
  } catch {
    return new Set()
  }
}

export function marcarImpresso(id: string) {
  try {
    // Guarda os últimos 200: a lista não pode crescer para sempre, e um pedido
    // de duzentos atrás não volta para a fila.
    const lista = [...jaImpressos(), id].slice(-200)
    localStorage.setItem(CHAVE, JSON.stringify(lista))
  } catch {
    // Sem armazenamento, o pior caso é reimprimir. Melhor do que não imprimir.
  }
}
