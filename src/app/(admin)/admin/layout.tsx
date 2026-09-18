import { SidebarDoPainel, type ItemDeMenu } from "@/components/navegacao/sidebar-do-painel"
import { CabecalhoDoPainel } from "@/components/navegacao/cabecalho-do-painel"
import { exigirAdminDaPlataforma } from "@/modules/auth/sessao"

const MENU: ItemDeMenu[] = [
  { rotulo: "Dashboard", href: "/admin", icone: "dashboard" },
  { rotulo: "Restaurantes", href: "/admin/restaurantes", icone: "estabelecimentos" },
  { rotulo: "Usuários", href: "/admin/usuarios", icone: "usuarios" },
  { rotulo: "Entregadores", href: "/admin/entregadores", icone: "entregadores" },
  { rotulo: "Pedidos", href: "/admin/pedidos", icone: "pedidos" },
  { rotulo: "Financeiro", href: "/admin/financeiro", icone: "financeiro" },
  { rotulo: "Comissões", href: "/admin/comissoes", icone: "comissoes" },
  { rotulo: "Cupons", href: "/admin/cupons", icone: "cupons" },
  { rotulo: "Banners", href: "/admin/banners", icone: "banners" },
  { rotulo: "Categorias", href: "/admin/categorias", icone: "categorias" },
  { rotulo: "Relatórios", href: "/admin/relatorios", icone: "relatorios" },
  { rotulo: "Configurações", href: "/admin/configuracoes", icone: "configuracoes" },
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
