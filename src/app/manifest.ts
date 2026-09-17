import type { MetadataRoute } from "next"

/**
 * Manifesto PWA do aplicativo do cliente.
 *
 * Instalar na tela inicial importa aqui: quem pede comida volta, e o atalho
 * poupa a pessoa de abrir o navegador e digitar o endereco toda vez.
 */
export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "Tronvix Fácil",
    short_name: "Tronvix Fácil",
    description: "Seu pedido na palma da mão.",
    start_url: "/",
    display: "standalone",
    background_color: "#ffffff",
    theme_color: "#e11d2f",
    lang: "pt-BR",
    categories: ["food", "shopping"],
    icons: [
      { src: "/icone.svg", sizes: "any", type: "image/svg+xml", purpose: "any" },
    ],
  }
}
