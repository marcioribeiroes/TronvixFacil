import type { Metadata } from "next"

import { LancarPedido } from "@/components/painel/lancar-pedido"
import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirVinculo } from "@/modules/auth/sessao"
import { carregarCardapio } from "@/modules/cardapio/carregar"

export const metadata: Metadata = { title: "Novo pedido" }

/**
 * O pedido que chega pelo balcão, pelo telefone ou pelo garçom.
 *
 * Entra direto como aceito, sem comissão, e vai para a fila, o caixa e o
 * estoque como qualquer outro.
 */
export default async function PaginaDeNovoPedido() {
  const { vinculo } = await exigirVinculo()
  const supabase = await criarClienteDoServidor()

  const [{ secoes, grupos }, { data: mesas }, { data: loja }, { data: clientes }] =
    await Promise.all([
    carregarCardapio(vinculo.restauranteId, { doBalcao: true }),
    supabase
      .from("restaurant_tables")
      .select("id, label")
      .eq("restaurant_id", vinculo.restauranteId)
      .eq("is_active", true)
      .is("deleted_at", null)
      .order("label"),
    supabase
      .from("restaurants")
      .select("delivery_fee_cents, free_delivery_above_cents")
      .eq("id", vinculo.restauranteId)
      .single(),
    // O caderno de clientes da loja (tela Clientes). A RLS deixa a equipe
    // inteira ler: quem atende o telefone e quem lanca o pedido.
    supabase
      .from("restaurant_customers")
      .select(
        "id, name, phone, address_street, address_number, address_complement, address_district, address_city, notes",
      )
      .eq("restaurant_id", vinculo.restauranteId)
      .is("deleted_at", null)
      .order("name"),
  ])

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">Novo pedido</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Balcão, mesa ou entrega por telefone. Entra na fila já aceito, e sem comissão.
        </p>
      </div>
      <LancarPedido
        secoes={secoes}
        grupos={grupos}
        mesas={(mesas ?? []).map((m) => ({ id: m.id, rotulo: m.label }))}
        frete={{
          centavos: loja?.delivery_fee_cents ?? 0,
          gratisAcimaDe: loja?.free_delivery_above_cents ?? null,
        }}
        clientes={(clientes ?? []).map((c) => ({
          id: c.id,
          nome: c.name,
          telefone: c.phone,
          rua: c.address_street,
          numero: c.address_number,
          complemento: c.address_complement,
          bairro: c.address_district,
          cidade: c.address_city,
          observacao: c.notes,
        }))}
      />
    </div>
  )
}
