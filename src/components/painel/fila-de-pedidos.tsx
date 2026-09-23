"use client"

import { useEffect, useRef, useState, useTransition } from "react"
import { useRouter } from "next/navigation"
import { Ban, Bike, Clock, Printer, StickyNote, Store, Wallet,
  UtensilsCrossed,
} from "lucide-react"

import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { imprimirComanda, jaImpressos, marcarImpresso } from "@/lib/impressao"
import { destravarSom, tocarSino } from "@/lib/sino"
import { criarClienteDoNavegador } from "@/lib/supabase/navegador"
import { formatarReais } from "@/lib/dinheiro"
import {
  ACAO_DA_SITUACAO,
  ROTULO_DA_SITUACAO,
  proximasSituacoesDoPedido,
  type SituacaoDoPedido,
  type TipoDeEntrega,
} from "@/modules/pedidos/maquina-de-estados"
import { AvisoDePedidos } from "@/components/painel/aviso-de-pedidos"
import {
  avancarPedido,
  chamarEntregador,
  confirmarPix,
  recusarPedido,
} from "@/modules/painel/pedidos"

export type PedidoDaFila = {
  id: string
  number: number
  status: string
  fulfillment: string
  table_label: string | null
  customer_name: string
  customer_phone: string | null
  address_summary: string | null
  address_district: string | null
  notes: string | null
  total_cents: number
  created_at: string
  /** Promessa de quando a comida fica pronta. Nulo enquanto ninguém chamou. */
  ready_forecast_at: string | null
  order_items: { id: string; product_name: string; quantity: number; notes: string | null }[]
  payments: { method: string; timing: string; status: string }[]
  /**
   * A entrega deste pedido. Vem como objeto, não lista: `deliveries.order_id`
   * é único, então o PostgREST trata a relação como um-para-um. Nulo em
   * retirada e mesa, que não têm rua no caminho.
   */
  deliveries: { status: string } | null
  cancelled_by?: string | null
  cancellation_reason?: string | null
}

const FORMA: Record<string, string> = {
  pix: "Pix",
  credit_card: "crédito",
  debit_card: "débito",
  cash: "dinheiro",
  meal_voucher: "vale-refeição",
}

function minutosDesde(iso: string) {
  return Math.max(0, Math.floor((Date.now() - new Date(iso).getTime()) / 60000))
}

/**
 * A previsao em palavras, do jeito que o balcao fala.
 *
 * Mostra o atraso quando a hora prometida ja passou, em vez de esconder: e
 * justamente ai que alguem precisa avisar o entregador que esta a caminho.
 */
function quando(iso: string) {
  const minutos = Math.round((new Date(iso).getTime() - Date.now()) / 60000)
  if (minutos > 1) return `em ${minutos} min`
  if (minutos >= 0) return "agora"
  return `há ${Math.abs(minutos)} min — atrasado`
}

/**
 * A fila da cozinha.
 *
 * Recebe a lista do servidor e assina o Realtime para se atualizar sozinha:
 * num balcao, o atraso entre o pedido entrar no banco e alguem ve-lo e comida
 * esfriando. Quando algo muda, `router.refresh()` refaz a consulta no servidor
 * em vez de remendar o estado aqui - a RLS continua sendo quem decide o que
 * aparece.
 *
 * E avisa. Atualizar sozinha so resolve para quem esta olhando, e restaurante
 * em movimento nao fica encarando monitor: o pedido entrava, a tela mudava, e
 * ninguem via.
 */
