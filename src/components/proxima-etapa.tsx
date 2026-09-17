import { Construction } from "lucide-react"

/**
 * Marcador honesto de tela ainda nao construida.
 *
 * O projeto e entregue por etapas; esta e a tela que ocupa o lugar do que
 * ainda nao chegou. Diz qual etapa entrega aquilo e o que ja funciona por
 * baixo, em vez de fingir uma interface pronta com dados inventados.
 */
export function ProximaEtapa({
  titulo,
  etapa,
  descricao,
  jaPronto,
}: {
  titulo: string
  etapa: string
  descricao: string
  jaPronto?: string[]
}) {
  return (
    <div className="mx-auto max-w-lg rounded-xl border border-dashed bg-card p-8 text-center">
      <Construction className="mx-auto size-8 text-muted-foreground" aria-hidden="true" />
      <h2 className="mt-4 text-lg font-bold tracking-tight">{titulo}</h2>
      <p className="mt-1 text-sm text-muted-foreground">{descricao}</p>

      <p className="mt-4 inline-block rounded-full bg-marca-suave px-3 py-1 text-xs font-semibold text-marca-forte">
        Chega na {etapa}
      </p>

      {jaPronto && jaPronto.length > 0 ? (
        <div className="mt-6 border-t pt-4 text-left">
          <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
            Já pronto por baixo
          </p>
          <ul className="mt-2 space-y-1.5 text-sm text-muted-foreground">
            {jaPronto.map((item) => (
              <li key={item} className="flex items-start gap-2">
                <span className="mt-1.5 size-1.5 shrink-0 rounded-full bg-status-pronto" />
                {item}
              </li>
            ))}
          </ul>
        </div>
      ) : null}
    </div>
  )
}
