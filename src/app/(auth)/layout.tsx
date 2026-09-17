import Link from "next/link"

import { LogoTronvixFacil, SLOGAN } from "@/components/marca/logo"

/**
 * Moldura das telas de autenticacao.
 *
 * Duas colunas no desktop: a esquerda vende a plataforma, a direita resolve a
 * tarefa. No celular a coluna de apresentacao sai de cena - quem abre o app
 * para entrar nao precisa ser convencido de novo.
 */
export default function LayoutDeAutenticacao({ children }: LayoutProps<"/">) {
  return (
    <div className="grid min-h-dvh lg:grid-cols-2">
      <aside className="relative hidden overflow-hidden bg-carvao p-12 text-white lg:flex lg:flex-col lg:justify-between">
        {/* Brilho vermelho ao fundo, puramente decorativo */}
        <div
          aria-hidden="true"
          className="pointer-events-none absolute -right-24 -top-24 size-[28rem] rounded-full bg-marca/25 blur-3xl"
        />
        <div
          aria-hidden="true"
          className="pointer-events-none absolute -bottom-32 -left-20 size-[24rem] rounded-full bg-marca/10 blur-3xl"
        />

        <Link href="/" className="relative">
          <LogoTronvixFacil tamanho="md" escuro />
        </Link>

        <div className="relative max-w-md">
          <p className="text-sm font-semibold uppercase tracking-[0.2em] text-marca">
            {SLOGAN}
          </p>
          <h2 className="mt-4 text-4xl font-bold leading-tight tracking-tight">
            Do primeiro clique à porta do cliente.
          </h2>
          <p className="mt-4 text-white/60">
            Cardápio, pedidos, entrega e relatórios no mesmo lugar — para
            restaurantes, lanchonetes, pizzarias e açaiterias.
          </p>

          <ul className="mt-10 space-y-3 text-sm text-white/70">
            {[
              "Pedidos online com acompanhamento em tempo real",
              "Painel de produção em Kanban para a cozinha",
              "Pix, cartão e dinheiro, com troco calculado",
              "Entregadores, comissões e relatórios",
            ].map((item) => (
              <li key={item} className="flex items-start gap-3">
                <span className="mt-1.5 size-1.5 shrink-0 rounded-full bg-marca" />
                {item}
              </li>
            ))}
          </ul>
        </div>

        <p className="relative text-xs text-white/35">
          Tronvix Fácil — uma plataforma Tronvix.
        </p>
      </aside>

      <main className="flex items-center justify-center px-5 py-10">
        <div className="w-full max-w-sm">{children}</div>
      </main>
    </div>
  )
}