export function FilaDePedidos({
  pedidos,
  cancelados,
  restauranteId,
  chavePublicaDePush,
  preparoMedioEmMinutos,
}: {
  pedidos: PedidoDaFila[]
  /** Cancelados nos ultimos vinte minutos. Sumir em silencio e pior. */
  cancelados: PedidoDaFila[]
  restauranteId: string
  chavePublicaDePush: string
  /** Palpite inicial da previsao que vai para o entregador. */
  preparoMedioEmMinutos: number
}) {
  const router = useRouter()
  const [somLigado, setSomLigado] = useState(false)
  const [imprimindoSozinho, setImprimindoSozinho] = useState(false)

  /**
   * Os pedidos que a tela JA viu, por id.
   *
   * Contar não serve. Com a contagem, aceitar um pedido e receber outro no
   * mesmo instante deixava o número igual e o sino calado; e confirmar um Pix
   * — que muda "aguardando" para "recebido" — fazia a contagem subir e o sino
   * tocar para uma ação da própria loja.
   */
  const jaVistos = useRef<Set<string> | null>(null)

  // Tudo que ainda espera alguém da loja: pedido novo e Pix por confirmar.
  const esperando = pedidos.filter(
    (p) => p.status === "received" || p.status === "awaiting_payment",
  )

  const idsEsperando = esperando.map((p) => p.id).join(",")

  useEffect(() => {
    const ids = idsEsperando ? idsEsperando.split(",") : []
    const anterior = jaVistos.current

    jaVistos.current = new Set(ids)

    // Primeira renderização: o que já estava na tela não é novidade.
    if (anterior === null) return

    const chegaram = ids.filter((id) => !anterior.has(id))
    if (chegaram.length === 0) return

    if (somLigado) tocarSino()

    // A comanda sai sozinha, um pedido de cada vez. Disparar três impressões
    // no mesmo instante embaralha a fila do driver, e o que sai do papel é
    // um pedido pela metade seguido de outro.
    if (imprimindoSozinho) {
      void (async () => {
        for (const id of chegaram) {
          if (jaImpressos().has(id)) continue
          const ok = await imprimirComanda(id)
          if (ok) marcarImpresso(id)
        }
      })()
    }

    // Aviso do sistema, para quem esta com a aba atras de outra janela.
    if (typeof Notification !== "undefined" && Notification.permission === "granted") {
      new Notification(chegaram.length === 1 ? "Pedido novo" : `${chegaram.length} pedidos novos`, {
        body: `${ids.length} esperando você.`,
        tag: "pedido-novo",
      })
    }
  }, [idsEsperando, somLigado, imprimindoSozinho])

  /**
   * Cancelamento também avisa.
   *
   * O pedido sai da fila quando o cliente desiste, e sair em silêncio é a
   * cozinha continuar fazendo comida que ninguém vai buscar.
   */
  const idsCancelados = cancelados.map((p) => p.id).join(",")
  const cancelamentosVistos = useRef<Set<string> | null>(null)

  useEffect(() => {
    const ids = idsCancelados ? idsCancelados.split(",") : []
    const anterior = cancelamentosVistos.current
    cancelamentosVistos.current = new Set(ids)

    if (anterior === null) return
    const novos = ids.filter((id) => !anterior.has(id))
    if (novos.length === 0) return

    // Um golpe só, e mais forte: é um aviso, não um chamado a atender.
    if (somLigado) tocarSino(0.34)

    if (typeof Notification !== "undefined" && Notification.permission === "granted") {
      new Notification("Pedido cancelado", {
        body: "Um pedido saiu da fila. Confira no quadro.",
        tag: "pedido-cancelado",
      })
    }
  }, [idsCancelados, somLigado])

  /**
   * Insiste enquanto ninguém atende.
   *
   * Um toque só se perde: a pessoa está na chapa, de costas para a tela. A
   * cada 45 segundos o sino repete, e para sozinho no instante em que a fila
   * de espera esvazia — não é alarme que alguém precise desligar.
   */
  useEffect(() => {
    if (!somLigado || esperando.length === 0) return
    const relogio = setInterval(() => tocarSino(0.22), 45_000)
    return () => clearInterval(relogio)
  }, [somLigado, esperando.length])

  /**
   * O som escolhido continua ligado amanhã.
   *
   * O navegador exige uma interação antes de deixar tocar, e isso não tem como
   * contornar. O que dá para evitar é a pessoa ter de achar o botão a cada
   * carregamento: a escolha fica guardada, e o primeiro clique em qualquer
   * lugar da página destrava o som de novo.
   */
  useEffect(() => {
    // Nos dois casos a leitura é adiada para depois do quadro: chamar setState
    // direto dentro do efeito encadeia renderizações, e o lint pega.
    if (localStorage.getItem("tronvix_comanda_automatica") === "ligada") {
      queueMicrotask(() => setImprimindoSozinho(true))
    }

    if (localStorage.getItem("tronvix_som_do_balcao") !== "ligado") return

    function destravar() {
      if (destravarSom()) queueMicrotask(() => setSomLigado(true))
    }

    // Já pode estar liberado, se a pessoa navegou até aqui de dentro do site.
    destravar()
    document.addEventListener("pointerdown", destravar, { once: true })
    document.addEventListener("keydown", destravar, { once: true })

    return () => {
      document.removeEventListener("pointerdown", destravar)
      document.removeEventListener("keydown", destravar)
    }
  }, [])

  useEffect(() => {
    const supabase = criarClienteDoNavegador()
    const canal = supabase
      .channel(`painel:${restauranteId}`)
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "orders",
          filter: `restaurant_id=eq.${restauranteId}`,
        },
        () => router.refresh(),
      )
      .subscribe()

    return () => {
      // Canal esquecido aberto e conexao viva gastando recurso de quem ja saiu
      // da tela.
      supabase.removeChannel(canal)
    }
  }, [restauranteId, router])

  const aviso = (
    <AvisoDePedidos
      somLigado={somLigado}
      chavePublica={chavePublicaDePush}
      imprimindoSozinho={imprimindoSozinho}
      aoMudarImpressao={(ligando) => {
        setImprimindoSozinho(ligando)
        localStorage.setItem("tronvix_comanda_automatica", ligando ? "ligada" : "desligada")
      }}
      aoMudarSom={(ligando) => {
        setSomLigado(ligando)
        localStorage.setItem("tronvix_som_do_balcao", ligando ? "ligado" : "desligado")
        // O clique é a interação que autoriza o navegador a tocar — e o toque
        // confirma para a pessoa que o alerta funciona.
        if (ligando) {
          destravarSom()
          tocarSino()
        }
      }}
    />
  )

  if (pedidos.length === 0) {
    return (
      <div className="space-y-4">
        {aviso}
        <div className="rounded-xl border border-dashed p-12 text-center">
          <Clock className="mx-auto size-8 text-muted-foreground" aria-hidden="true" />
          <p className="mt-3 font-semibold">Nenhum pedido em aberto</p>
          <p className="mt-1 text-sm text-muted-foreground">
            Quando entrar um pedido, ele aparece aqui sozinho.
          </p>
        </div>
      </div>
    )
  }

  return (
    <div className="space-y-4">
      {aviso}
      <Cancelamentos pedidos={cancelados} />
      <Quadro pedidos={pedidos} preparoMedioEmMinutos={preparoMedioEmMinutos} />
    </div>
  )
}

