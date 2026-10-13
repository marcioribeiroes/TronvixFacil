"use client"

import { useRouter } from "next/navigation"

import {
  ListaDoCardapio,
  type Grupo,
  type Secao,
} from "@/components/pedido/cardapio-para-escolher"
import { adicionarAoCarrinho } from "@/modules/cliente/carrinho"

/** O cardapio da loja para quem vai pedir: cada escolha vai para o carrinho. */
export function CardapioDoCliente({
  restauranteId,
  aberto,
  secoes,
  grupos,
}: {
  restauranteId: string
  aberto: boolean
  secoes: Secao[]
  grupos: Grupo[]
}) {
  const router = useRouter()

  return (
    <ListaDoCardapio
      secoes={secoes}
      grupos={grupos}
      bloqueio={aberto ? undefined : "Fechado agora"}
      aoEscolher={async (e) => {
        const r = await adicionarAoCarrinho({
          restauranteId,
          produtoId: e.produto.id,
          quantidade: e.quantidade,
          adicionais: e.adicionais,
          observacao: e.observacao,
        })
        if (r.ok) router.refresh()
        return r
      }}
    />
  )
}
