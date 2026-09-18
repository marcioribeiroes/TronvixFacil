"use client"

import Link from "next/link"
import { usePathname } from "next/navigation"
import {
  BarChart3,
  Bike,
  Building2,
  ClipboardList,
  DollarSign,
  Image as ImageIcon,
  LayoutDashboard,
  ListOrdered,
  LogOut,
  Package,
  Percent,
  PlusSquare,
  QrCode,
  Receipt,
  Settings,
  Tag,
  Users,
  UtensilsCrossed,
  type LucideIcon,
} from "lucide-react"

import { LogoTronvixFacil } from "@/components/marca/logo"
import { sair } from "@/modules/auth/acoes"
import { cn } from "@/lib/utils"

/**
 * Os icones vivem AQUI, do lado do cliente, e o menu viaja com o nome deles.
 *
 * Nao e preciosismo: um componente de icone e uma funcao, e funcao nao
 * atravessa a fronteira de Server Component para Client Component. Passando o
 * componente direto, o React derruba a pagina inteira com
 *
 *   "Only plain objects can be passed to Client Components from Server
 *    Components."
 *
 * Era o que acontecia com /admin e /painel: a rota respondia, o login
 * funcionava, e a tela quebrava ao montar. String atravessa; funcao nao.
 */
const ICONES = {
  dashboard: LayoutDashboard,
  estabelecimentos: Building2,
  usuarios: Users,
  entregadores: Bike,
  pedidos: Receipt,
  comanda: ClipboardList,
  financeiro: DollarSign,
  comissoes: Percent,
  cupons: Tag,
  banners: ImageIcon,
  categorias: ListOrdered,
  relatorios: BarChart3,
  configuracoes: Settings,
  cardapio: UtensilsCrossed,
  produtos: Package,
  adicionais: PlusSquare,
  mesas: QrCode,
} as const satisfies Record<string, LucideIcon>

export type NomeDoIcone = keyof typeof ICONES

export type ItemDeMenu = {
  rotulo: string
  href: string
  icone: NomeDoIcone
  /** Contador opcional (pedidos novos, por exemplo). */
  contador?: number
}

/**
 * Sidebar dos paineis de trabalho (restaurante e administracao).
 *
 * Fica escura mesmo no tema claro: separa a navegacao do conteudo e e a
 * assinatura visual dos paineis. No celular ela sai do fluxo - quem usa o
 * painel pelo telefone acessa o menu pelo cabecalho.
 */
export function SidebarDoPainel({
  itens,
  legenda,
  rodape,
}: {
  itens: ItemDeMenu[]
  legenda: string
  rodape?: React.ReactNode
}) {
  const caminho = usePathname()

  return (
    <aside className="hidden w-60 shrink-0 flex-col bg-sidebar text-sidebar-foreground lg:flex">
      <div className="px-5 py-6">
        <Link href="/">
          <LogoTronvixFacil tamanho="sm" legenda={legenda} escuro />
        </Link>
      </div>

      {rodape}

      <nav className="flex-1 space-y-0.5 overflow-y-auto px-3 py-2" aria-label="Menu principal">
        {itens.map((item) => {
          // startsWith para que /painel/produtos/novo mantenha "Produtos"
          // marcado. A home do painel e comparada por igualdade, senao ficaria
          // ativa o tempo todo.
          const ativo =
            item.href === "/painel" || item.href === "/admin" || item.href === "/entregas"
              ? caminho === item.href
              : caminho.startsWith(item.href)

          const Icone = ICONES[item.icone]

          return (
            <Link
              key={item.href}
              href={item.href}
              aria-current={ativo ? "page" : undefined}
              className={cn(
                "flex items-center gap-3 rounded-md px-3 py-2 text-sm font-medium transition-colors",
                ativo
                  ? "bg-sidebar-primary text-sidebar-primary-foreground"
                  : "text-sidebar-foreground/70 hover:bg-sidebar-accent hover:text-sidebar-accent-foreground",
              )}
            >
              <Icone className="size-4 shrink-0" aria-hidden="true" />
              <span className="flex-1">{item.rotulo}</span>
              {item.contador ? (
                <span
                  className={cn(
                    "rounded-full px-1.5 py-0.5 text-[10px] font-bold",
                    ativo ? "bg-white/20 text-white" : "bg-marca text-white",
                  )}
                >
                  {item.contador}
                </span>
              ) : null}
            </Link>
          )
        })}
      </nav>

      <form action={sair} className="border-t border-sidebar-border p-3">
        <button
          type="submit"
          className="flex w-full items-center gap-3 rounded-md px-3 py-2 text-sm font-medium text-sidebar-foreground/70 transition-colors hover:bg-sidebar-accent hover:text-sidebar-accent-foreground"
        >
          <LogOut className="size-4" aria-hidden="true" />
          Sair
        </button>
      </form>
    </aside>
  )
}
