import type { NextConfig } from "next"

const configuracao: NextConfig = {
  // Fotos de produto e logo de estabelecimento sao servidas pelo Storage do
  // Supabase. O host entra aqui a partir da propria variavel de ambiente para
  // nao existir um dominio fixo no codigo.
  images: {
    remotePatterns: process.env.NEXT_PUBLIC_SUPABASE_URL
      ? [
          {
            protocol: "https",
            hostname: new URL(process.env.NEXT_PUBLIC_SUPABASE_URL).hostname,
            pathname: "/storage/v1/object/public/**",
          },
        ]
      : [],
  },

  // Cabecalhos de seguranca aplicados a todas as respostas.
  async headers() {
    return [
      {
        source: "/:caminho*",
        headers: [
          // Impede o navegador de "adivinhar" o tipo de um arquivo enviado
          // por um restaurante e trata-lo como script.
          { key: "X-Content-Type-Options", value: "nosniff" },
          { key: "X-Frame-Options", value: "DENY" },
          { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
          {
            key: "Permissions-Policy",
            // Geolocalizacao permanece liberada para a propria origem: o app do
            // cliente sugere endereco e o do entregador acompanha a corrida.
            value: "camera=(), microphone=(), geolocation=(self)",
          },
        ],
      },
    ]
  },
}

export default configuracao
