import Link from "next/link"
import { UtensilsCrossed } from "lucide-react"

import { sairDaMesa } from "@/modules/cliente/acoes-da-mesa"

/**
 * "Voce esta na Mesa 7."
 *
 * Existe porque a mesa vive num cookie, e cookie e invisivel. Sem esta faixa,
 * quem escaneou de manha e volta a tarde de casa faria um pedido para o salao
 * sem perceber - e alguem levaria um prato para uma mesa vazia.
 *
 * Por isso a saida fica aqui do lado, e nao escondida em configuracoes.
 */
export function FaixaDaMesa({
  rotulo,
  restaurante,
  slug,
}: {
  rotulo: string
  restaurante: string
  slug: string
}) {
  return (
    <div className="border-b border-marca/20 bg-marca-suave">
      <div className="mx-auto flex max-w-6xl flex-wrap items-center gap-x-3 gap-y-1 px-4 py-2 text-sm">
        <UtensilsCrossed className="size-4 shrink-0 text-marca-forte" aria-hidden="true" />
        <span className="min-w-0 flex-1 text-marca-forte">
          Você está na <strong>{rotulo}</strong> ·{" "}
          <Link href={`/restaurante/${slug}`} className="underline underline-offset-2">
            {restaurante}
          </Link>
        </span>
        <form action={sairDaMesa}>
          <button
            type="submit"
            className="shrink-0 rounded-md px-2 py-1 text-xs font-semibold text-marca-forte underline underline-offset-2"
          >
            Não estou nesta mesa
          </button>
        </form>
      </div>
    </div>
  )
}
