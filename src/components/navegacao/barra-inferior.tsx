"use client"

import Link from "next/link"
import { usePathname } from "next/navigation"
import { Heart, Home, Receipt, User } from "lucide-react"

import { cn } from "@/lib/utils"

const ITENS = [
  { rotulo: "Início", href: "/", icone: Home },
  { rotulo: "Pedidos", href: "/conta/pedidos", icone: Receipt },
  { rotulo: "Favoritos", href: "/conta/favoritos", icone: Heart },
  { rotulo: "Perfil", href: "/conta", icone: User },
]

/**
 * Barra inferior do aplicativo do cliente.
 *
 * So aparece no celular: no desktop a navegacao mora no cabecalho. O padding
 * inferior respeita a area segura de aparelhos com barra de gestos.
 */
export function BarraInferior() {
  const caminho = usePathname()

  return (
    <nav
      aria-label="Navegação principal"
      className="area-segura-inferior fixed inset-x-0 bottom-0 z-40 border-t bg-background/95 backdrop-blur md:hidden"
    >
      <ul className="mx-auto flex max-w-lg items-stretch">
        {ITENS.map((item) => {
          const ativo = item.href === "/" ? caminho === "/" : caminho.startsWith(item.href)
          const Icone = item.icone

          return (
            <li key={item.href} className="flex-1">
              <Link
                href={item.href}
                aria-current={ativo ? "page" : undefined}
                className={cn(
                  "flex flex-col items-center gap-1 pt-2 text-[11px] font-medium transition-colors",
                  ativo ? "text-marca" : "text-muted-foreground",
                )}
              >
                <Icone className="size-5" aria-hidden="true" />
                {item.rotulo}
              </Link>
            </li>
          )
        })}
      </ul>
    </nav>
  )
}
