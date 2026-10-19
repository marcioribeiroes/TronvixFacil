import { registrarErro } from "@/lib/registrar-erro"

/**
 * Os erros do navegador: o que quebra na tela do cliente e o servidor nunca
 * fica sabendo. Vao para o mesmo registro (/admin/erros).
 *
 * Fica de fora o ruido que nao e nosso: extensao do navegador e o aviso
 * inofensivo do ResizeObserver, que alguns navegadores disparam a toa.
 */
const RUIDO = [/ResizeObserver loop/i, /chrome-extension:\/\//i, /moz-extension:\/\//i]

function ehRuido(texto: string) {
  return RUIDO.some((r) => r.test(texto))
}

window.addEventListener("error", (evento) => {
  const mensagem = evento.message || String(evento.error ?? "")
  const pilha = evento.error instanceof Error ? evento.error.stack : null
  if (!mensagem || ehRuido(`${mensagem} ${pilha ?? ""} ${evento.filename ?? ""}`)) return
  void registrarErro({
    origem: "navegador",
    mensagem,
    pilha,
    endereco: window.location.pathname,
    contexto: { arquivo: evento.filename, linha: evento.lineno, navegador: navigator.userAgent },
  })
})

window.addEventListener("unhandledrejection", (evento) => {
  const motivo = evento.reason
  const mensagem = motivo instanceof Error ? motivo.message : String(motivo)
  const pilha = motivo instanceof Error ? motivo.stack : null
  if (!mensagem || ehRuido(`${mensagem} ${pilha ?? ""}`)) return
  void registrarErro({
    origem: "navegador",
    mensagem,
    pilha,
    endereco: window.location.pathname,
    contexto: { tipo: "promessa", navegador: navigator.userAgent },
  })
})
