import type { Metadata } from "next"
import Link from "next/link"
import { CheckCircle2 } from "lucide-react"

export const metadata: Metadata = { title: "Conta apagada" }

/**
 * O fim do caminho de exclusao.
 *
 * Existe porque a alternativa — cair na tela de login logo depois de apagar a
 * conta — parece erro. A pessoa precisa ver, escrito, que deu certo.
 */
export default function ContaApagada() {
  return (
    <div className="mx-auto flex max-w-md flex-col items-center gap-4 px-6 py-20 text-center">
      <CheckCircle2 className="size-12 text-emerald-600" aria-hidden="true" />
      <div>
        <h1 className="text-xl font-bold">Sua conta foi apagada</h1>
        <p className="mt-2 text-sm text-muted-foreground">
          O acesso, o cadastro e os endereços saíram. Os pedidos antigos continuam no
          registro de vendas dos restaurantes, sem o seu nome e sem o seu contato.
        </p>
      </div>
      <Link
        href="/"
        className="rounded-md bg-marca px-5 py-2.5 text-sm font-semibold text-white transition-colors hover:bg-marca-forte"
      >
        Voltar ao início
      </Link>
    </div>
  )
}
