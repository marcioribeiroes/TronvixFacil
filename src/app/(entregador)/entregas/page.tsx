import type { Metadata } from "next"

import {
  CorridasDoEntregador,
  type CorridaNaTela,
} from "@/components/entregador/corridas-do-entregador"
import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirEntregador } from "@/modules/auth/sessao"
import type {
  SituacaoDaEntrega,
  SituacaoDoPedido,
} from "@/modules/pedidos/maquina-de-estados"

export const metadata: Metadata = { title: "Corridas" }

/** O mesmo recorte que o aplicativo pede — as colunas que a tela usa, e só. */
const CORRIDA_COMPLETA =
  "id, status, courier_fee_cents, created_at, courier_id, orders(number, status, ready_forecast_at, total_cents, customer_name, customer_phone, address_summary, address_district, notes, restaurants(name, phone, street, number, district), payments(timing))"

/**
 * A fila de corridas, no navegador.
 *
 * Existe porque nem todo entregador instala aplicativo: muitos trabalham com
 * o celular do dia, o da loja, ou um emprestado. O link abre e funciona.
 *
 * O que a tela mostra e recortado pela RLS, nao por um `where` aqui: a fila so
 * expoe corridas dos estabelecimentos que este entregador serve
 * (`app.courier_serves`), e o pedido por tras dela so aparece enquanto a
 * corrida esta oferecida a ele (`app.is_order_offered_to_courier`).
 */
export default async function CorridasDisponiveis() {
  const { entregadorId } = await exigirEntregador()
  const supabase = await criarClienteDoServidor()

  const hoje = new Date()
  hoje.setHours(0, 0, 0, 0)

  const [{ data: minha }, { data: fila }, { data: eu }, { data: entreguesHoje }] =
    await Promise.all([
      supabase
        .from("deliveries")
        .select(CORRIDA_COMPLETA)
        .eq("courier_id", entregadorId)
        .in("status", ["assigned", "heading_to_restaurant", "picked_up", "heading_to_customer"])
        .limit(1),
      supabase
        .from("deliveries")
        .select(CORRIDA_COMPLETA)
        .eq("status", "searching_courier")
        .order("created_at"),
      supabase.from("couriers").select("availability").eq("id", entregadorId).single(),
      supabase
        .from("deliveries")
        .select("courier_fee_cents")
        .eq("courier_id", entregadorId)
        .eq("status", "delivered")
        .gte("delivered_at", hoje.toISOString()),
    ])

  type Linha = NonNullable<typeof fila>[number]

  function paraTela(d: Linha): CorridaNaTela {
    const pedido = d.orders
    const loja = pedido?.restaurants
    return {
      id: d.id,
      situacao: d.status as SituacaoDaEntrega,
      ganhoCentavos: d.courier_fee_cents,
      numeroDoPedido: pedido?.number ?? 0,
      totalDoPedidoCentavos: pedido?.total_cents ?? 0,
      cliente: pedido?.customer_name ?? "",
      telefoneDoCliente: pedido?.customer_phone ?? null,
      enderecoDeEntrega: pedido?.address_summary ?? null,
      bairro: pedido?.address_district ?? null,
      restaurante: loja?.name ?? "",
      enderecoDoRestaurante:
        [loja?.street, loja?.number, loja?.district].filter(Boolean).join(", ") || null,
      telefoneDoRestaurante: loja?.phone ?? null,
      observacao: pedido?.notes ?? null,
      // payments é um-para-muitos (um pedido pode ter uma segunda tentativa),
      // então vem lista. Sem pagamento registrado o entregador cobra na porta:
      // dizer "já pago" por omissão é o jeito de ele sair sem receber.
      recebeNaPorta: pedido?.payments?.[0]?.timing !== "online",
      criadaEm: d.created_at,
      // Sem pedido em maos, "received" e o mais conservador: a tela nao
      // oferece o botao de retirar, e quem decide de verdade e o banco.
      situacaoDoPedido: (pedido?.status as SituacaoDoPedido | undefined) ?? "received",
      prontoEm: pedido?.ready_forecast_at ?? null,
    }
  }

  return (
    <CorridasDoEntregador
      minhaCorrida={minha && minha.length > 0 ? paraTela(minha[0]) : null}
      fila={(fila ?? []).map(paraTela)}
      online={eu?.availability === "online" || eu?.availability === "on_delivery"}
      entreguesHoje={(entreguesHoje ?? []).length}
      ganhoDeHoje={(entreguesHoje ?? []).reduce((s, d) => s + d.courier_fee_cents, 0)}
    />
  )
}
