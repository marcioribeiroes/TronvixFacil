import { createServerClient } from "@supabase/ssr"
import { NextResponse, type NextRequest } from "next/server"

/**
 * Proxy de sessao e porteiro das rotas.
 *
 * No Next.js 16 o arquivo `middleware.ts` foi renomeado para `proxy.ts` e a
 * funcao exportada passou a se chamar `proxy`. O comportamento e o mesmo:
 * roda antes de qualquer rota ser renderizada.
 *
 * Duas responsabilidades, nesta ordem:
 *
 *   1. Renovar o token do Supabase e devolver os cookies atualizados. E o
 *      unico lugar do projeto que pode gravar esses cookies; por isso os
 *      componentes de servidor ignoram falhas de escrita.
 *
 *   2. Barrar o acesso a area errada ANTES da renderizacao. O porteiro aqui e
 *      conveniencia e defesa em profundidade, nao a garantia: quem realmente
 *      impede alguem de ler dados de outro estabelecimento e a RLS no banco.
 *      Se este arquivo sumisse, nenhum dado vazaria - apenas apareceriam
 *      telas vazias em vez de um redirecionamento limpo.
 */

/** Prefixos que exigem sessao, com o papel que a area espera. */
const AREAS_PROTEGIDAS = [
  { prefixo: "/painel", area: "restaurante" },
  { prefixo: "/entregas", area: "entregador" },
  { prefixo: "/admin", area: "admin" },
  { prefixo: "/conta", area: "cliente" },
  { prefixo: "/checkout", area: "cliente" },
] as const

/** Rotas de autenticacao: quem ja esta logado nao precisa ve-las. */
const ROTAS_DE_ENTRADA = ["/entrar", "/criar-conta"]

export async function proxy(request: NextRequest) {
  let resposta = NextResponse.next({ request })

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL
  const chave = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY

  // Sem Supabase configurado o projeto ainda sobe: as telas explicam o que
  // falta em vez de quebrarem com um erro de chave invalida.
  if (!url || !chave) return resposta

  const supabase = createServerClient(url, chave, {
    cookies: {
      getAll() {
        return request.cookies.getAll()
      },
      setAll(cookiesParaGravar) {
        for (const { name, value } of cookiesParaGravar) {
          request.cookies.set(name, value)
        }
        resposta = NextResponse.next({ request })
        for (const { name, value, options } of cookiesParaGravar) {
          resposta.cookies.set(name, value, options)
        }
      },
    },
  })

  // getUser() valida o token no servidor do Supabase. getSession() apenas le o
  // cookie, que o navegador pode ter adulterado - por isso nao serve para
  // decidir acesso.
  const {
    data: { user },
  } = await supabase.auth.getUser()

  const caminho = request.nextUrl.pathname
  const area = AREAS_PROTEGIDAS.find((a) => caminho.startsWith(a.prefixo))

  if (area && !user) {
    const destino = request.nextUrl.clone()
    destino.pathname = "/entrar"
    // Preserva para onde a pessoa queria ir: depois de entrar, ela volta a
    // tela que pediu, em vez de cair na home e ter de navegar de novo.
    destino.searchParams.set("voltar_para", caminho + request.nextUrl.search)
    return NextResponse.redirect(destino)
  }

  if (user && ROTAS_DE_ENTRADA.includes(caminho)) {
    const destino = request.nextUrl.clone()
    destino.pathname = "/"
    destino.search = ""
    return NextResponse.redirect(destino)
  }

  return resposta
}

export const config = {
  // Sem este filtro o proxy rodaria tambem em CSS, JS e imagens, gastando uma
  // chamada de validacao de sessao por arquivo estatico.
  matcher: [
    "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp|ico|woff2?)$).*)",
  ],
}
