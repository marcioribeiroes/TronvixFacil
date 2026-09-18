import Link from "next/link"
import { Check, CircleAlert } from "lucide-react"

/**
 * O que ainda falta para a loja poder vender.
 *
 * Aparece so enquanto ha pendencia. Loja pronta nao precisa de lista de
 * tarefas ocupando a primeira tela do dia - e uma lista que nunca some vira
 * papel de parede e para de ser lida.
 */

export type ItemDeProntidao = {
  chave: string
  titulo: string
  ok: boolean
  /** Por que isso importa. So aparece quando esta pendente. */
  pendencia: string
  acao?: { rotulo: string; href: string }
}

export function ProntidaoDaLoja({ itens }: { itens: ItemDeProntidao[] }) {
  const faltando = itens.filter((i) => !i.ok)
  if (faltando.length === 0) return null

  const prontos = itens.length - faltando.length

  return (
    <section className="rounded-xl border border-amber-300 bg-amber-50 p-4 dark:border-amber-900 dark:bg-amber-950/30">
      <div className="flex items-center gap-2">
        <CircleAlert className="size-4 shrink-0 text-amber-600 dark:text-amber-500" />
        <h2 className="text-sm font-bold">
          Falta {faltando.length === 1 ? "um passo" : `${faltando.length} passos`} para vender
        </h2>
        <span className="ml-auto text-xs text-muted-foreground">
          {prontos} de {itens.length} prontos
        </span>
      </div>

      <ul className="mt-3 space-y-2">
        {faltando.map((item) => (
          <li
            key={item.chave}
            className="flex flex-wrap items-center gap-x-3 gap-y-1 rounded-lg bg-background p-3"
          >
            <span className="min-w-0 flex-1">
              <span className="block text-sm font-semibold">{item.titulo}</span>
              <span className="block text-xs text-muted-foreground">{item.pendencia}</span>
            </span>
            {item.acao ? (
              <Link
                href={item.acao.href}
                className="shrink-0 rounded-md border px-3 py-1.5 text-xs font-semibold transition-colors hover:bg-muted"
              >
                {item.acao.rotulo}
              </Link>
            ) : null}
          </li>
        ))}
      </ul>

      {prontos > 0 ? (
        <ul className="mt-3 flex flex-wrap gap-x-4 gap-y-1">
          {itens
            .filter((i) => i.ok)
            .map((i) => (
              <li
                key={i.chave}
                className="flex items-center gap-1.5 text-xs text-muted-foreground"
              >
                <Check className="size-3 text-emerald-600" />
                {i.titulo}
              </li>
            ))}
        </ul>
      ) : null}
    </section>
  )
}
