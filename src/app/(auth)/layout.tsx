import Link from "next/link"

import { LogoTronvixFacil, SLOGAN } from "@/components/marca/logo"

/**
 * Moldura das telas de autenticacao.
 *
 * Duas colunas no desktop: a esquerda vende a plataforma, a direita resolve a
 * tarefa. No celular a coluna de apresentacao encolhe para uma faixa - quem
 * abre o app para entrar nao precisa ser convencido de novo, mas precisa saber
 * onde esta.
 *
 * O painel escuro segue o tratamento do login do TronvixERP: gradiente em
 * camadas, malha de pontos e os dois riscos diagonais. As cores saem dos tokens
 * da marca (--marca, --carvao), nao de valores soltos - trocar a marca no
 * globals.css troca esta tela junto.
 */
export default function LayoutDeAutenticacao({ children }: LayoutProps<"/">) {
  return (
    <div className="grid min-h-dvh lg:grid-cols-[minmax(0,0.85fr)_minmax(0,1fr)]">
      <aside className="relative flex flex-col overflow-hidden bg-carvao px-7 py-8 text-white lg:justify-between lg:px-12 lg:py-12">
        {/* Camadas do fundo. Puramente decorativas: nenhuma carrega informacao,
            e todas somem para quem le com leitor de tela. */}
        <div
          aria-hidden="true"
          className="pointer-events-none absolute inset-0"
          style={{
            background: [
              "linear-gradient(112deg, transparent 42%, rgba(255,255,255,0.04) 42.2%, transparent 60%)",
              "linear-gradient(100deg, transparent 66%, rgba(0,0,0,0.42) 66.2%)",
              "linear-gradient(75deg, transparent 78%, rgba(255,255,255,0.028) 78.2%)",
              "radial-gradient(ellipse 70% 45% at 20% 44%, rgba(225,29,47,0.28), transparent 70%)",
              "radial-gradient(circle at 90% 4%, rgba(225,29,47,0.15), transparent 42%)",
              "linear-gradient(158deg, var(--carvao-claro) 0%, var(--carvao) 52%, #0b0b0d 100%)",
            ].join(", "),
          }}
        />

        {/* Malha de pontos */}
        <div
          aria-hidden="true"
          className="pointer-events-none absolute right-[8%] top-[26%] hidden h-48 w-32 opacity-60 lg:block"
          style={{
            backgroundImage:
              "radial-gradient(rgba(225,29,47,0.4) 1.4px, transparent 1.4px), radial-gradient(rgba(255,255,255,0.12) 1.4px, transparent 1.4px)",
            backgroundPosition: "0 0, 10px 10px",
            backgroundSize: "20px 20px, 20px 20px",
          }}
        />

        {/* Os dois riscos. O de cima e o gesto da marca; o de baixo e o eco. */}
        <div
          aria-hidden="true"
          className="pointer-events-none absolute -left-[20%] -right-[20%] bottom-0 top-0 hidden lg:block"
        >
          <span
            className="absolute left-0 right-0 top-[76%] h-0.5 -rotate-[17deg]"
            style={{
              background:
                "linear-gradient(90deg, transparent, var(--marca-forte) 40%, var(--marca) 60%, transparent)",
              boxShadow: "0 0 30px 6px rgba(225,29,47,0.4)",
            }}
          />
          <span
            className="absolute left-0 right-0 top-[89%] h-px -rotate-[17deg]"
            style={{
              background:
                "linear-gradient(90deg, transparent, rgba(225,29,47,0.35), transparent)",
              boxShadow: "0 0 18px 3px rgba(225,29,47,0.18)",
            }}
          />
        </div>

        {/* Fio vertical na divisa das duas colunas */}
        <div
          aria-hidden="true"
          className="pointer-events-none absolute right-0 top-[8%] hidden h-[62%] w-0.5 lg:block"
          style={{
            background:
              "linear-gradient(180deg, transparent, var(--marca) 45%, transparent)",
          }}
        />

        <Link href="/" className="relative z-10 w-fit">
          <LogoTronvixFacil tamanho="md" escuro />
        </Link>

        {/* Risco curto sob a marca, como no ERP */}
        <div
          aria-hidden="true"
          className="relative z-10 mt-5 h-[3px] w-16 lg:mt-6"
          style={{
            background: "linear-gradient(90deg, var(--marca), rgba(225,29,47,0))",
          }}
        />

        <div className="relative z-10 mt-6 max-w-md lg:my-auto">
          <p className="text-[11px] font-extrabold uppercase tracking-[0.28em] text-marca lg:text-xs">
            {SLOGAN}
          </p>
          <h2 className="mt-4 text-2xl font-bold leading-[1.08] tracking-[-0.038em] lg:text-[2.35rem]">
            Do primeiro clique à porta do cliente.
          </h2>
          <p className="mt-4 max-w-sm text-sm leading-relaxed text-white/55">
            Cardápio, pedidos, entrega e relatórios no mesmo lugar — para
            restaurantes, lanchonetes, pizzarias e açaiterias.
          </p>

          <ul className="mt-9 hidden space-y-3 text-sm text-white/65 lg:block">
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

        <p className="relative z-10 mt-8 hidden text-[9px] uppercase tracking-[0.12em] text-white/30 lg:block">
          Tronvix Fácil <span className="px-2 text-marca">•</span> Acesso seguro
        </p>
      </aside>

      <main className="flex items-center justify-center px-5 py-10 lg:px-10">
        <div className="w-full max-w-sm">{children}</div>
      </main>
    </div>
  )
}
