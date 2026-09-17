"use client"

import { Loader2 } from "lucide-react"
import { useFormStatus } from "react-dom"

import { Button } from "@/components/ui/button"

/**
 * Botao de envio que se desabilita sozinho enquanto a Server Action roda.
 *
 * useFormStatus le o estado do <form> mais proximo, entao o botao nao precisa
 * receber estado por prop. Alem do feedback visual, o disabled evita o duplo
 * clique - que em um checkout significaria dois pedidos.
 */
export function BotaoDeEnvio({
  children,
  carregando,
  className,
}: {
  children: React.ReactNode
  carregando?: string
  className?: string
}) {
  const { pending } = useFormStatus()

  return (
    <Button type="submit" size="lg" disabled={pending} className={className}>
      {pending ? (
        <>
          <Loader2 className="size-4 animate-spin" aria-hidden="true" />
          {carregando ?? "Aguarde..."}
        </>
      ) : (
        children
      )}
    </Button>
  )
}
