import type { Metadata } from "next"
import { notFound } from "next/navigation"

import { formatarReais } from "@/lib/dinheiro"
import { formatarTelefone } from "@/lib/telefone"
import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirVinculo } from "@/modules/auth/sessao"

export const metadata: Metadata = { title: "Comanda" }

/**
 * A comanda, para a impressora térmica.
 *
 * Página própria, e não um pedaço escondido do quadro: a impressão sai de um
 * iframe que carrega este endereço. Assim o que vai para o papel é exatamente
 * o que está aqui — sem herdar barra lateral, cabeçalho ou qualquer coisa que
 * o CSS de impressão do painel tivesse esquecido de esconder.
 *
 * Largura de 72mm: o papel de 80mm imprime 72mm; os 8mm restantes são a
 * margem física do mecanismo. Pôr 80 aqui corta a borda direita de cada linha.
 *
 * Sem cor e sem cinza claro: impressora térmica não tem tinta, ela queima o
 * papel. Cinza vira chuvisco, e texto cinza claro simplesmente não aparece.
 */

function hora(iso: string) {
  return new Date(iso).toLocaleString("pt-BR", {
    day: "2-digit",
    month: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  })
}

const FORMA: Record<string, string> = {
  pix: "PIX",
  credit_card: "CREDITO",
  debit_card: "DEBITO",
  cash: "DINHEIRO",
  meal_voucher: "VALE-REFEICAO",
}

