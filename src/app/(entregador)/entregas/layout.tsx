import Link from "next/link"
import { History, LogOut, Package, User } from "lucide-react"

import { LogoTronvixFacil } from "@/components/marca/logo"
import { sair } from "@/modules/auth/acoes"

/**
 * Moldura do app do entregador.
 *
 * Diferente dos outros paineis de proposito: quem usa esta tela esta na rua,
 * de capacete, com uma mao so. Por isso a navegacao fica embaixo (alcance do
 * polegar), os alvos sao grandes e nao ha sidebar em nenhum tamanho de tela.
 */

const ITENS = [
  { rotulo: "Corridas", href: "/entregas", icone: Package },
  { rotulo: "Histórico", href: "/entregas/historico", icone: History },
  { rotulo: "Perfil", href: "/entregas/perfil", icone: User },
]

export default function LayoutDoEntregador({ children }: LayoutProps<"/entregas">) {
  return (
    <div className="flex min-h-dvh flex-col bg-muted/40">
      <header className="sticky top-0 z-30 flex h-14 items-center justify-between border-b bg-carvao px-4">
        <LogoTronvixFacil tamanho="sm" legenda="Entregador" escuro />
        <form action={sair}>
          <button
            type="submit"
            aria-label="Sair"
            className="grid size-9 place-items-center rounded-md text-white/60 transition-colors hover:bg-white/10 hover:text-white"
          >
            <LogOut className="size-5" />
          </button>
        </form>
      </header>

      <main className="flex-1 p-4 pb-24">{children}</main>

      <nav
        aria-label="Navegação do entregador"
        className="area-segura-inferior fixed inset-x-0 bottom-0 z-40 border-t bg-background"
      >
        <ul className="mx-auto flex max-w-lg">
          {ITENS.map((item) => {
            const Icone = item.icone
            return (
              <li key={item.href} className="flex-1">
                <Link
                  href={item.href}
                  className="flex flex-col items-center gap-1 py-2.5 text-[11px] font-medium text-muted-foreground transition-colors hover:text-marca"
                >
                  <Icone className="size-5" aria-hidden="true" />
                  {item.rotulo}
                </Link>
              </li>
            )
          })}
        </ul>
      </nav>
    </div>
  )
}