/**
 * As colunas do quadro.
 *
 * A ordem e a do trabalho, da esquerda para a direita: chega, aceita, faz,
 * fica pronto, sai. Um pedido anda uma coluna por vez, e a coluna em que ele
 * esta diz o que falta fazer com ele.
 *
 * "Saiu" junta entrega na rua e pedido ja servido na mesa: das duas, o que o
 * balcao precisa saber e a mesma coisa — este ja nao esta na minha mao.
 */
const COLUNAS = [
  {
    chave: "recebido",
    titulo: "Chegou",
    detalhe: "esperando você aceitar",
    situacoes: ["awaiting_payment", "received"] as SituacaoDoPedido[],
    urgente: true,
  },
  {
    chave: "aceito",
    titulo: "Aceito",
    detalhe: "na fila da cozinha",
    situacoes: ["confirmed"] as SituacaoDoPedido[],
    urgente: false,
  },
  {
    chave: "preparo",
    titulo: "Em preparo",
    detalhe: "no fogo",
    situacoes: ["preparing"] as SituacaoDoPedido[],
    urgente: false,
  },
  {
    chave: "pronto",
    titulo: "Pronto",
    detalhe: "esperando sair",
    situacoes: ["ready"] as SituacaoDoPedido[],
    urgente: true,
  },
  {
    chave: "saiu",
    titulo: "Saiu",
    detalhe: "na rua ou na mesa",
    situacoes: ["out_for_delivery"] as SituacaoDoPedido[],
    urgente: false,
  },
] as const

/**
 * Os cancelamentos recentes, numa faixa acima do quadro.
 *
 * Nao e uma coluna porque nao e uma etapa do trabalho: e um aviso. Como coluna
 * ficava em sexto lugar, fora da tela, e o pedido que o cliente desistiu sumia
 * em silencio enquanto a cozinha continuava fazendo a comida.
 *
 * Some sozinha depois de vinte minutos. Aviso que nao some vira paisagem.
 */
