import type { Metadata } from "next"
import Link from "next/link"
import { Plus } from "lucide-react"

import { ChaveDaLoja } from "@/components/painel/chave-da-loja"
import { Button } from "@/components/ui/button"
import { FilaDePedidos, type PedidoDaFila } from "@/components/painel/fila-de-pedidos"
import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { formatarReais } from "@/lib/dinheiro"
import { exigirVinculo } from "@/modules/auth/sessao"
import { diaDeHoje, diaPorExtenso, diaValido, limitesDoDia } from "@/modules/pedidos/dia"
import type { SituacaoDoPedido } from "@/modules/pedidos/maquina-de-estados"

export const metadata: Metadata = { title: "Pedidos" }

/** Os estados em que o pedido ainda pede alguma coisa de alguem. */
const ABERTOS = [
  // "aguardando pagamento" entra na fila de propósito: é o Pix que o cliente
  // ainda não pagou, e alguém da loja precisa VER para confirmar. Fora daqui,
  // o pedido ficava invisível e parado para sempre.
  "awaiting_payment",
  "received",
  "confirmed",
  "preparing",
  "ready",
  "out_for_delivery",
] as const satisfies readonly SituacaoDoPedido[]

/** O que o cartão do quadro precisa saber de um pedido. */
const CAMPOS_DO_CARTAO =
  "id, number, status, cancelled_by, cancellation_reason, fulfillment, table_label, customer_name, customer_phone, address_summary, address_district, notes, total_cents, created_at, customer_added_at, ready_forecast_at, order_items(id, product_name, quantity, notes, created_at), payments(method, timing, status, amount_cents, payment_receipts(amount_cents)), deliveries(status)"

