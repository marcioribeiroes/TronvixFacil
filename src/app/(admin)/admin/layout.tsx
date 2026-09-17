import {
  BarChart3,
  Bike,
  Building2,
  DollarSign,
  Image as ImageIcon,
  LayoutDashboard,
  ListOrdered,
  Percent,
  Receipt,
  Settings,
  Tag,
  Users,
} from "lucide-react"

import { SidebarDoPainel, type ItemDeMenu } from "@/components/navegacao/sidebar-do-painel"
import { CabecalhoDoPainel } from "@/components/navegacao/cabecalho-do-painel"
import { exigirAdminDaPlataforma } from "@/modules/auth/sessao"

const MENU: ItemDeMenu[] = [
  { rotulo: "Dashboard", href: "/admin", icone: LayoutDashboard },
  { rotulo: "Restaurantes", href: "/admin/restaurantes", icone: Building2 },
  { rotulo: "Usuários", href: "/admin/usuarios", icone: Users },
  { rotulo: "Entregadores", href: "/admin/entregadores", icone: Bike },
  { rotulo: "Pedidos", href: "/admin/pedidos", icone: Receipt },
  { rotulo: "Financeiro", href: "/admin/financeiro", icone: DollarSign },
  { rotulo: "Comissões", href: "/admin/comissoes", icone: Percent },
  { rotulo: "Cupons", href: "/admin/cupons", icone: Tag },
  { rotulo: "Banners", href: "/admin/banners", icone: ImageIcon },
  { rotulo: "Categorias", href: "/admin/categorias", icone: ListOrdered },
  { rotulo: "Relatórios", href: "/admin/relatorios", icone: BarChart3 },
  { rotulo: "Configurações", href: "/admin/configuracoes", icone: Settings },
]

export default async function LayoutDaAdministracao({ children }: LayoutProps<"/admin">) {
  const contexto = await exigirAdminDaPlataforma()

  return (
    <div className="flex min-h-dvh bg-muted/40">
      <SidebarDoPainel itens={MENU} legenda="Painel Administrativo" />

      <div className="flex min-w-0 flex-1 flex-col">
        <CabecalhoDoPainel
          titulo="Administração da plataforma"
          nomeDoUsuario={contexto.perfil.full_name || contexto.email || ""}
        />
        <main className="flex-1 p-4 md:p-6">{children}</main>
      </div>
    </div>
  )
}