function Cancelamentos({ pedidos }: { pedidos: PedidoDaFila[] }) {
  if (pedidos.length === 0) return null

  return (
    <div className="space-y-2">
      {pedidos.map((p) => (
        <div
          key={p.id}
          className="flex flex-wrap items-center gap-x-3 gap-y-1 rounded-xl border border-destructive/40 bg-destructive/5 px-4 py-3 text-sm"
        >
          <Ban className="size-4 shrink-0 text-destructive" aria-hidden="true" />
          <span className="font-bold">nº {p.number}</span>
          <span className="font-semibold text-destructive">
            {p.cancelled_by === "cliente"
              ? "cancelado pelo cliente"
              : p.cancelled_by === "plataforma"
                ? "cancelado pela plataforma"
                : p.status === "rejected"
                  ? "recusado por vocês"
                  : "cancelado por vocês"}
          </span>
          <span className="min-w-0 flex-1 truncate text-muted-foreground">
            {p.customer_name} · {p.order_items.map((i) => `${i.quantity}× ${i.product_name}`).join(", ")}
          </span>
          {p.cancellation_reason && p.cancelled_by !== "cliente" ? (
            <span className="text-xs text-muted-foreground">{p.cancellation_reason}</span>
          ) : null}
        </div>
      ))}
    </div>
  )
}

function Quadro({
  pedidos,
  preparoMedioEmMinutos,
}: {
  pedidos: PedidoDaFila[]
  preparoMedioEmMinutos: number
}) {
  return (
    // Rolagem horizontal, e nao colunas que encolhem: cinco colunas espremidas
    // num monitor de balcao viram cinco tiras ilegiveis. Quem tem tela larga ve
    // tudo; quem nao tem, arrasta.
    <div className="-mx-4 overflow-x-auto px-4 pb-2 md:-mx-6 md:px-6">
      <div className="flex min-w-max gap-3">
        {COLUNAS.map((coluna) => {
          const daColuna = pedidos.filter((p) =>
            coluna.situacoes.includes(p.status as SituacaoDoPedido),
          )

          return (
            <section key={coluna.chave} className="w-[19rem] shrink-0">
              <header className="flex items-baseline gap-2 px-1 pb-2">
                <h2 className="text-sm font-bold uppercase tracking-wide">{coluna.titulo}</h2>
                <span
                  className={`rounded-full px-2 py-0.5 text-xs font-bold ${
                    daColuna.length > 0 && coluna.urgente
                      ? "bg-marca text-white"
                      : "bg-muted text-muted-foreground"
                  }`}
                >
                  {daColuna.length}
                </span>
                <span className="truncate text-[11px] text-muted-foreground">
                  {coluna.detalhe}
                </span>
              </header>

              <div className="space-y-3 rounded-xl bg-muted/50 p-2">
                {daColuna.map((p) => (
                  <CartaoDoPedido
                    key={p.id}
                    pedido={p}
                    preparoMedioEmMinutos={preparoMedioEmMinutos}
                  />
                ))}

                {daColuna.length === 0 ? (
                  <p className="px-2 py-6 text-center text-xs text-muted-foreground">
                    vazio
                  </p>
                ) : null}
              </div>
            </section>
          )
        })}

      </div>
    </div>
  )
}

