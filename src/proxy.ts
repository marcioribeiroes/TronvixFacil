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

  const caminho = request.nextUrl.pathname

  // O link de "esqueci minha senha" chega aqui com um codigo de uso unico
  // (?code=, fluxo PKCE do @supabase/ssr) ou, se o modelo de e-mail for
  // trocado, com ?token_hash=&type=recovery. Alguem precisa trocar isso por
  // uma sessao - sem ela, gravar a senha nova falha com "Auth session
  // missing!". O proxy e o unico lugar que pode gravar o cookie, entao a troca
  // e feita aqui, e a pessoa segue para a mesma tela com a URL limpa.
  if (caminho === "/nova-senha") {
    const codigo = request.nextUrl.searchParams.get("code")
    const tokenHash = request.nextUrl.searchParams.get("token_hash")

    if (codigo || tokenHash) {
      const { error } = codigo
        ? await supabase.auth.exchangeCodeForSession(codigo)
        : await supabase.auth.verifyOtp({ token_hash: tokenHash!, type: "recovery" })

      const destino = request.nextUrl.clone()
      destino.search = ""
      if (error) {
        // Link vencido, ja usado, ou aberto em outro navegador (o PKCE guarda
        // a outra metade do codigo num cookie de quem pediu a recuperacao).
        destino.pathname = "/recuperar-senha"
        destino.searchParams.set("link", "invalido")
      }

      const redirecionamento = NextResponse.redirect(destino)
      for (const cookie of resposta.cookies.getAll()) {
        redirecionamento.cookies.set(cookie)
      }
      return redirecionamento
    }
  }

  // getUser() valida o token no servidor do Supabase. getSession() apenas le o
  // cookie, que o navegador pode ter adulterado - por isso nao serve para
  // decidir acesso.
  const {
    data: { user },
  } = await supabase.auth.getUser()
  // A comparacao e por SEGMENTO, nao por prefixo de texto. "/conta-apagada"
  // comeca com "/conta" e nao tem nada com a area do cliente: quem chega la
  // acabou de apagar a conta e nao tem mais sessao — mandar essa pessoa para o
  // login e dizer que deu errado quando deu certo.
  const area = AREAS_PROTEGIDAS.find(
    (a) => caminho === a.prefixo || caminho.startsWith(`${a.prefixo}/`),
  )

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
