import type { Metadata, Viewport } from "next"
import { Plus_Jakarta_Sans } from "next/font/google"
import { Toaster } from "@/components/ui/sonner"

import "./globals.css"

/**
 * Plus Jakarta Sans: geometrica, com peso forte nos titulos. Escolhida por
 * sustentar a hierarquia agressiva de preco e nome de produto que uma tela de
 * delivery exige, sem parecer um painel corporativo.
 */
const fonte = Plus_Jakarta_Sans({
  variable: "--font-sans",
  subsets: ["latin"],
  display: "swap",
})

export const metadata: Metadata = {
  title: {
    default: "Tronvix Fácil — Seu pedido na palma da mão",
    template: "%s · Tronvix Fácil",
  },
  description:
    "Plataforma de pedidos e entregas para restaurantes, lanchonetes, pizzarias e açaiterias.",
  applicationName: "Tronvix Fácil",
  manifest: "/manifest.webmanifest",
}

export const viewport: Viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#ffffff" },
    { media: "(prefers-color-scheme: dark)", color: "#09090b" },
  ],
  // O app do cliente e mobile-first e tem barra fixa embaixo; travar o zoom por
  // gesto evita o deslocamento acidental durante a rolagem do cardapio.
  width: "device-width",
  initialScale: 1,
  maximumScale: 5,
}

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="pt-BR" className={`${fonte.variable} h-full antialiased`}>
      <body className="flex min-h-full flex-col">
        {children}
        <Toaster position="top-center" richColors closeButton />
      </body>
    </html>
  )
}