function CartaoDoPedido({
  pedido: p,
  preparoMedioEmMinutos,
}: {
  pedido: PedidoDaFila
  preparoMedioEmMinutos: number
}) {
  const [enviando, iniciar] = useTransition()
  const [erro, setErro] = useState<string | null>(null)
  const [recusando, setRecusando] = useState(false)
  const [motivo, setMotivo] = useState("")

  const situacao = p.status as SituacaoDoPedido
  const tipo = p.fulfillment as TipoDeEntrega
  const novo = situacao === "received"
  const espera = minutosDesde(p.created_at)
  // Cinco minutos parado num pedido novo e o limite de paciencia de quem
  // pediu. Depois disso o cartao grita.
  const atrasado = novo && espera >= 5

  // O proximo passo natural, ignorando cancelar/recusar: a cozinha aperta um
  // botao que diz o que vem agora, nao escolhe entre nove estados.
  const destino = proximasSituacoesDoPedido(situacao, tipo).find(
    (s) => s !== "cancelled" && s !== "rejected",
  )

  const pagamento = p.payments[0]
  const naEntrega = pagamento?.timing === "on_delivery"

  // Pix pelo site, ainda não confirmado. É o único caso em que o pedido está
  // parado esperando a loja, e não a cozinha.
  const esperandoPix =
    situacao === "awaiting_payment" &&
    pagamento?.method === "pix" &&
    pagamento.status !== "paid"

  /**
   * Chamar o entregador é decisão separada de despachar.
   *
   * Dá para chamar já no preparo: o entregador recebe a previsão e sai na hora
   * de chegar junto com a comida, em vez de correr até aqui e esperar de pé.
   */
  const corrida = p.deliveries?.status ?? null
  const podeChamar =
    tipo === "delivery" &&
    corrida === "pending" &&
    (situacao === "confirmed" || situacao === "preparing" || situacao === "ready")
  const procurandoEntregador = corrida === "searching_courier"

  const [minutos, setMinutos] = useState(() => {
    // Desconta o que a cozinha já gastou: num pedido que entrou há dez minutos,
    // prometer o preparo médio inteiro manda o entregador chegar tarde.
    const restante = preparoMedioEmMinutos - minutosDesde(p.created_at)
    return String(Math.max(5, restante))
  })

  function avancar() {
    if (!destino) return
    setErro(null)
    iniciar(async () => {
      const r = await avancarPedido(p.id, destino)
      if (!r.ok) setErro(r.erro)
    })
  }

  function chamar() {
    setErro(null)
    iniciar(async () => {
      const r = await chamarEntregador(p.id, Number(minutos))
      if (!r.ok) setErro(r.erro)
    })
  }

  function recusar() {
    setErro(null)
    iniciar(async () => {
      const r = await recusarPedido(p.id, motivo)
      if (r.ok) setRecusando(false)
      else setErro(r.erro)
    })
  }

  return (
    <article
      className={`rounded-xl border bg-card p-4 ${atrasado ? "border-destructive" : novo ? "border-marca/50" : ""}`}
    >
      <header className="flex flex-wrap items-center gap-2">
        <span className="text-lg font-bold">nº {p.number}</span>
        <Badge variant={novo ? "default" : "secondary"}>
          {novo ? "Novo pedido" : ROTULO_DA_SITUACAO[situacao]}
        </Badge>
        <span
          className={`ml-auto text-sm ${atrasado ? "font-bold text-destructive" : "text-muted-foreground"}`}
        >
          {espera === 0 ? "agora" : `há ${espera} min`}
        </span>
      </header>

      <p className="mt-2 font-semibold">{p.customer_name}</p>

      <p className="mt-0.5 flex flex-wrap items-center gap-x-3 gap-y-1 text-sm text-muted-foreground">
        <span className="inline-flex items-center gap-1.5">
          {tipo === "delivery" ? (
            <Bike className="size-3.5" aria-hidden="true" />
          ) : tipo === "dine_in" ? (
            <UtensilsCrossed className="size-3.5" aria-hidden="true" />
          ) : (
            <Store className="size-3.5" aria-hidden="true" />
          )}
          {/* Na mesa, o destino E a informacao: quem prepara precisa saber para
              onde o prato vai antes de saber o nome de quem pediu. Por isso o
              rotulo da mesa vem no lugar da palavra "Mesa". */}
          {tipo === "delivery"
            ? "Entrega"
            : tipo === "dine_in"
              ? (p.table_label ?? "Mesa")
              : "Retirada"}
        </span>
        {tipo === "delivery" && p.address_summary ? (
          <span>
            {p.address_summary}
            {p.address_district ? ` · ${p.address_district}` : ""}
          </span>
        ) : null}
      </p>

      <ul className="mt-3 space-y-1 border-t pt-3 text-sm">
        {p.order_items.map((i) => (
          <li key={i.id} className="flex gap-2">
            <span className="font-bold text-marca">{i.quantity}×</span>
            <span className="flex-1">
              {i.product_name}
              {i.notes ? (
                <em className="block text-xs font-semibold not-italic text-marca-forte">
                  “{i.notes}”
                </em>
              ) : null}
            </span>
          </li>
        ))}
      </ul>

      {p.notes ? (
        <p className="mt-3 flex gap-2 rounded-lg bg-marca-suave p-2.5 text-sm text-marca-forte">
          <StickyNote className="mt-0.5 size-4 shrink-0" aria-hidden="true" />
          {p.notes}
        </p>
      ) : null}

      {esperandoPix ? (
        <div className="mt-3 rounded-lg border border-amber-300 bg-amber-50 p-3 dark:border-amber-900 dark:bg-amber-950/30">
          <p className="text-sm font-semibold">Aguardando Pix</p>
          <p className="mt-0.5 text-xs text-muted-foreground">
            O cliente recebeu o código. Confirme quando o dinheiro entrar na conta — procure
            por <strong>TF{p.number}</strong> no extrato.
          </p>
          <Button
            size="sm"
            className="mt-2 w-full"
            disabled={enviando}
            onClick={() =>
              iniciar(async () => {
                const r = await confirmarPix(p.id)
                if (!r.ok) setErro(r.erro)
              })
            }
          >
            Recebi o Pix
          </Button>
        </div>
      ) : null}

      <footer className="mt-4 flex flex-wrap items-center justify-between gap-3 border-t pt-3">
        <span className="inline-flex items-center gap-1.5 text-sm">
          <Wallet className="size-4 text-muted-foreground" aria-hidden="true" />
          {naEntrega ? (
            <>
              Receber {tipo === "dine_in" ? "na mesa " : ""}
              <strong>{formatarReais(p.total_cents)}</strong> em{" "}
              {FORMA[pagamento.method] ?? pagamento.method}
            </>
          ) : esperandoPix ? (
            <>
              A receber · <strong>{formatarReais(p.total_cents)}</strong> por Pix
            </>
          ) : (
            <>
              Pago · <strong>{formatarReais(p.total_cents)}</strong>
            </>
          )}
        </span>

        <div className="flex gap-2">
          {/* Reimprimir. Comanda cai atrás do balcão, papel acaba no meio, o
              garçom leva a errada — e a fila não pode depender de ninguém ter
              guardado o papel. */}
          <Button
            variant="ghost"
            size="sm"
            aria-label={`Imprimir a comanda do pedido ${p.number}`}
            onClick={() => void imprimirComanda(p.id)}
          >
            <Printer className="size-4" aria-hidden="true" />
          </Button>
          {novo || esperandoPix ? (
            <Button
              variant="outline"
              size="sm"
              onClick={() => setRecusando((v) => !v)}
              disabled={enviando}
            >
              Recusar
            </Button>
          ) : null}
          {/* Sem "Confirmar pedido" enquanto o Pix não cai: quem solta o pedido
              é o botão de recebimento, e ter dois caminhos para a cozinha seria
              o caminho de mandar comida que ninguém pagou. */}
          {destino && !esperandoPix ? (
            <Button size="sm" onClick={avancar} disabled={enviando}>
              {ACAO_DA_SITUACAO[destino]}
            </Button>
          ) : null}
        </div>
      </footer>

      {/* Chamar entregador fica FORA da linha de botões de propósito: não é o
          próximo passo do pedido, é uma segunda decisão que corre em paralelo
          à cozinha. Misturado com "Aceitar" e "Pronto", viraria mais um botão
          na sequência — e quem está no balcão apertaria sem pensar no número. */}
      {podeChamar ? (
        <div className="mt-3 flex flex-wrap items-center gap-2 rounded-lg border border-dashed p-3">
          <Bike className="size-4 shrink-0 text-muted-foreground" aria-hidden="true" />
          <label htmlFor={`minutos-${p.id}`} className="text-sm text-muted-foreground">
            Fica pronto em
          </label>
          <input
            id={`minutos-${p.id}`}
            type="number"
            min={0}
            max={180}
            value={minutos}
            onChange={(e) => setMinutos(e.target.value)}
            className="w-16 rounded-md border bg-background px-2 py-1 text-sm"
          />
          <span className="text-sm text-muted-foreground">min</span>
          <Button
            size="sm"
            variant="outline"
            className="ml-auto"
            onClick={chamar}
            disabled={enviando}
          >
            Chamar entregador
          </Button>
        </div>
      ) : procurandoEntregador ? (
        <p className="mt-3 flex items-center gap-2 rounded-lg border border-dashed p-3 text-sm text-muted-foreground">
          <Bike className="size-4 shrink-0" aria-hidden="true" />
          Procurando entregador
          {p.ready_forecast_at ? ` · avisamos que fica pronto ${quando(p.ready_forecast_at)}` : null}
        </p>
      ) : null}

      {recusando ? (
        <div className="mt-3 space-y-2 rounded-lg border p-3">
          <label htmlFor={`motivo-${p.id}`} className="text-sm text-muted-foreground">
            O cliente vê esta mensagem. Diga o motivo — acabou o item, fora da área,
            fechando a cozinha.
          </label>
          <div className="flex gap-2">
            <input
              id={`motivo-${p.id}`}
              value={motivo}
              onChange={(e) => setMotivo(e.target.value)}
              className="h-10 flex-1 rounded-lg border bg-background px-3 text-sm"
              placeholder="Motivo"
            />
            <Button variant="destructive" size="sm" onClick={recusar} disabled={enviando}>
              Recusar
            </Button>
          </div>
        </div>
      ) : null}

      {erro ? (
        <p role="alert" className="mt-3 text-sm font-medium text-destructive">
          {erro}
        </p>
      ) : null}
    </article>
  )
}
