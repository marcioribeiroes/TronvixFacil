import type { Metadata } from "next"
import Link from "next/link"

import { ProntidaoDaLoja, type ItemDeProntidao } from "@/components/painel/prontidao-da-loja"
import { formatarReais } from "@/lib/dinheiro"
import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirVinculo } from "@/modules/auth/sessao"
import {
  ROTULO_DA_SITUACAO,
  pedidoEmAndamento,
  type SituacaoDoPedido,
} from "@/modules/pedidos/maquina-de-estados"

export const metadata: Metadata = { title: "Dashboard" }

/**
 * A primeira tela depois do login.
 *
 * Ela responde a pergunta de quem abriu o painel agora: tem pedido esperando?
 * quanto entrou hoje? O resto - grafico, ranking - vem depois, porque ninguem
 * abre o painel no meio do almoco para estudar tendencia.
 *
 * E, enquanto a loja nao esta pronta para vender, a prontidao vem na frente de
 * tudo. Dashboard zerado de loja que ainda nao pode receber pedido nao informa
 * nada; o que falta, sim.
 */

function diaCurto(iso: string) {
  return new Date(iso).toLocaleDateString("pt-BR", { day: "2-digit", month: "2-digit" })
}

function horaCurta(iso: string) {
  return new Date(iso).toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" })
}

