import type { Metadata } from "next"
import Link from "next/link"
import { Receipt } from "lucide-react"

import { Badge } from "@/components/ui/badge"
import { formatarReais } from "@/lib/dinheiro"
import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirUsuario } from "@/modules/auth/sessao"
import { ROTULO_DA_SITUACAO, type SituacaoDoPedido } from "@/modules/pedidos/maquina-de-estados"

export const metadata: Metadata = { title: "Seus pedidos" }

export default async function PaginaDePedidos() {
  const contexto = await exigirUsuario("/pedidos")
  const supabase = await criarClienteDoServidor()

  const { data: pedidos } = await supabase
    .from("orders")
    .select("id, number, status, total_cents, created_at, restaurants(name)")
    .eq("customer_id", contexto.id)
    .order("created_at", { ascending: false })
    .limit(30)

  return (
    <div className="mx-auto max-w-2xl px-4 py-6">
      <h1 className="text-2xl font-bold tracking-tight">Seus pedidos</h1>

      {(pedidos ?? []).length === 0 ? (
        <div className="mt-8 rounded-xl border border-dashed p-12 text-center">
          <Receipt className="mx-auto size-8 text-muted-foreground" aria-hidden="true" />
          <p className="mt-3 font-semibold">Nenhum pedido ainda</p>
          <p className="mt-1 text-sm text-muted-foreground">
            Quando você pedir, o histórico aparece aqui.
          </p>
        </div>
      ) : (
        <ul className="mt-6 divide-y rounded-xl border bg-card">
          {(pedidos ?? []).map((p) => (
            <li key={p.id}>
              <Link
                href={`/pedidos/${p.id}`}
                className="flex items-center gap-3 p-4 transition-colors hover:bg-muted/50"
              >
                <div className="min-w-0 flex-1">
                  <p className="font-semibold">{p.restaurants?.name}</p>
                  <p className="text-sm text-muted-foreground">
                    nº {p.number} ·{" "}
                    {new Date(p.created_at).toLocaleDateString("pt-BR", {
                      day: "2-digit",
                      month: "2-digit",
                    })}
                  </p>
                </div>
                <Badge variant="secondary">
                  {ROTULO_DA_SITUACAO[p.status as SituacaoDoPedido]}
                </Badge>
                <span className="font-bold">{formatarReais(p.total_cents)}</span>
              </Link>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}
