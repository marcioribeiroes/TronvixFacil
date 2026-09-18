"use client"

import { useRouter } from "next/navigation"
import { useState, useTransition } from "react"

import { Button } from "@/components/ui/button"
import { cancelarMeuPedido } from "@/modules/cliente/pedidos"

/**
 * Desistir do pedido.
 *
 * Duas etapas de propósito: o botão abre a confirmação, e só a segunda ação
 * cancela. Um toque sem querer no celular, num pedido de sessenta reais, é o
 * tipo de engano que ninguém perdoa.
 *
 * Só aparece enquanto a loja não aceitou — depois disso a comida está sendo
 * feita, e o banco recusa. Mostrar um botão que vai falhar seria pior do que
 * não mostrar botão nenhum.
 */
export function CancelarPedido({ id }: { id: string }) {
  const router = useRouter()
  const [confirmando, setConfirmando] = useState(false)
  const [enviando, iniciar] = useTransition()
  const [erro, setErro] = useState<string | null>(null)

  if (!confirmando) {
    return (
      <button
        type="button"
        onClick={() => setConfirmando(true)}
        className="text-sm font-semibold text-muted-foreground underline underline-offset-4 hover:text-destructive"
      >
        Cancelar pedido
      </button>
    )
  }

  return (
    <div className="rounded-xl border p-4">
      <p className="text-sm font-semibold">Cancelar este pedido?</p>
      <p className="mt-1 text-xs text-muted-foreground">
        O restaurante ainda não começou a preparar. Depois que ele aceitar, o cancelamento
        passa a ser com a loja.
      </p>

      {erro ? <p className="mt-2 text-sm text-destructive">{erro}</p> : null}

      <div className="mt-3 flex gap-2">
        <Button
          variant="destructive"
          size="sm"
          disabled={enviando}
          onClick={() =>
            iniciar(async () => {
              const r = await cancelarMeuPedido(id)
              if (r.ok) router.refresh()
              else setErro(r.erro)
            })
          }
        >
          {enviando ? "Cancelando…" : "Sim, cancelar"}
        </Button>
        <Button
          variant="outline"
          size="sm"
          disabled={enviando}
          onClick={() => setConfirmando(false)}
        >
          Manter o pedido
        </Button>
      </div>
    </div>
  )
}
