import Link from "next/link"

import { LogoTronvixFacil } from "@/components/marca/logo"

/**
 * Moldura do cadastro de estabelecimento.
 *
 * Nao usa a moldura de autenticacao: aquela e uma coluna estreita, boa para
 * quatro campos, e este formulario tem quinze. Aqui a marca fica numa faixa no
 * topo e o espaco vai todo para o formulario.
 */
export default function LayoutDoParceiro({ children }: LayoutProps<"/"> ) {
  return (
    <div className="flex min-h-dvh flex-col bg-muted/40">
      <header className="border-b bg-carvao">
        <div className="mx-auto flex h-16 max-w-3xl items-center justify-between px-5">
          <Link href="/">
            <LogoTronvixFacil tamanho="sm" legenda="Para restaurantes" escuro />
          </Link>
          <Link
            href="/entrar"
            className="text-sm font-semibold text-white/70 transition-colors hover:text-white"
          >
            Entrar
          </Link>
        </div>
      </header>

      <main className="mx-auto w-full max-w-3xl flex-1 px-5 py-8 sm:py-12">{children}</main>
    </div>
  )
}
