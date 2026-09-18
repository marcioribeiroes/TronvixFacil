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
  podeMexer,
}: {
  aberta: boolean
  podeMexer: boolean
}) {
  const [enviando, iniciar] = useTransition()
  const [erro, setErro] = useState<string | null>(null)

  return (
    <div className="text-right">
      <div className="flex items-center gap-3">
        <span
          className={`inline-flex items-center gap-2 text-sm font-semibold ${aberta ? "text-status-pronto" : "text-muted-foreground"}`}
        >
          <span
            className={`size-2 rounded-full ${aberta ? "bg-status-pronto" : "bg-muted-foreground"}`}
            aria-hidden="true"
          />
          {aberta ? "Aberto agora" : "Fechado"}
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
      {erro ? (
        <p role="alert" className="mt-1 text-sm text-destructive">
          {erro}
        </p>
      ) : null}
    </div>
  )
}
