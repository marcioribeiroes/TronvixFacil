"use client"

import { useEffect, useState } from "react"
import { Check, Copy, QrCode } from "lucide-react"

import { Button } from "@/components/ui/button"
import { formatarReais } from "@/lib/dinheiro"

/**
 * Pagar o pedido pelo Pix.
 *
 * O "copia e cola" vem antes do QR de propósito: quem está com o celular na mão
 * não consegue fotografar a própria tela. O QR existe para o caso de alguém
 * pagar pelo computador, ou de a pessoa da mesa mostrar a tela para outra.
 *
 * O desenho do QR é feito aqui, no navegador, a partir do mesmo texto — assim
 * não há duas fontes de verdade, e um não pode divergir do outro.
 */
export function PagarComPix({
  codigo,
  centavos,
  numero,
}: {
  codigo: string
  centavos: number
  numero: number
}) {
  const [copiado, setCopiado] = useState(false)
  const [svg, setSvg] = useState<string | null>(null)

  useEffect(() => {
    // Carregado sob demanda: quem paga em dinheiro não baixa a biblioteca de
    // QR só por abrir a tela do pedido.
    let vivo = true
    import("qrcode")
      .then((qr) => qr.toString(codigo, { type: "svg", margin: 1, errorCorrectionLevel: "M" }))
      .then((s) => vivo && setSvg(s))
      .catch(() => {
        // Sem o desenho, o copia e cola continua ali — e é ele que a maioria usa.
      })
    return () => {
      vivo = false
    }
  }, [codigo])

  async function copiar() {
    try {
      await navigator.clipboard.writeText(codigo)
      setCopiado(true)
      setTimeout(() => setCopiado(false), 2500)
    } catch {
      // Navegador sem permissão de área de transferência: o texto está na tela
      // e dá para selecionar à mão.
    }
  }

  return (
    <section className="rounded-xl border-2 border-marca bg-marca/5 p-4">
      <h2 className="flex items-center gap-2 font-bold">
        <QrCode className="size-5 text-marca" aria-hidden="true" />
        Pague {formatarReais(centavos)} por Pix
      </h2>
      <p className="mt-1 text-sm text-muted-foreground">
        A cozinha começa assim que o restaurante confirmar que o dinheiro entrou.
      </p>

      <Button className="mt-4 h-12 w-full text-base" onClick={copiar}>
        {copiado ? (
          <>
            <Check className="size-5" aria-hidden="true" />
            Código copiado
          </>
        ) : (
          <>
            <Copy className="size-5" aria-hidden="true" />
            Copiar código Pix
          </>
        )}
      </Button>

      <p className="mt-2 text-center text-xs text-muted-foreground">
        Abra o aplicativo do seu banco e escolha <strong>Pix copia e cola</strong>.
      </p>

      {svg ? (
        <details className="mt-4">
          <summary className="cursor-pointer text-center text-sm font-semibold text-marca">
            Ou mostre o QR Code
          </summary>
          <div
            className="mx-auto mt-3 w-48 rounded-lg bg-white p-2 [&>svg]:h-full [&>svg]:w-full"
            // O SVG vem do gerador de QR sobre um texto que o próprio servidor
            // montou — não há conteúdo de usuário aqui.
            dangerouslySetInnerHTML={{ __html: svg }}
          />
        </details>
      ) : null}

      <p className="mt-4 break-all rounded-lg bg-background p-2 text-center font-mono text-[10px] text-muted-foreground">
        {codigo}
      </p>

      <p className="mt-2 text-center text-xs text-muted-foreground">
        Identificação no seu extrato: <strong>TF{numero}</strong>
      </p>
    </section>
  )
}
