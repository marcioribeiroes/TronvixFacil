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
      // A tag é o destino, e não um texto fixo. Assim os avisos DO MESMO
      // pedido se substituem — "aceito" vira "saiu para entrega" no mesmo
      // lugar da tela de bloqueio, em vez de empilhar três — enquanto pedidos
      // diferentes, e a fila do balcão, seguem separados. Com uma tag só para
      // tudo, o aviso de um pedido apagava o do outro.
      tag: aviso.url,
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
      // Qualquer aba do site serve. Antes procurava só por "/painel", então o
      // aviso do cliente — que leva a /pedidos/<id> — nunca reaproveitava a
      // aba aberta e abria uma janela nova a cada toque.
      for (const aba of abas) {
        if ("focus" in aba) {
          if ("navigate" in aba) aba.navigate(destino)
          return aba.focus()
        }
      }
      return self.clients.openWindow(destino)
    }),
  )
})
