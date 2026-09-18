"use client"

import { useEffect, useRef, useState, useTransition } from "react"
import { useRouter } from "next/navigation"
import { Bike, Clock, StickyNote, Store, Wallet,
  UtensilsCrossed,
} from "lucide-react"

import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
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
import { avancarPedido, confirmarPix, recusarPedido } from "@/modules/painel/pedidos"

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
  order_items: { id: string; product_name: string; quantity: number; notes: string | null }[]
  payments: { method: string; timing: string; status: string }[]
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
 * Toca o alerta de pedido novo.
 *
 * Som gerado na hora pela Web Audio API, sem arquivo: dois bipes curtos, o
 * segundo mais agudo. Arquivo de audio seria mais um recurso para hospedar e
 * mais uma coisa para faltar em producao - e o que precisa acontecer aqui e
 * simples, alguem levantar a cabeca.
 *
 * O navegador so deixa tocar depois de a pessoa ter interagido com a pagina.
 * Por isso o botao de ligar o som existe: o clique nele e a interacao que
 * autoriza, e nao ha como contornar isso - e protecao do navegador contra
 * paginas que gritam sozinhas.
 */
function tocarAlerta() {
  try {
    const Audio = window.AudioContext ?? (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext
    const contexto = new Audio()
    const agora = contexto.currentTime

    for (const [atraso, frequencia] of [
      [0, 880],
      [0.18, 1175],
    ] as const) {
      const oscilador = contexto.createOscillator()
      const volume = contexto.createGain()
      oscilador.frequency.value = frequencia
      oscilador.type = "sine"
      volume.gain.setValueAtTime(0.0001, agora + atraso)
      volume.gain.exponentialRampToValueAtTime(0.3, agora + atraso + 0.02)
      volume.gain.exponentialRampToValueAtTime(0.0001, agora + atraso + 0.16)
      oscilador.connect(volume).connect(contexto.destination)
      oscilador.start(agora + atraso)
      oscilador.stop(agora + atraso + 0.18)
    }
  } catch {
    // Sem som, a tela continua se atualizando. O alerta e ajuda, nao requisito.
  }
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
  restauranteId,
  chavePublicaDePush,
}: {
  pedidos: PedidoDaFila[]
  restauranteId: string
  chavePublicaDePush: string
}) {
  const router = useRouter()
  const [somLigado, setSomLigado] = useState(false)

  // Quantos pedidos novos havia na renderizacao anterior. E a comparacao que
  // diz se CHEGOU alguem, em vez de tocar a cada mudanca de estado - despachar
  // um pedido tambem mexe na fila e nao merece alarme.
  const novosAntes = useRef<number | null>(null)

  const novos = pedidos.filter((p) => p.status === "received").length

  useEffect(() => {
    const anterior = novosAntes.current
    novosAntes.current = novos

    if (anterior === null || novos <= anterior) return

    if (somLigado) tocarAlerta()

    // Aviso do sistema, para quem esta com a aba atras de outra janela.
    if (typeof Notification !== "undefined" && Notification.permission === "granted") {
      new Notification("Pedido novo", {
        body: `${novos} pedido(s) esperando aceite.`,
        tag: "pedido-novo",
      })
    }
  }, [novos, somLigado])

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
      aoMudarSom={(ligando) => {
        setSomLigado(ligando)
        // O clique é a interação que autoriza o navegador a tocar som — e o
        // primeiro bipe confirma para a pessoa que o alerta funciona.
        if (ligando) tocarAlerta()
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
      <Quadro pedidos={pedidos} />
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

function Quadro({ pedidos }: { pedidos: PedidoDaFila[] }) {
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
                  <CartaoDoPedido key={p.id} pedido={p} />
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

function CartaoDoPedido({ pedido: p }: { pedido: PedidoDaFila }) {
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

  function avancar() {
    if (!destino) return
    setErro(null)
    iniciar(async () => {
      const r = await avancarPedido(p.id, destino)
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
