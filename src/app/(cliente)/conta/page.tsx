import type { Metadata } from "next"
import Link from "next/link"
import { ChevronRight, LayoutDashboard, LogOut, MapPin, Receipt, UserX } from "lucide-react"

import { Button } from "@/components/ui/button"
import { sair } from "@/modules/auth/acoes"
import { exigirUsuario, rotaInicialDe } from "@/modules/auth/sessao"

export const metadata: Metadata = { title: "Conta" }

/**
 * A conta do cliente: o caminho para pedidos e enderecos, e a saida.
 *
 * Existia na barra de baixo do celular, mas a pagina nao — o botao "Perfil"
 * dava em 404.
 */
export default async function PaginaDaConta() {
  const contexto = await exigirUsuario("/conta")
  const destino = rotaInicialDe(contexto)

  const linhas = [
    ...(destino !== "/"
      ? [
          {
            href: destino,
            rotulo: contexto.ehAdminDaPlataforma
              ? "Administração"
              : contexto.vinculos.length > 0
                ? "Painel da loja"
                : "Entregas",
            Icone: LayoutDashboard,
          },
        ]
      : []),
    { href: "/pedidos", rotulo: "Meus pedidos", Icone: Receipt },
    { href: "/conta/enderecos", rotulo: "Endereços", Icone: MapPin },
    { href: "/excluir-conta", rotulo: "Excluir minha conta", Icone: UserX },
  ]

  return (
    <div className="mx-auto max-w-2xl space-y-6 py-2">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">
          {contexto.perfil.full_name || "Sua conta"}
        </h1>
        {contexto.email ? (
          <p className="mt-1 text-sm text-muted-foreground">{contexto.email}</p>
        ) : null}
      </div>

      <ul className="divide-y rounded-xl border bg-card">
        {linhas.map(({ href, rotulo, Icone }) => (
          <li key={href}>
            <Link href={href} className="flex items-center gap-3 p-4 hover:bg-muted/50">
              <Icone className="size-4 text-muted-foreground" aria-hidden="true" />
              <span className="flex-1 font-medium">{rotulo}</span>
              <ChevronRight className="size-4 text-muted-foreground" aria-hidden="true" />
            </Link>
          </li>
        ))}
      </ul>

      <form action={sair}>
        <Button type="submit" variant="outline" className="w-full">
          <LogOut className="size-4" aria-hidden="true" />
          Sair
        </Button>
      </form>
    </div>
  )
}
