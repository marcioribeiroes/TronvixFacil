"use client"

import { useState, useTransition } from "react"

import { Button } from "@/components/ui/button"
import { abrirOuFecharLoja } from "@/modules/painel/pedidos"

/**
 * Abrir e fechar a loja.
 *
 * Fica no topo da fila porque e a decisao mais consequente do balcao: loja
 * fechada nao recebe pedido nenhum, e `fechar_pedido` recusa no banco.
 */
export function ChaveDaLoja({
  aberta,
  noHorario,
  podeMexer,
}: {
  /** A chave da mão. É só ela que este botão liga e desliga. */
  aberta: boolean
  /** O relógio da loja. Fora do horário, a chave ligada não vende. */
  noHorario: boolean
  podeMexer: boolean
}) {
  const [enviando, iniciar] = useTransition()
  const [erro, setErro] = useState<string | null>(null)

  // Vendendo de verdade só quando as duas concordam. Dizer "Aberto agora" com
  // a loja fora do horário é a mentira que fez alguém perguntar por que o
  // aplicativo não mostrava fechado.
  const vendendo = aberta && noHorario

  return (
    <div className="text-right">
      <div className="flex items-center gap-3">
        <span
          className={`inline-flex items-center gap-2 text-sm font-semibold ${vendendo ? "text-status-pronto" : "text-muted-foreground"}`}
        >
          <span
            className={`size-2 rounded-full ${vendendo ? "bg-status-pronto" : "bg-muted-foreground"}`}
            aria-hidden="true"
          />
          {vendendo ? "Aberto agora" : "Fechado"}
        </span>

        {podeMexer ? (
          <Button
            size="sm"
            variant={aberta ? "outline" : "default"}
            disabled={enviando}
            onClick={() =>
              iniciar(async () => {
                const r = await abrirOuFecharLoja(!aberta)
                if (!r.ok) setErro(r.erro)
              })
            }
          >
            {aberta ? "Fechar loja" : "Abrir loja"}
          </Button>
        ) : null}
      </div>
      {aberta && !noHorario ? (
        <p className="mt-1 text-xs text-muted-foreground">
          A chave está ligada, mas é fora do horário. Reabre sozinha no próximo turno.
        </p>
      ) : null}
      {erro ? (
        <p role="alert" className="mt-1 text-sm text-destructive">
          {erro}
        </p>
      ) : null}
    </div>
  )
}
