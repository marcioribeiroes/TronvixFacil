import { NextResponse, type NextRequest } from "next/server"

import { COOKIE_DA_MESA, mesaPeloCodigo } from "@/modules/cliente/mesa"

/**
 * O destino do QR Code da mesa.
 *
 * Endereco curto de proposito - /m/abc23xyz. Quanto menos caracteres, menos
 * denso o QR, e mais facil a camera ler numa mesa com luz baixa.
 *
 * E um Route Handler, e nao uma pagina, porque precisa GRAVAR o cookie da
 * mesa: no Next, Server Component so le cookie - quem escreve e Route Handler
 * ou Server Action. Uma pagina aqui lanca "Cookies can only be modified in a
 * Server Action or Route Handler", a mesa nao gruda, e o pedido chega a cozinha
 * sem dizer para onde levar.
 *
 * Nao pede login: quem acabou de sentar quer ver o cardapio. A conta so faz
 * falta na hora de fechar o pedido.
 */

const QUATRO_HORAS = 60 * 60 * 4

export async function GET(
  pedido: NextRequest,
  { params }: { params: Promise<{ codigo: string }> },
) {
  const { codigo } = await params
  const mesa = await mesaPeloCodigo(codigo)

  if (!mesa) {
    return NextResponse.redirect(new URL("/mesa-nao-encontrada", pedido.url))
  }

  const resposta = NextResponse.redirect(
    new URL(`/restaurante/${mesa.restauranteSlug}`, pedido.url),
  )

  resposta.cookies.set(COOKIE_DA_MESA, mesa.codigo, {
    maxAge: QUATRO_HORAS,
    httpOnly: true,
    sameSite: "lax",
    path: "/",
  })

  return resposta
}