export default async function PaginaDePedidos({
  searchParams,
}: PageProps<"/painel/pedidos">) {
  const { vinculo } = await exigirVinculo()
  const supabase = await criarClienteDoServidor()
  const parametros = await searchParams

  // A loja vem antes do resto: o fuso dela decide onde comeca e termina o dia.
  const { data: loja } = await supabase
    .from("restaurants")
    .select("id, name, is_open, no_horario, avg_prep_minutes, timezone")
    .eq("id", vinculo.restauranteId)
    .single()

  const fuso = loja?.timezone ?? "America/Sao_Paulo"
  const hoje = diaDeHoje(fuso)
  const dia = diaValido(parametros.dia) ? parametros.dia : hoje
  const ehHoje = dia === hoje
  const { inicio, fim } = limitesDoDia(dia, fuso)

  // Vinte minutos atrás: o quanto um cancelamento ainda interessa a quem está
  // olhando a tela. Calculado aqui, e não dentro da consulta — chamar Date.now()
  // no meio da renderização é o tipo de impureza que o lint pega.
  const vinteMinutos = new Date()
  vinteMinutos.setMinutes(vinteMinutos.getMinutes() - 20)

  const doDiaEscolhido = supabase
    .from("orders")
    .select("total_cents, status")
    .eq("restaurant_id", vinculo.restauranteId)
    .gte("created_at", inicio)
    .lt("created_at", fim)

  let abertos: PedidoDaFila[]
  let cancelados: PedidoDaFila[]
  let entregues: PedidoDaFila[]
  let doDia: { total_cents: number; status: string }[]

  if (ehHoje) {
    const [r1, r2, r3, r4] = await Promise.all([
      // Hoje, a fila e a fila: todo pedido em aberto, de qualquer dia. Filtrar
      // por data aqui escondia o pedido de ontem que ficou parado.
      supabase
        .from("orders")
        .select(CAMPOS_DO_CARTAO)
        .eq("restaurant_id", vinculo.restauranteId)
        .in("status", ABERTOS)
        .order("created_at"),
      // Cancelados recentes. Sem isto, o pedido que o cliente desiste some da
      // tela enquanto alguem olha para ele — e a cozinha continua fazendo comida
      // que ninguem vai buscar.
      supabase
        .from("orders")
        .select(CAMPOS_DO_CARTAO)
        .eq("restaurant_id", vinculo.restauranteId)
        .in("status", ["cancelled", "rejected"])
        .gte("updated_at", vinteMinutos.toISOString())
        .order("updated_at", { ascending: false }),
      // Entregues hoje: o pedido que o cliente ja recebeu. O mais recente em
      // cima, que e o que o balcao procura quando o cliente liga.
      supabase
        .from("orders")
        .select(CAMPOS_DO_CARTAO)
        .eq("restaurant_id", vinculo.restauranteId)
        .eq("status", "delivered")
        .gte("updated_at", inicio)
        .order("updated_at", { ascending: false }),
      doDiaEscolhido,
    ])
    abertos = (r1.data ?? []) as PedidoDaFila[]
    cancelados = (r2.data ?? []) as PedidoDaFila[]
    entregues = (r3.data ?? []) as PedidoDaFila[]
    doDia = r4.data ?? []
  } else {
    // Outro dia: tudo o que foi pedido nele, em qualquer situacao, separado
    // aqui nas mesmas faixas do quadro de hoje.
    const [r1, r2] = await Promise.all([
      supabase
        .from("orders")
        .select(CAMPOS_DO_CARTAO)
        .eq("restaurant_id", vinculo.restauranteId)
        .gte("created_at", inicio)
        .lt("created_at", fim)
        .order("created_at"),
      doDiaEscolhido,
    ])
    const todos = (r1.data ?? []) as PedidoDaFila[]
    const aberto = new Set<string>(ABERTOS)
    abertos = todos.filter((p) => aberto.has(p.status))
    cancelados = todos.filter((p) => p.status === "cancelled" || p.status === "rejected")
    entregues = todos.filter((p) => p.status === "delivered").reverse()
    doDia = r2.data ?? []
  }

  const valendo = doDia.filter(
    (p) => p.status !== "cancelled" && p.status !== "rejected",
  )
  const faturado = valendo.reduce((soma, p) => soma + p.total_cents, 0)

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold tracking-tight">Pedidos</h1>
          <p className="mt-1 text-sm text-muted-foreground">
            {ehHoje
              ? "A fila da cozinha. Pedido que entra aparece aqui sozinho."
              : `Os pedidos feitos em ${diaPorExtenso(dia)}.`}
          </p>
        </div>

        <div className="flex flex-wrap items-start gap-3">
          {/* O pedido que nao veio pelo aplicativo: balcao, telefone, garcom. */}
          <Button render={<Link href="/painel/pedidos/novo" />}>
            <Plus className="size-4" aria-hidden="true" />
            Novo pedido
          </Button>
          {loja ? (
            <ChaveDaLoja
              aberta={loja.is_open}
              noHorario={loja.no_horario !== false}
              podeMexer={vinculo.cargo !== "staff"}
            />
          ) : null}
        </div>
      </div>

      {/* Formulario GET: o dia vai para a URL, e o link de um dia pode ser
          guardado ou mandado para alguem. */}
      <form className="flex flex-wrap items-end gap-2">
        <label className="text-sm">
          <span className="block text-xs text-muted-foreground">Dia</span>
          <input
            type="date"
            name="dia"
            defaultValue={dia}
            max={hoje}
            className="h-9 rounded-lg border bg-background px-2 text-sm"
          />
        </label>
        <Button type="submit" variant="outline">
          Ver
        </Button>
        {ehHoje ? null : (
          <Button variant="ghost" render={<Link href="/painel/pedidos" />}>
            Voltar para hoje
          </Button>
        )}
      </form>

      <dl className="grid grid-cols-3 gap-3 rounded-xl border bg-muted/40 p-4">
        <div>
          <dt className="text-xs font-semibold uppercase text-muted-foreground">
            {ehHoje ? "Hoje" : diaPorExtenso(dia)}
          </dt>
          <dd className="text-xl font-bold">{valendo.length}</dd>
        </div>
        <div>
          <dt className="text-xs font-semibold uppercase text-muted-foreground">Faturado</dt>
          <dd className="text-xl font-bold">{formatarReais(faturado)}</dd>
        </div>
        <div>
          <dt className="text-xs font-semibold uppercase text-muted-foreground">Em aberto</dt>
          <dd className="text-xl font-bold">{abertos.length}</dd>
        </div>
      </dl>

      <FilaDePedidos
        // Trocar de dia monta a fila de novo: sem isto, os pedidos do outro dia
        // pareciam "chegando" e o sino tocava.
        key={dia}
        pedidos={abertos}
        cancelados={cancelados}
        entregues={entregues}
        vazio={
          ehHoje
            ? undefined
            : { titulo: "Nenhum pedido neste dia", detalhe: "Escolha outro dia acima." }
        }
        restauranteId={vinculo.restauranteId}
        chavePublicaDePush={process.env.NEXT_PUBLIC_VAPID_CHAVE_PUBLICA ?? ""}
        // O preparo médio da loja é o palpite inicial da previsão que vai para
        // o entregador. Um número fixo aqui seria pior: pizzaria e açaiteria
        // não levam o mesmo tempo.
        preparoMedioEmMinutos={loja?.avg_prep_minutes ?? 30}
      />
    </div>
  )
}
