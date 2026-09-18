/**
 * Avisa a equipe do estabelecimento que entrou pedido — com o navegador
 * fechado.
 *
 * O aviso sonoro da fila so funciona com a aba aberta. Esta funcao e a outra
 * metade: um gatilho no banco a chama quando um pedido chega em `received`, e
 * ela dispara Web Push para quem trabalha naquele estabelecimento.
 *
 * Roda no Supabase, nao no Next: o banco esta na nuvem e nao alcanca o
 * servidor de desenvolvimento de ninguem. Uma funcao no mesmo lugar que o
 * banco e o unico jeito de isto funcionar antes de haver producao.
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
  // Chave de servico: a funcao precisa ler as inscricoes de TODA a equipe do
  // estabelecimento, e ela nao age em nome de nenhum usuario.
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
)

Deno.serve(async (req) => {
  try {
    const corpo = await req.json()
    const pedido = corpo.record
    const anterior = corpo.old_record

    if (!pedido?.id) return new Response("sem pedido", { status: 400 })

    // So avisa quando o pedido CHEGA a "recebido". Um pedido que anda de
    // "em preparo" para "pronto" tambem dispara o gatilho, e tocar o alarme
    // a cada passo treinaria a equipe a ignorar o alarme.
    const chegou = pedido.status === "received" && anterior?.status !== "received"
    if (!chegou) return new Response("nada a avisar", { status: 200 })

    const { data: equipe } = await supabase
      .from("restaurant_members")
      .select("user_id")
      .eq("restaurant_id", pedido.restaurant_id)
      .eq("is_active", true)
      .is("deleted_at", null)

    const donos = (equipe ?? []).map((m) => m.user_id)
    if (donos.length === 0) return new Response("sem equipe", { status: 200 })

    const { data: inscricoes } = await supabase
      .from("push_subscriptions")
      .select("id, endpoint, p256dh, auth")
      .in("user_id", donos)

    const aviso = JSON.stringify({
      titulo: `Pedido nº ${pedido.number}`,
      corpo: `${pedido.customer_name} · ${(pedido.total_cents / 100).toLocaleString("pt-BR", { style: "currency", currency: "BRL" })}`,
      url: "/painel/pedidos",
    })

    let entregues = 0
    const mortas: string[] = []

    for (const i of inscricoes ?? []) {
      try {
        await webpush.sendNotification(
          { endpoint: i.endpoint, keys: { p256dh: i.p256dh, auth: i.auth } },
          aviso,
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
