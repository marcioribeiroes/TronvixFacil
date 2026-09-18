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
  { rotulo: "Dashboard", href: "/painel", icone: "dashboard" },
  { rotulo: "Pedidos", href: "/painel/pedidos", icone: "comanda" },
  { rotulo: "Cardápio", href: "/painel/cardapio", icone: "cardapio" },
  { rotulo: "Categorias", href: "/painel/categorias", icone: "categorias" },
  { rotulo: "Produtos", href: "/painel/produtos", icone: "produtos" },
  { rotulo: "Adicionais", href: "/painel/adicionais", icone: "adicionais" },
  { rotulo: "Mesas", href: "/painel/mesas", icone: "mesas" },
  { rotulo: "Promoções", href: "/painel/promocoes", icone: "cupons" },
  { rotulo: "Clientes", href: "/painel/clientes", icone: "usuarios" },
  { rotulo: "Entregas", href: "/painel/entregas", icone: "entregadores" },
  { rotulo: "Relatórios", href: "/painel/relatorios", icone: "relatorios" },
  { rotulo: "Configurações", href: "/painel/configuracoes", icone: "configuracoes" },
]

/**
 * Atendente ve so o que precisa para tocar o turno. Esconder o resto nao e
 * seguranca - quem garante isso e a RLS e o exigirGestao de cada pagina -, e
 * sim nao oferecer botao que a pessoa nao pode usar.
 */
const MENU_DO_ATENDENTE: ItemDeMenu[] = MENU_DA_GESTAO.filter((item) =>
  ["/painel", "/painel/pedidos", "/painel/cardapio", "/painel/entregas", "/painel/mesas"].includes(
    item.href,
  ),
)

export default async function LayoutDoPainel({ children }: LayoutProps<"/painel">) {
  const { contexto, vinculo } = await exigirVinculo()
  const ehGestao = vinculo.cargo === "owner" || vinculo.cargo === "manager"

  return (
    <div className="flex min-h-dvh bg-muted/40 print:block print:bg-white">
      <div className="contents print:hidden">
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
      </div>

      <div className="flex min-w-0 flex-1 flex-col">
        <div className="print:hidden">
          <CabecalhoDoPainel
            titulo={vinculo.nome}
            nomeDoUsuario={contexto.perfil.full_name || contexto.email || ""}
          />
        </div>
        <main className="flex-1 p-4 md:p-6 print:p-0">{children}</main>
      </div>
    </div>
  )
}
