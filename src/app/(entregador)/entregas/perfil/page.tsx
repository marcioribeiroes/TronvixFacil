import type { Metadata } from "next"

import {
  AssinaturaDoEntregador,
  type Assinatura,
} from "@/components/entregador/assinatura-do-entregador"
import { formatarTelefone } from "@/lib/telefone"
import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirEntregador } from "@/modules/auth/sessao"

export const metadata: Metadata = { title: "Perfil" }

/**
 * O cadastro do entregador, como o banco o ve.
 *
 * So leitura, e por um motivo: `app.guard_courier_platform_fields` recusa que
 * o proprio entregador mexa em status, contador de entregas ou nota. Oferecer
 * campos que o banco vai recusar e ensinar a pessoa a nao confiar na tela.
 * Quem corrige um dado errado aqui e o estabelecimento.
 */

const SITUACAO: Record<string, string> = {
  pending: "Esperando aprovação",
  approved: "Aprovado",
  suspended: "Suspenso",
  rejected: "Recusado",
}

const VEICULO: Record<string, string> = {
  motorcycle: "Moto",
  bicycle: "Bicicleta",
  car: "Carro",
  foot: "A pé",
}

export default async function PerfilDoEntregador() {
  const { contexto, entregadorId } = await exigirEntregador()
  const supabase = await criarClienteDoServidor()

  // So o autonomo tem assinatura; para o do estabelecimento vem "aplica: false".
  const { data: bruta } = await supabase.rpc("minha_assinatura")
  const dados = (bruta ?? {}) as Record<string, unknown>
  const pendente = dados.pendente as Record<string, unknown> | null | undefined
  const assinatura: Assinatura | null = dados.aplica
    ? {
        cobrando: Boolean(dados.cobrando),
        inicio: (dados.inicio as string | null) ?? null,
        vence: (dados.vence as string | null) ?? null,
        emDia: Boolean(dados.em_dia),
        precoCentavos: Number(dados.preco_centavos ?? 0),
        pendente: pendente
          ? {
              valorCentavos: Number(pendente.valor_centavos),
              referencia: String(pendente.referencia),
              copiaECola: String(pendente.copia_e_cola),
            }
          : null,
      }
    : null

  const { data: eu } = await supabase
    .from("couriers")
    .select(
      "status, availability, vehicle_type, vehicle_plate, deliveries_count, rating_avg, rating_count, created_at, restaurants(name, phone)",
    )
    .eq("id", entregadorId)
    .single()

  const linhas: [string, string][] = [
    ["Nome", contexto.perfil.full_name || "—"],
    ["E-mail", contexto.email ?? "—"],
    ["Telefone", formatarTelefone(contexto.perfil.phone) || "—"],
    ["Situação", SITUACAO[eu?.status ?? ""] ?? eu?.status ?? "—"],
    [
      "Veículo",
      [VEICULO[eu?.vehicle_type ?? ""] ?? eu?.vehicle_type, eu?.vehicle_plate]
        .filter(Boolean)
        .join(" · ") || "—",
    ],
    ["Entregas concluídas", String(eu?.deliveries_count ?? 0)],
    [
      "Avaliação",
      (eu?.rating_count ?? 0) > 0
        ? `${eu!.rating_avg.toFixed(1).replace(".", ",")} (${eu!.rating_count})`
        : "sem avaliações ainda",
    ],
    ["Trabalha para", eu?.restaurants?.name ?? "a plataforma"],
    [
      "Desde",
      eu?.created_at ? new Date(eu.created_at).toLocaleDateString("pt-BR") : "—",
    ],
  ]

  return (
    <div className="mx-auto max-w-lg space-y-4">
      <h1 className="text-xl font-bold tracking-tight">Perfil</h1>

      <dl className="divide-y rounded-xl border bg-card">
        {linhas.map(([rotulo, valor]) => (
          <div key={rotulo} className="flex items-center justify-between gap-3 p-3 text-sm">
            <dt className="text-muted-foreground">{rotulo}</dt>
            <dd className="text-right font-medium">{valor}</dd>
          </div>
        ))}
      </dl>

      {assinatura ? <AssinaturaDoEntregador assinatura={assinatura} /> : null}

      <p className="rounded-xl border border-dashed p-4 text-xs text-muted-foreground">
        Dado errado aqui se corrige com {eu?.restaurants?.name ?? "a plataforma"}
        {eu?.restaurants?.phone ? ` (${formatarTelefone(eu.restaurants.phone)})` : ""}. O banco
        não deixa o próprio entregador mexer na situação, no contador de entregas nem na nota —
        é isso que faz esses números valerem alguma coisa.
      </p>
    </div>
  )
}
