import type { Metadata } from "next"
import Link from "next/link"
import { CircleCheck } from "lucide-react"

export const metadata: Metadata = { title: "Cadastro enviado" }

/**
 * O que acontece depois de enviar.
 *
 * A tela diz duas coisas que a pessoa precisa saber agora: que a loja ainda nao
 * vende, e que ja da para trabalhar. Sem isso, quem cadastrou fica esperando um
 * e-mail e perde o dia que podia usar montando o cardapio.
 */
export default async function CadastroEnviado({
  searchParams,
}: PageProps<"/cadastrar-restaurante/enviado">) {
  const parametros = await searchParams
  const loja = typeof parametros.loja === "string" ? parametros.loja : null

  return (
    <div className="mx-auto max-w-xl space-y-6 text-center">
      <CircleCheck className="mx-auto size-12 text-emerald-600" aria-hidden="true" />

      <div>
        <h1 className="text-2xl font-bold tracking-tight">Cadastro enviado</h1>
        <p className="mt-2 text-sm text-muted-foreground">
          A plataforma vai analisar e liberar. Até lá sua loja não aparece na vitrine.
        </p>
      </div>

      <div className="rounded-xl border bg-card p-5 text-left">
        <p className="text-sm font-bold">Enquanto isso, adiante o trabalho</p>
        <ul className="mt-3 space-y-2 text-sm text-muted-foreground">
          <li>• Monte o cardápio: categorias, produtos e preços.</li>
          <li>• Ajuste taxa de entrega, pedido mínimo e horário de funcionamento.</li>
          <li>• Cadastre seus entregadores.</li>
        </ul>
        <p className="mt-4 text-xs text-muted-foreground">
          Quando a aprovação sair, basta abrir a loja no painel e começar a receber pedido.
        </p>
      </div>

      <div className="flex flex-col gap-3 sm:flex-row sm:justify-center">
        <Link
          href="/painel"
          className="rounded-md bg-marca px-6 py-2.5 text-sm font-semibold text-white transition-colors hover:bg-marca-forte"
        >
          Ir para o painel
        </Link>
        {loja ? (
          <Link
            href={`/restaurante/${loja}`}
            className="rounded-md border px-6 py-2.5 text-sm font-semibold transition-colors hover:bg-muted"
          >
            Ver como vai ficar
          </Link>
        ) : null}
      </div>
    </div>
  )
}