export default async function Comanda({ params }: PageProps<"/painel/comanda/[id]">) {
  const { id } = await params
  const { vinculo } = await exigirVinculo()
  const supabase = await criarClienteDoServidor()

  const { data: pedido } = await supabase
    .from("orders")
    .select(
      "id, number, status, fulfillment, table_label, customer_name, customer_phone, address_summary, address_district, address_city, notes, subtotal_cents, delivery_fee_cents, discount_cents, total_cents, coupon_code, created_at, order_items(id, product_name, quantity, notes, total_cents, order_item_addons(addon_name, quantity)), payments(method, timing, change_for_cents)",
    )
    .eq("id", id)
    .eq("restaurant_id", vinculo.restauranteId)
    .maybeSingle()

  // A RLS já recorta para esta loja; o eq é a mensagem, não a tranca.
  if (!pedido) notFound()

  const pagamento = pedido.payments?.[0]
  const destino =
    pedido.fulfillment === "dine_in"
      ? (pedido.table_label ?? "MESA")
      : pedido.fulfillment === "pickup"
        ? "RETIRADA NO BALCAO"
        : "ENTREGA"

  return (
    <div className="comanda">
      {/* O estilo vive aqui, e não no Tailwind: esta página existe para o
          papel, e quem a lê depois precisa ver as medidas junto do conteúdo. */}
      <style>{`
        @page { size: 72mm auto; margin: 0; }
        html, body { margin: 0; padding: 0; background: #fff; }
        .comanda {
          width: 72mm;
          padding: 2mm 3mm 8mm;
          color: #000;
          font-family: ui-monospace, "Courier New", monospace;
          font-size: 12px;
          line-height: 1.35;
        }
        .comanda h1 { font-size: 15px; margin: 0; text-align: center; }
        .comanda .grande { font-size: 22px; font-weight: 700; text-align: center; margin: 2mm 0 0; }
        .comanda .destino { font-size: 16px; font-weight: 700; text-align: center; margin: 1mm 0 2mm; }
        .comanda hr { border: 0; border-top: 1px dashed #000; margin: 2mm 0; }
        .comanda table { width: 100%; border-collapse: collapse; }
        .comanda td { vertical-align: top; padding: 0.4mm 0; }
        .comanda .qtd { width: 8mm; font-weight: 700; }
        .comanda .valor { text-align: right; white-space: nowrap; }
        .comanda .obs { font-weight: 700; text-transform: uppercase; }
        .comanda .total td { font-size: 14px; font-weight: 700; padding-top: 1mm; }
        .comanda .rodape { text-align: center; margin-top: 3mm; font-size: 11px; }
        @media screen {
          html, body { background: #e5e5e5; }
          .comanda { margin: 16px auto; background: #fff; box-shadow: 0 1px 8px rgba(0,0,0,.2); }
        }
      `}</style>

      <h1>{vinculo.nome}</h1>
      <p className="grande">Nº {pedido.number}</p>
      <p className="destino">{destino}</p>
      <div style={{ textAlign: "center" }}>{hora(pedido.created_at)}</div>

      <hr />

      <div>
        <strong>{pedido.customer_name}</strong>
      </div>
      {pedido.customer_phone ? <div>{formatarTelefone(pedido.customer_phone)}</div> : null}
      {pedido.fulfillment === "delivery" && pedido.address_summary ? (
        <div>
          {pedido.address_summary}
          {pedido.address_district ? ` - ${pedido.address_district}` : ""}
          {pedido.address_city ? ` - ${pedido.address_city}` : ""}
        </div>
      ) : null}

      <hr />

      <table>
        <tbody>
          {pedido.order_items.map((i) => (
            <tr key={i.id}>
              <td className="qtd">{i.quantity}x</td>
              <td>
                {i.product_name}
                {i.order_item_addons.length > 0 ? (
                  <div>
                    {i.order_item_addons
                      .map((a) => `+ ${a.quantity > 1 ? `${a.quantity}x ` : ""}${a.addon_name}`)
                      .join("\n")
                      .split("\n")
                      .map((linha) => (
                        <div key={linha}>{linha}</div>
                      ))}
                  </div>
                ) : null}
                {/* A observação do item é a coisa mais importante do papel: é
                    o "sem cebola" que vira reclamação se passar batido. */}
                {i.notes ? <div className="obs">** {i.notes}</div> : null}
              </td>
              <td className="valor">{formatarReais(i.total_cents)}</td>
            </tr>
          ))}
        </tbody>
      </table>

      <hr />

      <table>
        <tbody>
          <tr>
            <td>Subtotal</td>
            <td className="valor">{formatarReais(pedido.subtotal_cents)}</td>
          </tr>
          {pedido.delivery_fee_cents > 0 ? (
            <tr>
              <td>Entrega</td>
              <td className="valor">{formatarReais(pedido.delivery_fee_cents)}</td>
            </tr>
          ) : null}
          {pedido.discount_cents > 0 ? (
            <tr>
              <td>Desconto {pedido.coupon_code ?? ""}</td>
              <td className="valor">- {formatarReais(pedido.discount_cents)}</td>
            </tr>
          ) : null}
          <tr className="total">
            <td>TOTAL</td>
            <td className="valor">{formatarReais(pedido.total_cents)}</td>
          </tr>
        </tbody>
      </table>

      <hr />

      <div>
        {pagamento?.timing === "on_delivery" ? (
          <>
            <strong>
              RECEBER{" "}
              {pedido.fulfillment === "dine_in"
                ? "NA MESA"
                : pedido.fulfillment === "pickup"
                  ? "NO BALCAO"
                  : "NA ENTREGA"}
            </strong>
            <div>{FORMA[pagamento.method] ?? pagamento.method}</div>
            {pagamento.method === "cash" && pagamento.change_for_cents ? (
              <div className="obs">
                TROCO PARA {formatarReais(pagamento.change_for_cents)} ={" "}
                {formatarReais(pagamento.change_for_cents - pedido.total_cents)}
              </div>
            ) : null}
          </>
        ) : (
          <strong>PAGO PELO SITE - {FORMA[pagamento?.method ?? ""] ?? ""}</strong>
        )}
      </div>

      {pedido.notes ? (
        <>
          <hr />
          <div className="obs">{pedido.notes}</div>
        </>
      ) : null}

      <div className="rodape">Tronvix Facil</div>
    </div>
  )
}
