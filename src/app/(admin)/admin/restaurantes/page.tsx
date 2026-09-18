import type { Metadata } from "next"
import { Store } from "lucide-react"

import { LinhaDoEstabelecimento } from "@/components/admin/linha-do-estabelecimento"
import { Badge } from "@/components/ui/badge"
import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirAdminDaPlataforma } from "@/modules/auth/sessao"

export const metadata: Metadata = { title: "Restaurantes" }

/**
 * Os estabelecimentos da plataforma.
 *
 * Quem espera aprovacao vem primeiro, e separado: e a unica parte desta tela
 * com prazo. Um cadastro parado aqui e um restaurante que nao vende e um
 * cliente que desiste.
 */
export default async function PaginaDeRestaurantes() {
  await exigirAdminDaPlataforma()
  const supabase = await criarClienteDoServidor()

  const { data: estabelecimentos } = await supabase
    .from("restaurants")
    // Literal de uma vez só: o cliente tipado do Supabase infere as colunas do
    // texto, e uma concatenação com + apaga essa inferência — a linha vira
    // `GenericStringError` e o TypeScript perde o tipo inteiro.
    .select(
      "id, slug, name, description, logo_url, status, is_open, commission_bps, city, state, district, phone, created_at, approved_at, rating_avg, rating_count",
    )
    .is("deleted_at", null)
    .order("created_at", { ascending: false })

  const lista = estabelecimentos ?? []
  const esperando = lista.filter((r) => r.status === "pending")
  const resto = lista.filter((r) => r.status !== "pending")

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">Restaurantes</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Quem entra na plataforma, quanto a plataforma cobra, e quem está fora.
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
            {esperando.map((r) => (
              <LinhaDoEstabelecimento key={r.id} estabelecimento={r} destaque />
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
            <Store className="mx-auto size-8 text-muted-foreground" aria-hidden="true" />
            <p className="mt-3 font-semibold">Nenhum estabelecimento ainda</p>
            <p className="mt-1 text-sm text-muted-foreground">
              Quando alguém se cadastrar, o pedido de aprovação aparece aqui.
            </p>
          </div>
        ) : (
          <div className="mt-3 space-y-3">
            {resto.map((r) => (
              <LinhaDoEstabelecimento key={r.id} estabelecimento={r} />
            ))}
          </div>
        )}
      </section>
    </div>
  )
}
