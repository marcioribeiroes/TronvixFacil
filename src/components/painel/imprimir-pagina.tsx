"use client"

import { Printer } from "lucide-react"

import { Button } from "@/components/ui/button"

/** Imprimir ou salvar em PDF: os dois saem do mesmo diálogo do navegador. */
export function ImprimirPagina({ rotulo = "Imprimir ou salvar PDF" }: { rotulo?: string }) {
  return (
    <Button onClick={() => window.print()}>
      <Printer className="size-4" aria-hidden="true" />
      {rotulo}
    </Button>
  )
}
