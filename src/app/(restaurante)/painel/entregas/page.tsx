import type { Metadata } from "next"

import { EquipeDeEntrega } from "@/components/painel/equipe-de-entrega"
import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirGestao } from "@/modules/auth/sessao"
import { ROTULO_DA_ENTREGA, type SituacaoDaEntrega } from "@/modules/pedidos/maquina-de-estados"

export const metadata: Metadata = { title: "Entregas" }

export default async function PaginaDeEntregas() {
  const { vinculo } = await exigirGestao()
  const supabase = await criarClienteDoServidor()

  const [{ data: entregadores }, { data: corridas }, { data: loja }] = await Promise.all([
    // A RLS ja recorta para os deste estabelecimento; nao ha `where` aqui de
    // proposito — se aparecer gente de fora, o conserto e no banco.
    supabase
      .from("couriers")
      // A dica do nome da chave e obrigatoria: couriers aponta para profiles
      // duas vezes — user_id (quem e) e approved_by (quem aprovou) — e sem
      // dizer qual, o PostgREST recusa o embed.
      .select(
        "id, status, availability, vehicle_type, deliveries_count, created_at, profiles!couriers_user_id_fkey(full_name, phone)",
      )
      .is("deleted_at", null)
      .order("status")
      .order("created_at"),
    supabase
      .from("deliveries")
      .select("id, status, courier_fee_cents, courier_id, orders(number, customer_name, address_district)")
      .eq("restaurant_id", vinculo.restauranteId)
      .in("status", ["searching_courier", "assigned", "heading_to_restaurant", "picked_up", "heading_to_customer"])
      .order("created_at"),
    supabase
      .from("restaurants")
      .select("accepts_platform_couriers")
      .eq("id", vinculo.restauranteId)
      .single(),
  ])

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">Entregas</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Sua equipe de entrega e as corridas em andamento. O sistema não leiloa
          a corrida: quem leva é gente sua, e quem aprova é você.
        </p>
      </div>

      <EquipeDeEntrega
        aceitaDeFora={loja?.accepts_platform_couriers ?? false}
        entregadores={(entregadores ?? []).map((c) => ({
          id: c.id,
          nome: c.profiles?.full_name ?? "Entregador",
          telefone: c.profiles?.phone ?? null,
          situacao: c.status,
          disponibilidade: c.availability,
          veiculo: c.vehicle_type,
          entregas: c.deliveries_count,
        }))}
        corridas={(corridas ?? []).map((d) => ({
          id: d.id,
          situacao: ROTULO_DA_ENTREGA[d.status as SituacaoDaEntrega] ?? d.status,
          semEntregador: d.courier_id === null,
          numeroDoPedido: d.orders?.number ?? 0,
          cliente: d.orders?.customer_name ?? "",
          bairro: d.orders?.address_district ?? null,
          taxaCentavos: d.courier_fee_cents,
        }))}
      />
    </div>
  )
}
