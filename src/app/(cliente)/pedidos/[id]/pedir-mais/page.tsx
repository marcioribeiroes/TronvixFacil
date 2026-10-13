import type { Metadata } from "next"
import Link from "next/link"
import { notFound } from "next/navigation"

import { PedirMais } from "@/components/cliente/pedir-mais"
import { Button } from "@/components/ui/button"
import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirUsuario } from "@/modules/auth/sessao"
import { carregarCardapio } from "@/modules/cardapio/carregar"
import { pedidoEditavel } from "@/modules/pedidos/edicao"

export const metadata: Metadata = { title: "Pedir mais" }

export default async function PaginaDePedirMais({
  params,
}: PageProps<"/pedidos/[id]/pedir-mais">) {
  const { id } = await params
  await exigirUsuario(`/pedidos/${id}/pedir-mais`)
  const supabase = await criarClienteDoServidor()

  const { data: pedido } = await supabase
    .from("orders")
    .select("id, number, status, fulfillment, table_label, restaurant_id, restaurants(name, is_open), payments(timing, status)")
    .eq("id", id)
    .maybeSingle()

  // Pedido de outra pessoa nao aparece pela RLS; e so a mesa pede mais.
  if (!pedido || pedido.fulfillment !== "dine_in") notFound()

  const voltar = (
    <Button variant="outline" render={<Link href={`/pedidos/${pedido.id}`} />}>
      Voltar ao pedido
    </Button>
  )

  if (!pedidoEditavel(pedido.status, pedido.payments[0])) {
    return (
      <div className="mx-auto max-w-2xl space-y-4 px-4 py-6">
        <h1 className="text-2xl font-bold tracking-tight">Pedir mais</h1>
        <p className="text-muted-foreground">
          Este pedido já foi fechado. Para pedir mais, faça um pedido novo pelo QR Code da mesa.
        </p>
        {voltar}
      </div>
    )
  }

  const { secoes, grupos } = await carregarCardapio(pedido.restaurant_id)

  return (
    <div className="mx-auto max-w-2xl space-y-6 px-4 py-6">
      <div>
        <p className="text-sm font-semibold text-muted-foreground">
          {pedido.restaurants?.name} · {pedido.table_label ?? "Mesa"} · pedido nº {pedido.number}
        </p>
        <h1 className="text-2xl font-bold tracking-tight">Pedir mais</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          O que você escolher entra no mesmo pedido e na mesma conta.
        </p>
      </div>
      <PedirMais
        pedidoId={pedido.id}
        aberto={pedido.restaurants?.is_open ?? false}
        secoes={secoes}
        grupos={grupos}
      />
      {voltar}
    </div>
  )
}
