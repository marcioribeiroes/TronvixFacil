import type { Metadata } from "next"
import { notFound } from "next/navigation"

import { PagarComPix } from "@/components/cliente/pagar-com-pix"
import { Check } from "lucide-react"

import { formatarReais } from "@/lib/dinheiro"
import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirUsuario } from "@/modules/auth/sessao"
import { ROTULO_DA_SITUACAO, type SituacaoDoPedido } from "@/modules/pedidos/maquina-de-estados"

export const metadata: Metadata = { title: "Acompanhar pedido" }

const ETAPAS_DE_ENTREGA = [
  "Pedido enviado",
  "Restaurante aceitou",
  "Em preparo",
  "Pronto",
  "Saiu para entrega",
  "Entregue",
]

const ETAPAS_DE_RETIRADA = [
  "Pedido enviado",
  "Restaurante aceitou",
  "Em preparo",
  "Pronto para retirar",
  "Retirado",
]

function etapaAtual(situacao: SituacaoDoPedido, retirada: boolean) {
  const mapa: Partial<Record<SituacaoDoPedido, number>> = {
    awaiting_payment: 0,
    received: 0,
    confirmed: 1,
    preparing: 2,
    ready: 3,
    out_for_delivery: 4,
  }
  return mapa[situacao] ?? (retirada ? 4 : 5)
}

export default async function PaginaDoPedido({ params }: PageProps<"/pedidos/[id]">) {
  const { id } = await params
  await exigirUsuario(`/pedidos/${id}`)
  const supabase = await criarClienteDoServidor()

  const { data: pedido } = await supabase
    .from("orders")
    .select(
      "id, number, status, fulfillment, customer_name, address_summary, address_district, notes, subtotal_cents, delivery_fee_cents, discount_cents, total_cents, coupon_code, created_at, restaurants(name), order_items(id, product_name, quantity, total_cents, order_item_addons(addon_name)), payments(method, timing, status, change_for_cents, pix_qr_code), deliveries(status)",
    )
    .eq("id", id)
    .maybeSingle()

  // A RLS ja recorta: `pedido visivel a quem participa dele`. Nulo aqui
  // significa "nao e seu", e 404 e a resposta que nao conta nada a mais.
  if (!pedido) notFound()

  const situacao = pedido.status as SituacaoDoPedido
  const retirada = pedido.fulfillment === "pickup"
  const encerradoMal = situacao === "cancelled" || situacao === "rejected"
  const etapas = retirada ? ETAPAS_DE_RETIRADA : ETAPAS_DE_ENTREGA
  const atual = etapaAtual(situacao, retirada)

  // O Pix ainda não confirmado é a única coisa entre o cliente e a cozinha.
  // Por isso vem antes da trilha de etapas, e não escondido no rodapé.
  const pagamento = pedido.payments?.[0]
  const pixPendente =
    situacao === "awaiting_payment" &&
    pagamento?.method === "pix" &&
    pagamento.status !== "paid" &&
    Boolean(pagamento.pix_qr_code)

  return (
    <div className="mx-auto max-w-2xl px-4 py-6">
      <h1 className="text-sm font-semibold text-muted-foreground">
        Pedido nº {pedido.number} · {pedido.restaurants?.name}
      </h1>
      <p className="mt-1 text-2xl font-bold tracking-tight">
        {ROTULO_DA_SITUACAO[situacao]}
      </p>

      {pixPendente ? (
        <div className="mt-6">
          <PagarComPix
            codigo={pagamento!.pix_qr_code!}
            centavos={pedido.total_cents}
            numero={pedido.number}
          />
        </div>
      ) : null}

      {encerradoMal ? (
        <p className="mt-4 rounded-lg bg-marca-suave px-4 py-3 text-sm text-marca-forte">
          Este pedido não seguiu adiante.
        </p>
      ) : (
        <ol className="mt-6 space-y-3">
          {etapas.map((etapa, i) => (
            <li key={etapa} className="flex items-center gap-3">
              <span
                className={`flex size-5 items-center justify-center rounded-full border-2 ${
                  i <= atual ? "border-marca bg-marca text-white" : "border-border"
                }`}
                aria-hidden="true"
              >
                {i < atual ? <Check className="size-3" /> : null}
              </span>
              <span className={i === atual ? "font-bold" : i < atual ? "" : "text-muted-foreground"}>
                {etapa}
              </span>
            </li>
          ))}
        </ol>
      )}

      {pedido.fulfillment === "delivery" && pedido.address_summary ? (
        <p className="mt-6 text-sm text-muted-foreground">
          Entregar em {pedido.address_summary}
          {pedido.address_district ? `, ${pedido.address_district}` : ""}
        </p>
      ) : null}

      <section className="mt-6">
        <h2 className="text-sm font-bold uppercase tracking-wide text-muted-foreground">
          Itens
        </h2>
        <ul className="mt-2 divide-y rounded-xl border bg-card">
          {pedido.order_items.map((i) => (
            <li key={i.id} className="flex items-start gap-3 p-3 text-sm">
              <span className="font-bold text-marca">{i.quantity}×</span>
              <span className="flex-1">
                {i.product_name}
                {i.order_item_addons.map((a) => (
                  <span key={a.addon_name} className="block text-muted-foreground">
                    + {a.addon_name}
                  </span>
                ))}
              </span>
              <span>{formatarReais(i.total_cents)}</span>
            </li>
          ))}
        </ul>
      </section>

      <dl className="mt-4 space-y-1.5 rounded-xl border bg-card p-4 text-sm">
        <div className="flex justify-between">
          <dt className="text-muted-foreground">Subtotal</dt>
          <dd>{formatarReais(pedido.subtotal_cents)}</dd>
        </div>
        <div className="flex justify-between">
          <dt className="text-muted-foreground">Entrega</dt>
          <dd>
            {pedido.delivery_fee_cents === 0
              ? "Grátis"
              : formatarReais(pedido.delivery_fee_cents)}
          </dd>
        </div>
        {pedido.discount_cents > 0 ? (
          <div className="flex justify-between text-status-pronto">
            <dt>Cupom {pedido.coupon_code}</dt>
            <dd>− {formatarReais(pedido.discount_cents)}</dd>
          </div>
        ) : null}
        <div className="flex justify-between border-t pt-2 text-base font-bold">
          <dt>Total</dt>
          <dd>{formatarReais(pedido.total_cents)}</dd>
        </div>
      </dl>
    </div>
  )
}
