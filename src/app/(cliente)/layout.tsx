import Link from "next/link"
import { MapPin, Search, ShoppingCart } from "lucide-react"

import { BarraInferior } from "@/components/navegacao/barra-inferior"
import { LogoTronvixFacil } from "@/components/marca/logo"
import { Button } from "@/components/ui/button"
import { obterContexto } from "@/modules/auth/sessao"

/**
 * Moldura do aplicativo do cliente.
 *
 * Mobile-first: o cabecalho compacto com endereco e busca e o mesmo dos apps
 * de delivery, e a navegacao principal fica na barra inferior no celular. No
 * desktop a barra some e a navegacao sobe para o cabecalho.
 */
export default async function LayoutDoCliente({ children }: LayoutProps<"/">) {
  const contexto = await obterContexto()

  return (
    <div className="flex min-h-dvh flex-col">
      <header className="sticky top-0 z-40 border-b bg-background/95 backdrop-blur">
        <div className="mx-auto flex h-14 max-w-6xl items-center gap-3 px-4">
          <Link href="/" className="shrink-0">
            <LogoTronvixFacil tamanho="sm" className="hidden sm:inline-flex" />
            <span className="sm:hidden">
              <LogoTronvixFacil tamanho="sm" />
            </span>
          </Link>

          <button
            type="button"
            className="ml-auto flex min-w-0 items-center gap-1.5 rounded-md px-2 py-1.5 text-left text-sm transition-colors hover:bg-muted md:ml-4"
          >
            <MapPin className="size-4 shrink-0 text-marca" aria-hidden="true" />
            <span className="min-w-0">
              <span className="block text-[10px] uppercase tracking-wide text-muted-foreground">
                Entregar em
              </span>
              <span className="block truncate font-medium">
                {contexto ? "Escolher endereço" : "Informe seu endereço"}
              </span>
            </span>
          </button>

          <div className="hidden flex-1 md:block">
            <label className="relative block">
              <span className="sr-only">Buscar restaurantes e pratos</span>
              <Search
                className="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground"
                aria-hidden="true"
              />
              <input
                type="search"
                placeholder="Buscar restaurantes, lanches, pizzas..."
                className="h-9 w-full rounded-md border bg-muted/50 pl-9 pr-3 text-sm outline-none transition-colors focus-visible:border-ring focus-visible:bg-background"
              />
            </label>
          </div>

          <Button
            variant="ghost"
            size="icon"
            aria-label="Carrinho"
            render={<Link href="/carrinho" />}
          >
            <ShoppingCart className="size-5" />
          </Button>

          {contexto ? null : (
            <Button size="sm" className="hidden sm:inline-flex" render={<Link href="/entrar" />}>
              Entrar
            </Button>
          )}
        </div>
      </header>

      <main className="mx-auto w-full max-w-6xl flex-1 px-4 pb-24 pt-4 md:pb-10">{children}</main>

      {/* O convite ao restaurante mora no rodape da vitrine, e nao no
          cabecalho: quem abre esta tela veio para pedir comida. Mas o dono de
          restaurante tambem pede comida, e e aqui que ele descobre que da para
          vender por aqui. */}
      <footer className="border-t bg-muted/40">
        <div className="mx-auto flex max-w-6xl flex-col items-center gap-1 px-4 py-8 pb-28 text-center md:pb-8">
          <p className="text-sm font-semibold">Tem um restaurante?</p>
          <p className="text-xs text-muted-foreground">
            Sem mensalidade, com seus próprios entregadores.
          </p>
          <Link
            href="/cadastrar-restaurante"
            className="mt-3 rounded-md border bg-background px-5 py-2 text-sm font-semibold transition-colors hover:bg-muted"
          >
            Coloque no ar
          </Link>
        </div>
      </footer>

      <BarraInferior />
    </div>
  )
}
