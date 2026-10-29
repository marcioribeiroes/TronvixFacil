import type { Metadata } from "next"
import { Bike } from "lucide-react"

import { LinhaDoEntregador, type EntregadorNaLista } from "@/components/admin/linha-do-entregador"
import {
  PagamentosDosEntregadores,
  type PagamentoPendente,
} from "@/components/admin/pagamentos-dos-entregadores"
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
      "id, status, availability, vehicle_type, vehicle_plate, deliveries_count, rating_avg, rating_count, created_at, restaurant_id, cpf, birth_date, city, pix_key, vehicle_model, vehicle_color, review_note, document_cnh_path, document_vehicle_path, document_selfie_path, profiles!couriers_user_id_fkey(full_name, email, phone), restaurants(name)",
    )
    .is("deleted_at", null)
    .order("created_at", { ascending: false })

  // Os documentos ficam em balde privado. Uma hora de validade: o bastante
  // para analisar a fila, e o link copiado nao vira acesso permanente.
  const caminhos = (entregadores ?? []).flatMap((c) =>
    [c.document_cnh_path, c.document_vehicle_path, c.document_selfie_path].filter(
      (x): x is string => Boolean(x),
    ),
  )
  const assinadas = new Map<string, string>()
  if (caminhos.length > 0) {
    const { data } = await supabase.storage
      .from("documentos-entregador")
      .createSignedUrls(caminhos, 3600)
    for (const d of data ?? []) {
      if (d.path && d.signedUrl) assinadas.set(d.path, d.signedUrl)
    }
  }

  const hoje = new Date()
  const idade = (nascimento: string | null) => {
    if (!nascimento) return null
    const n = new Date(`${nascimento}T12:00:00`)
    let anos = hoje.getFullYear() - n.getFullYear()
    if (hoje < new Date(hoje.getFullYear(), n.getMonth(), n.getDate())) anos -= 1
    return anos
  }

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
    cadastro: c.cpf
      ? {
          cpf: c.cpf,
          idade: idade(c.birth_date),
          cidade: c.city,
          pix: c.pix_key,
          modelo: c.vehicle_model,
          cor: c.vehicle_color,
          motivo: c.review_note,
          documentos: (
            [
              ["CNH", c.document_cnh_path],
              ["Documento do veículo", c.document_vehicle_path],
              ["Selfie com a CNH", c.document_selfie_path],
            ] as const
          ).flatMap(([rotulo, caminho]) => {
            const url = caminho ? assinadas.get(caminho) : undefined
            return url ? [{ rotulo, url }] : []
          }),
        }
      : null,
  }))

  const { data: pendentes } = await supabase
    .from("courier_payments")
    .select("id, amount_cents, reference, created_at, couriers(profiles!couriers_user_id_fkey(full_name))")
    .eq("status", "pending")
    .order("created_at")

  const pagamentos: PagamentoPendente[] = (pendentes ?? []).map((p) => ({
    id: p.id,
    entregador: p.couriers?.profiles?.full_name ?? "Entregador",
    valorCentavos: p.amount_cents,
    referencia: p.reference,
    criadoEm: p.created_at,
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

      <PagamentosDosEntregadores pagamentos={pagamentos} />

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
