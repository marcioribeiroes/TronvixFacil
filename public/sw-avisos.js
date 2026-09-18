/**
 * Service worker dos avisos.
 *
 * Existe por um motivo só: receber push com a página fechada. O navegador
 * mantém este arquivo vivo fora da aba, e é ele quem mostra a notificação —
 * por isso o aviso funciona com o notebook fechado, ao contrário do alerta
 * sonoro da fila, que morre junto com a aba.
 *
 * Não faz cache de nada. Um service worker que serve arquivos velhos é a
 * origem clássica de "atualizei e continua o mesmo", e aqui ele não tem essa
 * função.
 */

self.addEventListener("push", (evento) => {
  let aviso = { titulo: "Pedido novo", corpo: "", url: "/painel/pedidos" }

  try {
    aviso = { ...aviso, ...evento.data.json() }
  } catch {
    // Push sem corpo legível ainda vale como "olhe a fila".
  }

  evento.waitUntil(
    self.registration.showNotification(aviso.titulo, {
      body: aviso.corpo,
      icon: "/icone.svg",
      badge: "/icone.svg",
      // A mesma tag substitui o aviso anterior em vez de empilhar: três
      // pedidos em um minuto não devem virar três avisos na tela de bloqueio.
      tag: "pedido-novo",
      renotify: true,
      requireInteraction: true,
      data: { url: aviso.url },
    }),
  )
})

self.addEventListener("notificationclick", (evento) => {
  evento.notification.close()
  const destino = evento.notification.data?.url ?? "/painel/pedidos"

  evento.waitUntil(
    // Reaproveita a aba já aberta em vez de abrir outra: quem clica no aviso
    // quer ver a fila, não colecionar janelas.
    self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((abas) => {
      for (const aba of abas) {
        if (aba.url.includes("/painel") && "focus" in aba) {
          aba.navigate(destino)
          return aba.focus()
        }
      }
      return self.clients.openWindow(destino)
    }),
  )
})
