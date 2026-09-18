import type { Metadata } from "next"
import { Bike } from "lucide-react"

import { LinhaDoEntregador, type EntregadorNaLista } from "@/components/admin/linha-do-entregador"
import { Badge } from "@/components/ui/badge"
import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirAdminDaPlataforma } from "@/modules/auth/sessao"

export const metadata: Metadata = { title: "Entregadores" }

/**
 * Os entregadores da plataforma.
 *
 * Quem espera aprovacao vem primeiro: entregador parado na fila e alguem que
 * quer trabalhar e nao consegue, e que em dois dias esta no concorrente.
 *
 * O entregador que pertence a uma loja aparece marcado. Quem o aprova e a
 * propria loja, pela tela de entregas dela - a plataforma ve, para saber quem
 * circula, mas nao assume a decisao de quem nao e dela.
 */
export default async function PaginaDeEntregadores() {
  await exigirAdminDaPlataforma()
  const supabase = await criarClienteDoServidor()

  const { data: entregadores } = await supabase
    .from("couriers")
    // couriers aponta para profiles duas vezes - user_id e approved_by - e o
    // PostgREST recusa o embed sem a dica de qual chave usar.
    .select(
      "id, status, availability, vehicle_type, vehicle_plate, deliveries_count, rating_avg, rating_count, created_at, restaurant_id, profiles!couriers_user_id_fkey(full_name, email, phone), restaurants(name)",
    )
    .is("deleted_at", null)
    .order("created_at", { ascending: false })

  const lista: EntregadorNaLista[] = (entregadores ?? []).map((c) => ({
    id: c.id,
    nome: c.profiles?.full_name ?? "Entregador",
    email: c.profiles?.email ?? null,
    telefone: c.profiles?.phone ?? null,
    situacao: c.status,
    disponibilidade: c.availability,
    veiculo: c.vehicle_type,
    placa: c.vehicle_plate,
    entregas: c.deliveries_count,
    nota: c.rating_avg,
    avaliacoes: c.rating_count,
    loja: c.restaurants?.name ?? null,
    desde: c.created_at,
  }))

  const esperando = lista.filter((c) => c.situacao === "pending")
  const resto = lista.filter((c) => c.situacao !== "pending")

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">Entregadores</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Quem leva o pedido. Ninguém entra na fila de corridas sem passar por aqui — ou pela
          loja, quando o entregador é dela.
        </p>
      </div>

      {esperando.length > 0 ? (
        <section>
          <div className="flex items-center gap-2">
            <h2 className="text-sm font-bold uppercase tracking-wide text-muted-foreground">
              Esperando aprovação
            </h2>
            <Badge variant="destructive">{esperando.length}</Badge>
          </div>
          <div className="mt-3 space-y-3">
            {esperando.map((c) => (
              <LinhaDoEntregador key={c.id} entregador={c} destaque />
            ))}
          </div>
        </section>
      ) : null}

      <section>
        <h2 className="text-sm font-bold uppercase tracking-wide text-muted-foreground">
          {esperando.length > 0 ? "Os demais" : "Todos"}
        </h2>

        {resto.length === 0 ? (
          <div className="mt-3 rounded-xl border border-dashed p-10 text-center">
            <Bike className="mx-auto size-8 text-muted-foreground" aria-hidden="true" />
            <p className="mt-3 font-semibold">Nenhum entregador cadastrado</p>
            <p className="mt-1 text-sm text-muted-foreground">
              Quem se cadastrar pelo aplicativo aparece aqui esperando aprovação.
            </p>
          </div>
        ) : (
          <div className="mt-3 space-y-3">
            {resto.map((c) => (
              <LinhaDoEntregador key={c.id} entregador={c} />
            ))}
          </div>
        )}
      </section>
    </div>
  )
}
