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
 *
 * Dois canais para as mesmas pessoas: o navegador (Web Push, `push_subscriptions`)
 * e o celular (Firebase Cloud Messaging, `device_tokens`). Sem a conta de
 * servico do Firebase configurada, o celular fica de fora e o navegador segue
 * como antes.
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

// ---------------------------------------------------------------------------
// Firebase Cloud Messaging (celular)
//
// A API v1 pede um token OAuth da conta de servico do projeto. O token e
// gerado aqui, assinando um JWT com a chave privada (RS256), e vale uma hora —
// guardado enquanto a funcao estiver quente.
// ---------------------------------------------------------------------------

type ContaDeServico = { project_id: string; client_email: string; private_key: string }

const CONTA_FIREBASE: ContaDeServico | null = (() => {
  const bruto = Deno.env.get("FIREBASE_CONTA_DE_SERVICO")
  if (!bruto) return null
  try {
    return JSON.parse(bruto) as ContaDeServico
  } catch {
    return null
  }
})()

let tokenGoogle: { valor: string; expiraEm: number } | null = null

const base64url = (dados: ArrayBuffer | Uint8Array | string) => {
  const bytes =
    typeof dados === "string" ? new TextEncoder().encode(dados) : new Uint8Array(dados)
  let texto = ""
  for (const b of bytes) texto += String.fromCharCode(b)
  return btoa(texto).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")
}

async function tokenDoFirebase(conta: ContaDeServico): Promise<string> {
  const agora = Math.floor(Date.now() / 1000)
  if (tokenGoogle && tokenGoogle.expiraEm - 60 > agora) return tokenGoogle.valor

  const cabecalho = base64url(JSON.stringify({ alg: "RS256", typ: "JWT" }))
  const corpo = base64url(
    JSON.stringify({
      iss: conta.client_email,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: "https://oauth2.googleapis.com/token",
      iat: agora,
      exp: agora + 3600,
    }),
  )

  const pem = conta.private_key
    .replace(/-----[^-]+-----/g, "")
    .replace(/\s+/g, "")
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0))
  const chave = await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  )
  const assinatura = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    chave,
    new TextEncoder().encode(`${cabecalho}.${corpo}`),
  )

  const resposta = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${cabecalho}.${corpo}.${base64url(assinatura)}`,
    }),
  })
  if (!resposta.ok) throw new Error(`oauth ${resposta.status}`)
  const json = (await resposta.json()) as { access_token: string; expires_in: number }
  tokenGoogle = { valor: json.access_token, expiraEm: agora + json.expires_in }
  return json.access_token
}

/**
 * Manda para cada aparelho. Devolve quantos chegaram e quais tokens morreram
 * (app desinstalado, token trocado) — esses saem da tabela.
 */
async function enviarAoCelular(
  tokens: { id: string; token: string }[],
  aviso: Aviso,
  pedidoId: string,
): Promise<{ entregues: number; mortos: string[] }> {
  if (!CONTA_FIREBASE || tokens.length === 0) return { entregues: 0, mortos: [] }

  const acesso = await tokenDoFirebase(CONTA_FIREBASE)
  const url = `https://fcm.googleapis.com/v1/projects/${CONTA_FIREBASE.project_id}/messages:send`

  let entregues = 0
  const mortos: string[] = []

  for (const t of tokens) {
    const resposta = await fetch(url, {
      method: "POST",
      headers: { Authorization: `Bearer ${acesso}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        message: {
          token: t.token,
          notification: { title: aviso.titulo, body: aviso.corpo },
          // O app abre no pedido certo ao tocar no aviso.
          data: { url: aviso.url, pedido: pedidoId },
          // Prioridade alta: pedido novo e para tocar agora, nao no proximo
          // lote que o Android achar conveniente.
          android: { priority: "HIGH", notification: { sound: "default" } },
          apns: { payload: { aps: { sound: "default" } } },
        },
      }),
    })

    if (resposta.ok) {
      entregues++
      continue
    }
    // 404 (UNREGISTERED) e 400 de token invalido: o aparelho nao existe mais.
    const erro = await resposta.text()
    if (resposta.status === 404 || erro.includes("UNREGISTERED") || erro.includes("registration token")) {
      mortos.push(t.id)
    }
  }

  return { entregues, mortos }
}

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

    // O celular. Um erro aqui nao pode derrubar o que o navegador ja entregou.
    let noCelular = { entregues: 0, mortos: [] as string[] }
    try {
      const { data: aparelhos } = await supabase
        .from("device_tokens")
        .select("id, token")
        .in("user_id", alvo.usuarios)
      noCelular = await enviarAoCelular(aparelhos ?? [], alvo.aviso, pedido.id)
      if (noCelular.mortos.length > 0) {
        await supabase.from("device_tokens").delete().in("id", noCelular.mortos)
      }
    } catch (e) {
      console.error("celular:", e instanceof Error ? e.message : e)
    }

    return Response.json({
      entregues,
      removidas: mortas.length,
      no_celular: noCelular.entregues,
      aparelhos_removidos: noCelular.mortos.length,
    })
  } catch (e) {
    return new Response(`erro: ${e instanceof Error ? e.message : e}`, { status: 500 })
  }
})
