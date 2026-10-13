import type { Metadata } from "next"
import Link from "next/link"
import { notFound } from "next/navigation"

import { Button } from "@/components/ui/button"
import { EditorDoPedido } from "@/components/painel/editor-do-pedido"
import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirVinculo } from "@/modules/auth/sessao"
import { carregarCardapio } from "@/modules/cardapio/carregar"
import { pedidoEditavel } from "@/modules/pedidos/edicao"
import { ROTULO_DO_TIPO, type TipoDeEntrega } from "@/modules/pedidos/maquina-de-estados"

export const metadata: Metadata = { title: "Editar pedido" }

export default async function PaginaDeEditarPedido({
  params,
}: PageProps<"/painel/pedidos/[id]/editar">) {
  const { id } = await params
  const { vinculo } = await exigirVinculo()
  const supabase = await criarClienteDoServidor()

  const { data: pedido } = await supabase
    .from("orders")
    .select(
      "id, number, status, fulfillment, table_label, customer_name, delivery_fee_cents, discount_cents, restaurant_id, order_items(id, product_name, quantity, unit_price_cents, addons_total_cents, notes, created_at, order_item_addons(addon_name)), payments(timing, status)",
    )
    .eq("id", id)
    .eq("restaurant_id", vinculo.restauranteId)
    .maybeSingle()

  if (!pedido) notFound()

  const destino =
    pedido.fulfillment === "dine_in"
      ? (pedido.table_label ?? "Mesa")
      : ROTULO_DO_TIPO[pedido.fulfillment as TipoDeEntrega]

  const cabecalho = (
    <div>
      <h1 className="text-2xl font-bold tracking-tight">Editar pedido nº {pedido.number}</h1>
      <p className="mt-1 text-sm text-muted-foreground">
        {pedido.customer_name} · {destino}. Mude quantidades, tire ou acrescente itens — a conta,
        o estoque e o valor a receber são refeitos ao salvar.
      </p>
    </div>
  )

  if (!pedidoEditavel(pedido.status, pedido.payments[0])) {
    return (
      <div className="space-y-6">
        {cabecalho}
        <p className="rounded-xl border border-dashed p-6 text-sm text-muted-foreground">
          Este pedido não pode mais ser alterado: ou já saiu, foi entregue ou cancelado, ou o
          pagamento já foi feito. Para vender mais ao mesmo cliente, faça um pedido novo.
        </p>
        <Button variant="outline" render={<Link href="/painel/pedidos" />}>
          Voltar aos pedidos
        </Button>
      </div>
    )
  }

  const { secoes, grupos } = await carregarCardapio(vinculo.restauranteId)

  const itens = [...pedido.order_items]
    .sort((a, b) => a.created_at.localeCompare(b.created_at))
    .map((i) => ({
      id: i.id,
      nome: i.product_name,
      quantidade: i.quantity,
      unitarioCentavos: i.unit_price_cents,
      adicionaisCentavos: i.addons_total_cents,
      adicionais: i.order_item_addons.map((a) => a.addon_name),
      observacao: i.notes,
    }))

  return (
    <div className="space-y-6">
      {cabecalho}
      <EditorDoPedido
        pedidoId={pedido.id}
        itens={itens}
        freteCentavos={pedido.delivery_fee_cents}
        descontoCentavos={pedido.discount_cents}
        secoes={secoes}
        grupos={grupos}
      />
    </div>
  )
}
