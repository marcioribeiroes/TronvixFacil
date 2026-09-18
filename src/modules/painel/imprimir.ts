"use server"

import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirVinculo } from "@/modules/auth/sessao"
import { montarComanda, type PedidoParaImprimir } from "@/modules/painel/comanda"

/**
 * Os bytes da comanda, prontos para a impressora.
 *
 * A montagem acontece no servidor e o navegador recebe só a fita. Assim o
 * pedido inteiro não precisa trafegar para a tela, e a RLS continua sendo quem
 * decide o que este balcão pode ver.
 *
 * Volta em base64 porque é o que passa por uma Server Action sem se transformar
 * pelo caminho: um Uint8Array vira objeto comum na serialização, e um array de
 * números de três mil posições é desperdício puro.
 */
export async function bytesDaComanda(
  id: string,
  colunas = 48,
): Promise<{ ok: true; fita: string } | { ok: false; erro: string }> {
  const { vinculo } = await exigirVinculo()
  const supabase = await criarClienteDoServidor()

  const { data: pedido, error } = await supabase
    .from("orders")
    .select(
      "id, number, fulfillment, table_label, customer_name, customer_phone, address_summary, address_district, address_city, notes, subtotal_cents, delivery_fee_cents, discount_cents, total_cents, coupon_code, created_at, order_items(product_name, quantity, notes, total_cents, order_item_addons(addon_name, quantity)), payments(method, timing, change_for_cents)",
    )
    .eq("id", id)
    .eq("restaurant_id", vinculo.restauranteId)
    .maybeSingle()

  if (error) return { ok: false, erro: error.message }
  if (!pedido) return { ok: false, erro: "Não achei esse pedido." }

  const pagamento = pedido.payments?.[0]

  const dados: PedidoParaImprimir = {
    numero: pedido.number,
    loja: vinculo.nome,
    criadoEm: pedido.created_at,
    tipo: pedido.fulfillment,
    mesa: pedido.table_label,
    cliente: pedido.customer_name,
    telefone: pedido.customer_phone,
    endereco: pedido.address_summary,
    bairro: pedido.address_district,
    cidade: pedido.address_city,
    observacao: pedido.notes,
    subtotalCentavos: pedido.subtotal_cents,
    taxaCentavos: pedido.delivery_fee_cents,
    descontoCentavos: pedido.discount_cents,
    totalCentavos: pedido.total_cents,
    cupom: pedido.coupon_code,
    formaDePagamento: pagamento?.method ?? null,
    pagaNaHora: pagamento?.timing === "on_delivery",
    trocoParaCentavos: pagamento?.change_for_cents ?? null,
    itens: pedido.order_items.map((i) => ({
      nome: i.product_name,
      quantidade: i.quantity,
      observacao: i.notes,
      totalCentavos: i.total_cents,
      adicionais: i.order_item_addons.map((a) => ({
        nome: a.addon_name,
        quantidade: a.quantity,
      })),
    })),
  }

  const fita = montarComanda(dados, colunas)
  return { ok: true, fita: Buffer.from(fita).toString("base64") }
}
