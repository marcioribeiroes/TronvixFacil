/**
 * Avisa quem precisa saber que o pedido andou — com o navegador fechado.
 *
 * Sao dois publicos, e eles nao se misturam:
 *
 *   A LOJA      quando o pedido entra. O aviso sonoro da fila so funciona com
 *               a aba aberta; quem fecha o notebook voltava a nao saber.
 *
 *   QUEM PEDIU  quando o pedido anda. Ate aqui o cliente nao era avisado de
 *               nada e ficava reabrindo o aplicativo para ver se tinha mudado
 *               — que e exatamente o que o push existe para evitar.
 *
 * Roda no Supabase, nao no Next: o banco esta na nuvem e nao alcanca o
 * servidor de desenvolvimento de ninguem.
 *
 * Entra por webhook do banco, com o corpo padrao do Supabase:
 *   { type: "INSERT" | "UPDATE", record: { ... }, old_record: { ... } }
 */

import webpush from "npm:web-push@3.6.7"
import { createClient } from "jsr:@supabase/supabase-js@2"

const VAPID_PUBLICA = Deno.env.get("VAPID_CHAVE_PUBLICA")!
const VAPID_PRIVADA = Deno.env.get("VAPID_CHAVE_PRIVADA")!
const VAPID_CONTATO = Deno.env.get("VAPID_CONTATO") ?? "mailto:suporte@tronvixfacil.com.br"

webpush.setVapidDetails(VAPID_CONTATO, VAPID_PUBLICA, VAPID_PRIVADA)

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  // Chave de servico: a funcao le inscricoes de gente que nao e ela, e nao
  // age em nome de nenhum usuario.
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
)

const emReais = (centavos: number) =>
  (centavos / 100).toLocaleString("pt-BR", { style: "currency", currency: "BRL" })

type Pedido = {
  id: string
  number: number
  status: string
  fulfillment: string
  customer_id: string | null
  customer_name: string
  restaurant_id: string
  total_cents: number
  cancellation_reason: string | null
}

type Aviso = { titulo: string; corpo: string; url: string }

/**
 * O que dizer a quem pediu, em cada virada.
 *
 * O texto fala do pedido, e nao do sistema: "a loja confirmou", nunca "status
 * alterado para confirmed". Quem le esta com fome, no meio de outra coisa, sem
 * contexto nenhum na cabeca.
 *
 * Devolve `null` quando a virada nao interessa ao cliente. O gatilho ja filtra
 * antes, mas esta funcao nao confia nisso: um gatilho mais largo amanha nao
 * deve virar enxurrada de aviso.
 */
function avisoParaOCliente(pedido: Pedido): Aviso | null {
  const numero = `Pedido nº ${pedido.number}`
  const url = `/pedidos/${pedido.id}`

  switch (pedido.status) {
    case "confirmed":
      return {
        titulo: "Pedido aceito",
        corpo: `${numero} · a loja confirmou e já começou a preparar.`,
        url,
      }

    case "ready":
      // Em entrega isto nao vira aviso: quem pediu em casa nao faz nada com
      // "pronto", e o passo seguinte ja avisa. Em retirada e mesa, e A hora.
      if (pedido.fulfillment === "delivery") return null
      return {
        titulo: pedido.fulfillment === "pickup" ? "Pode buscar" : "Seu pedido está pronto",
        corpo:
          pedido.fulfillment === "pickup"
            ? `${numero} · pronto para retirada no balcão.`
            : `${numero} · saindo da cozinha agora.`,
        url,
      }

    case "out_for_delivery":
      return {
        titulo: "Saiu para entrega",
        corpo: `${numero} · o entregador está a caminho.`,
        url,
      }

    case "delivered":
      return { titulo: "Pedido entregue", corpo: `${numero} · bom apetite.`, url }

    case "rejected":
      return {
        titulo: "A loja não pôde aceitar",
        corpo: pedido.cancellation_reason
          ? `${numero} · ${pedido.cancellation_reason}`
          : `${numero} · o pedido foi recusado.`,
        url,
      }

    case "cancelled":
      return {
        titulo: "Pedido cancelado",
        corpo: `${numero} · ${pedido.cancellation_reason ?? "o pedido foi cancelado."}`,
        url,
      }

    default:
      return null
  }
}

/** Para quem mandar, e o que. Nulo quando esta virada nao e de ninguem. */
async function destinatarios(
  pedido: Pedido,
  anterior: { status?: string } | null,
): Promise<{ usuarios: string[]; aviso: Aviso } | null> {
  // A loja, quando o pedido entra.
  if (pedido.status === "received" && anterior?.status !== "received") {
    const { data: equipe } = await supabase
      .from("restaurant_members")
      .select("user_id")
      .eq("restaurant_id", pedido.restaurant_id)
      .eq("is_active", true)
      .is("deleted_at", null)

    const usuarios = (equipe ?? []).map((m) => m.user_id)
    if (usuarios.length === 0) return null

    return {
      usuarios,
      aviso: {
        titulo: `Pedido nº ${pedido.number}`,
        corpo: `${pedido.customer_name} · ${emReais(pedido.total_cents)}`,
        url: "/painel/pedidos",
      },
    }
  }

  // Quem pediu, quando o pedido anda. Sem `customer_id` nao ha a quem avisar:
  // e o pedido lancado no balcao, em nome de alguem que nao tem conta.
  if (!pedido.customer_id) return null

  const aviso = avisoParaOCliente(pedido)
  if (!aviso) return null

  return { usuarios: [pedido.customer_id], aviso }
}

Deno.serve(async (req) => {
  try {
    const corpo = await req.json()
    const pedido = corpo.record as Pedido | undefined
    const anterior = (corpo.old_record ?? null) as { status?: string } | null

    if (!pedido?.id) return new Response("sem pedido", { status: 400 })

    // Status que nao mudou nao avisa ninguem. A tabela tem gatilho de
    // `updated_at`, entao UPDATE que nao mexe no status e a maioria deles.
    if (corpo.type === "UPDATE" && anterior?.status === pedido.status) {
      return new Response("status nao mudou", { status: 200 })
    }

    const alvo = await destinatarios(pedido, anterior)
    if (!alvo) return new Response("nada a avisar", { status: 200 })

    const { data: inscricoes } = await supabase
      .from("push_subscriptions")
      .select("id, endpoint, p256dh, auth")
      .in("user_id", alvo.usuarios)

    const carga = JSON.stringify(alvo.aviso)

    let entregues = 0
    const mortas: string[] = []

    for (const i of inscricoes ?? []) {
      try {
        await webpush.sendNotification(
          { endpoint: i.endpoint, keys: { p256dh: i.p256dh, auth: i.auth } },
          carga,
        )
        entregues++
      } catch (e) {
        // 404 e 410 sao o navegador dizendo que a inscricao morreu: aba
        // desinstalada, permissao revogada, aparelho trocado. Guardar
        // inscricao morta so faz a proxima entrega demorar mais.
        const status = (e as { statusCode?: number }).statusCode
        if (status === 404 || status === 410) mortas.push(i.id)
      }
    }

    if (mortas.length > 0) {
      await supabase.from("push_subscriptions").delete().in("id", mortas)
    }

    return Response.json({ entregues, removidas: mortas.length })
  } catch (e) {
    return new Response(`erro: ${e instanceof Error ? e.message : e}`, { status: 500 })
  }
})
