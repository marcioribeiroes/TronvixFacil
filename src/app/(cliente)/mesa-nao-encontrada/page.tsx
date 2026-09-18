import type { Metadata } from "next"
import Link from "next/link"
import { QrCode } from "lucide-react"

export const metadata: Metadata = { title: "Mesa não encontrada" }

/**
 * QR que nao levou a lugar nenhum.
 *
 * Acontece de verdade: etiqueta antiga numa mesa removida, mesa fora de uso
 * hoje, ou o codigo digitado errado a mao. A tela precisa dizer o que fazer —
 * e o que fazer, num restaurante, e chamar alguem do salao.
 */
export default function MesaNaoEncontrada() {
  return (
    <div className="mx-auto flex max-w-md flex-col items-center gap-4 px-6 py-16 text-center">
      <QrCode className="size-12 text-muted-foreground" aria-hidden="true" />
      <div>
        <h1 className="text-xl font-bold">Não encontrei essa mesa</h1>
        <p className="mt-2 text-sm text-muted-foreground">
          A etiqueta pode ser de uma mesa que saiu de uso. Chame alguém do salão — e, se
          quiser, peça por aqui mesmo escolhendo o restaurante.
        </p>
      </div>
      <Link
        href="/"
        className="rounded-md bg-marca px-5 py-2.5 text-sm font-semibold text-white transition-colors hover:bg-marca-forte"
      >
        Ver os restaurantes
      </Link>
    </div>
  )
}