export default async function DashboardDoRestaurante() {
  const { vinculo } = await exigirVinculo()
  const supabase = await criarClienteDoServidor()

  const seteDias = new Date()
  seteDias.setDate(seteDias.getDate() - 6)
  seteDias.setHours(0, 0, 0, 0)

  const hoje = new Date()
  hoje.setHours(0, 0, 0, 0)

  const [{ data: loja }, { data: pedidos }, { count: produtos }, { count: entregadores }] =
    await Promise.all([
      supabase
        .from("restaurants")
        .select(
          "status, is_open, phone, street, number, district, city, postal_code, delivery_fee_cents, min_order_cents, avg_prep_minutes, commission_bps, logo_url",
        )
        .eq("id", vinculo.restauranteId)
        .single(),
      supabase
        .from("orders")
        .select("id, number, status, fulfillment, total_cents, customer_name, created_at")
        .eq("restaurant_id", vinculo.restauranteId)
        .gte("created_at", seteDias.toISOString())
        .order("created_at", { ascending: false }),
      supabase
        .from("products")
        .select("id", { count: "exact", head: true })
        .eq("restaurant_id", vinculo.restauranteId)
        .eq("is_available", true)
        .is("deleted_at", null),
      supabase
        .from("couriers")
        .select("id", { count: "exact", head: true })
        .eq("status", "approved")
        .is("deleted_at", null),
    ])

  const todos = pedidos ?? []
  const valendo = todos.filter((p) => p.status !== "cancelled" && p.status !== "rejected")

  const doDia = valendo.filter((p) => new Date(p.created_at) >= hoje)
  const faturadoHoje = doDia.reduce((s, p) => s + p.total_cents, 0)
  const ticket = doDia.length > 0 ? Math.round(faturadoHoje / doDia.length) : 0

  const emAndamento = todos.filter((p) => pedidoEmAndamento(p.status as SituacaoDoPedido))
  const esperandoResposta = emAndamento.filter((p) => p.status === "received")

  // Sete dias fixos no eixo: dia sem venda e informacao, dia omitido e mentira
  // sobre a constancia da loja.
  const porDia = new Map<string, number>()
  for (let d = 0; d < 7; d++) {
    const dia = new Date(seteDias)
    dia.setDate(dia.getDate() + d)
    porDia.set(dia.toISOString().slice(0, 10), 0)
  }
  for (const p of valendo) {
    const chave = p.created_at.slice(0, 10)
    if (porDia.has(chave)) porDia.set(chave, (porDia.get(chave) ?? 0) + p.total_cents)
  }
  const dias = [...porDia.entries()]
  const pico = Math.max(1, ...dias.map(([, v]) => v))

  const enderecoCompleto = Boolean(loja?.street && loja?.number && loja?.district && loja?.city)

  const prontidao: ItemDeProntidao[] = [
    {
      chave: "aprovacao",
      titulo: "Estabelecimento aprovado",
      ok: loja?.status === "approved",
      // A loja nao se aprova: quem aprova e a plataforma. Por isso aqui nao ha
      // botao - so o aviso de onde a coisa esta parada.
      pendencia:
        loja?.status === "pending"
          ? "Aguardando a aprovação da plataforma. Até lá a loja não aparece na vitrine."
          : loja?.status === "rejected"
            ? "Cadastro recusado pela plataforma."
            : "Estabelecimento suspenso. Fale com a plataforma.",
    },
    {
      chave: "cardapio",
      titulo: "Cardápio com produto disponível",
      ok: (produtos ?? 0) > 0,
      pendencia: "Sem produto disponível não há o que pedir.",
      acao: { rotulo: "Montar cardápio", href: "/painel/produtos" },
    },
    {
      chave: "endereco",
      titulo: "Endereço da loja",
      ok: enderecoCompleto,
      pendencia: "O endereço é de onde o entregador retira o pedido.",
      acao: { rotulo: "Preencher", href: "/painel/configuracoes" },
    },
    {
      chave: "telefone",
      titulo: "Telefone de contato",
      ok: Boolean(loja?.phone),
      pendencia: "É por ele que o cliente liga quando algo foge do combinado.",
      acao: { rotulo: "Preencher", href: "/painel/configuracoes" },
    },
    {
      chave: "entrega",
      titulo: "Equipe de entrega",
      ok: (entregadores ?? 0) > 0,
      pendencia:
        "Nenhum entregador aprovado. Dá para operar só com retirada no balcão, mas não com entrega.",
      acao: { rotulo: "Ver equipe", href: "/painel/entregas" },
    },
    {
      chave: "aberta",
      titulo: "Loja aberta",
      ok: loja?.is_open === true,
      pendencia: "Fechada, ela aparece na vitrine mas não aceita pedido.",
      acao: { rotulo: "Abrir", href: "/painel/configuracoes" },
    },
  ]

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">{vinculo.nome}</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          {loja?.is_open ? "Aberta agora." : "Fechada agora."} Comissão da plataforma:{" "}
          {((loja?.commission_bps ?? 0) / 100).toFixed(2).replace(".", ",")}%.
        </p>
      </div>

      <ProntidaoDaLoja itens={prontidao} />

      {esperandoResposta.length > 0 ? (
        <Link
          href="/painel/pedidos"
          className="flex items-center gap-3 rounded-xl border-2 border-marca bg-marca/5 p-4 transition-colors hover:bg-marca/10"
        >
          <span className="flex size-10 shrink-0 items-center justify-center rounded-full bg-marca text-lg font-bold text-white">
            {esperandoResposta.length}
          </span>
          <span className="min-w-0 flex-1">
            <span className="block font-bold">
              {esperandoResposta.length === 1
                ? "Um pedido esperando resposta"
                : `${esperandoResposta.length} pedidos esperando resposta`}
            </span>
            <span className="block text-sm text-muted-foreground">
              O cliente está olhando a tela. Aceite ou recuse na fila.
            </span>
          </span>
          <span className="shrink-0 text-sm font-semibold text-marca">Abrir fila →</span>
        </Link>
      ) : null}

      <dl className="grid gap-3 sm:grid-cols-4">
        <div className="rounded-xl border bg-card p-4">
          <dt className="text-xs font-semibold uppercase text-muted-foreground">Hoje</dt>
          <dd className="text-2xl font-bold">{formatarReais(faturadoHoje)}</dd>
        </div>
        <div className="rounded-xl border bg-card p-4">
          <dt className="text-xs font-semibold uppercase text-muted-foreground">
            Pedidos hoje
          </dt>
          <dd className="text-2xl font-bold">{doDia.length}</dd>
        </div>
        <div className="rounded-xl border bg-card p-4">
          <dt className="text-xs font-semibold uppercase text-muted-foreground">
            Ticket médio
          </dt>
          <dd className="text-2xl font-bold">{formatarReais(ticket)}</dd>
        </div>
        <div className="rounded-xl border bg-card p-4">
          <dt className="text-xs font-semibold uppercase text-muted-foreground">
            Em andamento
          </dt>
          <dd className="text-2xl font-bold">{emAndamento.length}</dd>
        </div>
      </dl>

      <div className="grid gap-6 lg:grid-cols-2">
        <section>
          <h2 className="text-sm font-bold uppercase tracking-wide text-muted-foreground">
            Últimos 7 dias
          </h2>
          {/* items-stretch, e nao items-end: com items-end a coluna encolhe ate
              a altura do conteudo, a barra calcula a porcentagem contra zero e
              o grafico aparece vazio. A barra e que se alinha ao fundo, dentro
              da coluna inteira. */}
          <div className="mt-3 flex h-36 items-stretch gap-2 rounded-xl border bg-card p-4">
            {dias.map(([dia, valor]) => (
              <div
                key={dia}
                className="group flex flex-1 flex-col gap-1"
                title={`${diaCurto(dia)}: ${formatarReais(valor)}`}
              >
                <div className="flex min-h-0 flex-1 items-end">
                  <div
                    className="w-full rounded-t bg-marca transition-colors group-hover:bg-marca-forte"
                    style={{ height: `${Math.max(2, (valor / pico) * 100)}%` }}
                  />
                </div>
                <span className="text-center text-[10px] text-muted-foreground">
                  {diaCurto(dia)}
                </span>
              </div>
            ))}
          </div>
        </section>

        <section>
          <h2 className="text-sm font-bold uppercase tracking-wide text-muted-foreground">
            Na cozinha e na rua
          </h2>
          <ul className="mt-3 divide-y rounded-xl border bg-card">
            {emAndamento.slice(0, 6).map((p) => (
              <li key={p.id} className="flex items-center gap-3 p-3 text-sm">
                <span className="font-mono text-xs text-muted-foreground">#{p.number}</span>
                <span className="min-w-0 flex-1 truncate font-medium">{p.customer_name}</span>
                <span className="shrink-0 text-xs text-muted-foreground">
                  {horaCurta(p.created_at)}
                </span>
                <span className="shrink-0 rounded-md bg-muted px-2 py-0.5 text-xs font-semibold">
                  {ROTULO_DA_SITUACAO[p.status as SituacaoDoPedido] ?? p.status}
                </span>
              </li>
            ))}
            {emAndamento.length === 0 ? (
              <li className="p-4 text-sm text-muted-foreground">
                Nenhum pedido em andamento.
              </li>
            ) : null}
          </ul>
          {emAndamento.length > 6 ? (
            <Link
              href="/painel/pedidos"
              className="mt-2 inline-block text-sm font-semibold text-marca hover:underline"
            >
              Ver os {emAndamento.length} na fila →
            </Link>
          ) : null}
        </section>
      </div>
    </div>
  )
}
