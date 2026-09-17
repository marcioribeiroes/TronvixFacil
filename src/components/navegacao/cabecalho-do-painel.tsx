"use client"

import { Bell, Menu } from "lucide-react"

import { Button } from "@/components/ui/button"

/**
 * Cabecalho dos paineis: identifica onde a pessoa esta e abre o menu no
 * celular, onde a sidebar nao cabe.
 */
export function CabecalhoDoPainel({
  titulo,
  nomeDoUsuario,
}: {
  titulo: string
  nomeDoUsuario: string
}) {
  const iniciais = nomeDoUsuario
    .split(" ")
    .filter(Boolean)
    .slice(0, 2)
    .map((parte) => parte[0]?.toUpperCase())
    .join("")

  return (
    <header className="sticky top-0 z-30 flex h-14 items-center gap-3 border-b bg-background px-4 md:px-6">
      <Button variant="ghost" size="icon" className="lg:hidden" aria-label="Abrir menu">
        <Menu className="size-5" />
      </Button>

      <h1 className="min-w-0 flex-1 truncate text-sm font-semibold">{titulo}</h1>

      <Button variant="ghost" size="icon" aria-label="Notificações">
        <Bell className="size-5" />
      </Button>

      <span
        className="grid size-8 shrink-0 place-items-center rounded-full bg-marca text-xs font-bold text-white"
        title={nomeDoUsuario}
      >
        {iniciais || "?"}
      </span>
    </header>
  )
}
