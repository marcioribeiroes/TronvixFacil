import {
  BarChart3,
  Bike,
  ClipboardList,
  LayoutDashboard,
  ListOrdered,
  Package,
  PlusSquare,
  Settings,
  Tag,
  Users,
  UtensilsCrossed,
} from "lucide-react"

import { SidebarDoPainel, type ItemDeMenu } from "@/components/navegacao/sidebar-do-painel"
import { CabecalhoDoPainel } from "@/components/navegacao/cabecalho-do-painel"
import { exigirVinculo } from "@/modules/auth/sessao"

/**
 * Moldura do painel do restaurante.
 *
 * O layout resolve o vinculo uma vez e o repassa; nenhuma pagina filha precisa
 * perguntar de novo quem e o usuario. exigirVinculo redireciona quem nao
 * trabalha em estabelecimento nenhum, entao daqui para baixo o vinculo e
 * garantido.
 */

const MENU_DA_GESTAO: ItemDeMenu[] = [
  { rotulo: "Dashboard", href: "/painel", icone: LayoutDashboard },
  { rotulo: "Pedidos", href: "/painel/pedidos", icone: ClipboardList },
  { rotulo: "Cardápio", href: "/painel/cardapio", icone: UtensilsCrossed },
  { rotulo: "Categorias", href: "/painel/categorias", icone: ListOrdered },
  { rotulo: "Produtos", href: "/painel/produtos", icone: Package },
  { rotulo: "Adicionais", href: "/painel/adicionais", icone: PlusSquare },
  { rotulo: "Promoções", href: "/painel/promocoes", icone: Tag },
  { rotulo: "Clientes", href: "/painel/clientes", icone: Users },
  { rotulo: "Entregas", href: "/painel/entregas", icone: Bike },
  { rotulo: "Relatórios", href: "/painel/relatorios", icone: BarChart3 },
  { rotulo: "Configurações", href: "/painel/configuracoes", icone: Settings },
]

/**
 * Atendente ve so o que precisa para tocar o turno. Esconder o resto nao e
 * seguranca - quem garante isso e a RLS e o exigirGestao de cada pagina -, e
 * sim nao oferecer botao que a pessoa nao pode usar.
 */
const MENU_DO_ATENDENTE: ItemDeMenu[] = MENU_DA_GESTAO.filter((item) =>
  ["/painel", "/painel/pedidos", "/painel/cardapio", "/painel/entregas"].includes(item.href),
)

export default async function LayoutDoPainel({ children }: LayoutProps<"/painel">) {
  const { contexto, vinculo } = await exigirVinculo()
  const ehGestao = vinculo.cargo === "owner" || vinculo.cargo === "manager"

  return (
    <div className="flex min-h-dvh bg-muted/40">
      <SidebarDoPainel
        itens={ehGestao ? MENU_DA_GESTAO : MENU_DO_ATENDENTE}
        legenda="Painel do Restaurante"
        rodape={
          <div className="mx-3 mb-2 rounded-md bg-sidebar-accent px-3 py-2.5">
            <p className="truncate text-sm font-semibold text-white">{vinculo.nome}</p>
            <p className="text-[11px] text-white/50">
              {vinculo.cargo === "owner"
                ? "Proprietário"
                : vinculo.cargo === "manager"
                  ? "Gerente"
                  : "Atendente"}
            </p>
          </div>
        }
      />

      <div className="flex min-w-0 flex-1 flex-col">
        <CabecalhoDoPainel
          titulo={vinculo.nome}
          nomeDoUsuario={contexto.perfil.full_name || contexto.email || ""}
        />
        <main className="flex-1 p-4 md:p-6">{children}</main>
      </div>
    </div>
  )
}
