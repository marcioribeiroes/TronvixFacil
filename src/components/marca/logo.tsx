import { cn } from "@/lib/utils"

/**
 * Marca do Tronvix Facil.
 *
 * O simbolo junta as duas ideias do produto num desenho so: a cupula de um
 * prato servido (a comida) dentro da silhueta de um alfinete de mapa (a
 * entrega). Desenho proprio, sem referencia a nenhuma marca existente.
 *
 * SVG inline, nao arquivo de imagem: assim o simbolo herda a cor do texto ao
 * redor e funciona igual na sidebar escura, no fundo claro e no favicon.
 */

export function SimboloTronvixFacil({ className }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 40 40"
      fill="none"
      aria-hidden="true"
      className={cn("size-8", className)}
    >
      {/* Alfinete de mapa: a entrega */}
      <path
        d="M20 2.5c-7.18 0-13 5.6-13 12.5 0 8.9 10.2 20.1 12.1 22.1a1.25 1.25 0 0 0 1.8 0C22.8 35.1 33 23.9 33 15c0-6.9-5.82-12.5-13-12.5Z"
        fill="currentColor"
      />
      {/* Cupula do prato servido, vazada: a comida */}
      <path
        d="M12.5 19.5h15c0-3.9-3.36-7-7.5-7s-7.5 3.1-7.5 7Z"
        fill="var(--marca-contraste)"
      />
      <path
        d="M11 21.75h18"
        stroke="var(--marca-contraste)"
        strokeWidth="2.25"
        strokeLinecap="round"
      />
      {/* Pegador da cupula */}
      <circle cx="20" cy="10.75" r="1.5" fill="var(--marca-contraste)" />
    </svg>
  )
}

type TamanhoDaLogo = "sm" | "md" | "lg"

const TAMANHOS: Record<TamanhoDaLogo, { simbolo: string; titulo: string; sub: string }> = {
  sm: { simbolo: "size-7", titulo: "text-base", sub: "text-[9px]" },
  md: { simbolo: "size-9", titulo: "text-xl", sub: "text-[10px]" },
  lg: { simbolo: "size-12", titulo: "text-3xl", sub: "text-xs" },
}

export function LogoTronvixFacil({
  tamanho = "md",
  className,
  /** Subtitulo do painel: "Painel do Restaurante", "Painel Administrativo"... */
  legenda,
  /** Em superficie escura, o texto vira branco e o simbolo mantem o vermelho. */
  escuro = false,
}: {
  tamanho?: TamanhoDaLogo
  className?: string
  legenda?: string
  escuro?: boolean
}) {
  const medida = TAMANHOS[tamanho]

  return (
    <span className={cn("inline-flex items-center gap-2.5", className)}>
      <SimboloTronvixFacil className={cn(medida.simbolo, "text-marca shrink-0")} />
      <span className="flex flex-col leading-none">
        <span
          className={cn(
            "font-bold tracking-tight",
            medida.titulo,
            escuro ? "text-white" : "text-foreground",
          )}
        >
          Tronvix <span className="text-marca">Fácil</span>
        </span>
        {legenda ? (
          <span
            className={cn(
              "mt-1 font-semibold uppercase tracking-[0.18em]",
              medida.sub,
              escuro ? "text-white/55" : "text-muted-foreground",
            )}
          >
            {legenda}
          </span>
        ) : null}
      </span>
    </span>
  )
}

/** Assinatura da plataforma, usada nas telas de entrada. */
export const SLOGAN = "Seu pedido na palma da mão"
