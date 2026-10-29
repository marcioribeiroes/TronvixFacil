"use client"

import { useTransition } from "react"
import { Trash2 } from "lucide-react"

import { Button } from "@/components/ui/button"
import { apagarPreparo } from "@/modules/painel/cozinha"

/** So a gestao ve este botao; quem garante e a RLS de kitchen_preps. */
export function ApagarPreparo({ id, numero }: { id: string; numero: number }) {
  const [enviando, iniciar] = useTransition()

  return (
    <Button
      variant="ghost"
      size="icon"
      aria-label={`Apagar o preparo ${numero}`}
      disabled={enviando}
      onClick={() => {
        if (!window.confirm(`Apagar o preparo nº ${numero}? Isso não tem volta.`)) return
        iniciar(async () => {
          const r = await apagarPreparo(id)
          if (!r.ok) window.alert(r.erro)
        })
      }}
    >
      <Trash2 className="size-4" aria-hidden="true" />
    </Button>
  )
}
