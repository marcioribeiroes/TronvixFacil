"use client"

import { Eye, EyeOff } from "lucide-react"
import * as React from "react"

import { Input } from "@/components/ui/input"
import { cn } from "@/lib/utils"

/**
 * Campo de senha com alternancia de visibilidade.
 *
 * O botao tem aria-label que muda de acordo com o estado: um leitor de tela
 * anuncia "Mostrar senha" ou "Ocultar senha", nao um botao sem nome.
 */
export function CampoDeSenha({
  className,
  ...props
}: React.ComponentProps<typeof Input>) {
  const [visivel, setVisivel] = React.useState(false)

  return (
    <div className="relative">
      <Input
        type={visivel ? "text" : "password"}
        className={cn("pr-10", className)}
        {...props}
      />
      <button
        type="button"
        onClick={() => setVisivel((atual) => !atual)}
        aria-label={visivel ? "Ocultar senha" : "Mostrar senha"}
        className="absolute inset-y-0 right-0 flex w-10 items-center justify-center text-muted-foreground transition-colors hover:text-foreground focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring"
      >
        {visivel ? <EyeOff className="size-4" /> : <Eye className="size-4" />}
      </button>
    </div>
  )
}
