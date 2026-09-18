import type { Metadata } from "next"

import { ChaveDaLoja } from "@/components/painel/chave-da-loja"
import { FilaDePedidos, type PedidoDaFila } from "@/components/painel/fila-de-pedidos"
import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { formatarReais } from "@/lib/dinheiro"
import { exigirVinculo } from "@/modules/auth/sessao"
import type { SituacaoDoPedido } from "@/modules/pedidos/maquina-de-estados"

export const metadata: Metadata = { title: "Pedidos" }

/** Os estados em que o pedido ainda pede alguma coisa de alguem. */
const ABERTOS = [
  // "aguardando pagamento" entra na fila de propósito: é o Pix que o cliente
  // ainda não pagou, e alguém da loja precisa VER para confirmar. Fora daqui,
  // o pedido ficava invisível e parado para sempre.
  "awaiting_payment",
  "received",
  "confirmed",
  "preparing",
  "ready",
  "out_for_delivery",
] as const satisfies readonly SituacaoDoPedido[]

export default async function PaginaDePedidos() {
  const { vinculo } = await exigirVinculo()
  const supabase = await criarClienteDoServidor()

  const meiaNoite = new Date()
  meiaNoite.setHours(0, 0, 0, 0)

  const [{ data: abertos }, { data: doDia }, { data: loja }] = await Promise.all([
    supabase
      .from("orders")
      .select(
        "id, number, status, fulfillment, table_label, customer_name, customer_phone, address_summary, address_district, notes, total_cents, created_at, order_items(id, product_name, quantity, notes), payments(method, timing, status)",
      )
      .eq("restaurant_id", vinculo.restauranteId)
      .in("status", ABERTOS)
      .order("created_at"),
    supabase
      .from("orders")
      .select("total_cents, status")
      .eq("restaurant_id", vinculo.restauranteId)
      .gte("created_at", meiaNoite.toISOString()),
    supabase
      .from("restaurants")
      .select("id, name, is_open, no_horario")
      .eq("id", vinculo.restauranteId)
      .single(),
  ])

  const valendo = (doDia ?? []).filter(
    (p) => p.status !== "cancelled" && p.status !== "rejected",
  )
  const faturado = valendo.reduce((soma, p) => soma + p.total_cents, 0)

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold tracking-tight">Pedidos</h1>
          <p className="mt-1 text-sm text-muted-foreground">
            A fila da cozinha. Pedido que entra aparece aqui sozinho.
          </p>
        </div>

        {loja ? (
          <ChaveDaLoja
            aberta={loja.is_open}
            noHorario={loja.no_horario !== false}
            podeMexer={vinculo.cargo !== "staff"}
          />
        ) : null}
      </div>

      <dl className="grid grid-cols-3 gap-3 rounded-xl border bg-muted/40 p-4">
        <div>
          <dt className="text-xs font-semibold uppercase text-muted-foreground">Hoje</dt>
          <dd className="text-xl font-bold">{valendo.length}</dd>
        </div>
        <div>
          <dt className="text-xs font-semibold uppercase text-muted-foreground">Faturado</dt>
          <dd className="text-xl font-bold">{formatarReais(faturado)}</dd>
        </div>
        <div>
          <dt className="text-xs font-semibold uppercase text-muted-foreground">Em aberto</dt>
          <dd className="text-xl font-bold">{abertos?.length ?? 0}</dd>
        </div>
      </dl>

      <FilaDePedidos
        pedidos={(abertos ?? []) as PedidoDaFila[]}
        restauranteId={vinculo.restauranteId}
        chavePublicaDePush={process.env.NEXT_PUBLIC_VAPID_CHAVE_PUBLICA ?? ""}
      />
    </div>
  )
}
