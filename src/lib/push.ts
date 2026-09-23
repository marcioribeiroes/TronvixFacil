/**
 * A mecanica de inscrever este navegador no push.
 *
 * Vive fora dos componentes porque sao dois que precisam dela, e por motivos
 * diferentes: o balcao quer saber que entrou pedido, e quem pediu quer saber
 * que o pedido andou. A conversa com o navegador e a mesma nos dois casos —
 * e e cheia de detalhe que nao se quer manter em duas copias.
 */

/** O navegador entrega a chave em base64url; a API de push quer bytes. */
export function paraBytes(base64url: string) {
  const preenchido = base64url.padEnd(
    base64url.length + ((4 - (base64url.length % 4)) % 4),
    "=",
  )
  const base64 = preenchido.replace(/-/g, "+").replace(/_/g, "/")
  const bruto = atob(base64)
  return Uint8Array.from([...bruto].map((c) => c.charCodeAt(0)))
}

/** E o caminho de volta: bytes da inscricao viram o texto que o banco guarda. */
export function comoTexto(chave: ArrayBuffer | null) {
  if (!chave) return ""
  return btoa(String.fromCharCode(...new Uint8Array(chave)))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "")
}

export type InscricaoDoAparelho = {
  endpoint: string
  p256dh: string
  auth: string
  descricao: string
}

export function suportaPush() {
  return (
    typeof navigator !== "undefined" &&
    "serviceWorker" in navigator &&
    typeof window !== "undefined" &&
    "PushManager" in window
  )
}

/** A inscricao que ja existe neste navegador, se existir. */
export async function inscricaoExistente() {
  if (!suportaPush()) return null
  const registro = await navigator.serviceWorker.register("/sw-avisos.js")
  return registro.pushManager.getSubscription()
}

/**
 * Pede permissao e inscreve.
 *
 * Estoura com mensagem em portugues quando a pessoa nega: quem chamou precisa
 * dizer isso na tela, e "NotAllowedError" nao e frase que se mostre a
 * ninguem.
 */
export async function inscreverNesteAparelho(
  chavePublica: string,
): Promise<InscricaoDoAparelho> {
  const permissao = await Notification.requestPermission()
  if (permissao !== "granted") {
    throw new Error("O navegador não autorizou os avisos.")
  }

  const registro = await navigator.serviceWorker.register("/sw-avisos.js")
  const inscricao = await registro.pushManager.subscribe({
    // Obrigatorio e sem alternativa: o navegador nao aceita push que a pessoa
    // nao possa ver.
    userVisibleOnly: true,
    applicationServerKey: paraBytes(chavePublica),
  })

  return {
    endpoint: inscricao.endpoint,
    p256dh: comoTexto(inscricao.getKey("p256dh")),
    auth: comoTexto(inscricao.getKey("auth")),
    descricao: navigator.userAgent.slice(0, 120),
  }
}
