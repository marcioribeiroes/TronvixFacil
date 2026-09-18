"use client"

import { useEffect, useState, useTransition } from "react"
import { Bell, BellOff, BellRing,
  Printer,
} from "lucide-react"

import { Button } from "@/components/ui/button"
import { ImpressoraTermica } from "@/components/painel/impressora-termica"
import {
  removerInscricaoDePush,
  salvarInscricaoDePush,
  temInscricao,
} from "@/modules/painel/avisos"

/**
 * O aviso de pedido novo, nas duas camadas.
 *
 *   som          toca na aba aberta. Imediato, e morre com a aba.
 *   push         chega com o navegador fechado. E o que faz o dono saber do
 *                pedido depois de fechar o notebook.
 *
 * As duas existem porque resolvem coisas diferentes. Push tem latencia de
 * segundos e passa pelo servico do fabricante; o som e instantaneo e nao
 * depende de ninguem. Num balcao em movimento, quem esta na tela precisa do
 * som; quem saiu precisa do push.
 */

/** O navegador entrega a chave em base64url; a API quer bytes. */
function paraBytes(base64url: string) {
  const preenchido = base64url.padEnd(
    base64url.length + ((4 - (base64url.length % 4)) % 4),
    "=",
  )
  const base64 = preenchido.replace(/-/g, "+").replace(/_/g, "/")
  const bruto = atob(base64)
  return Uint8Array.from([...bruto].map((c) => c.charCodeAt(0)))
}

function comoTexto(chave: ArrayBuffer | null) {
  if (!chave) return ""
  return btoa(String.fromCharCode(...new Uint8Array(chave)))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "")
}

export function AvisoDePedidos({
  somLigado,
  aoMudarSom,
  imprimindoSozinho,
  aoMudarImpressao,
  chavePublica,
}: {
  somLigado: boolean
  aoMudarSom: (ligado: boolean) => void
  /** A comanda sai na impressora assim que o pedido chega. */
  imprimindoSozinho: boolean
  aoMudarImpressao: (ligado: boolean) => void
  chavePublica: string
}) {
  const [enviando, iniciar] = useTransition()
  const [inscrito, setInscrito] = useState(false)
  // Começa como "sim" e só desliga se o navegador disser que não: assumir o
  // contrário esconderia o botão por um instante em todo carregamento.
  const [suportado, setSuportado] = useState(true)
  const [erro, setErro] = useState<string | null>(null)

  useEffect(() => {
    let vivo = true

    async function conferir() {
      if (!("serviceWorker" in navigator) || !("PushManager" in window)) {
        if (vivo) setSuportado(false)
        return
      }
      try {
        const registro = await navigator.serviceWorker.register("/sw-avisos.js")
        const inscricao = await registro.pushManager.getSubscription()
        if (!inscricao || !vivo) return
        // Pergunta ao servidor, e não ao navegador: a inscrição pode existir
        // aqui e ter sido removida lá — por 410 do serviço de push, ou porque
        // a pessoa entrou com outra conta neste mesmo aparelho.
        const existe = await temInscricao(inscricao.endpoint)
        if (vivo) setInscrito(existe)
      } catch {
        if (vivo) setSuportado(false)
      }
    }

    void conferir()
    return () => {
      vivo = false
    }
  }, [])

  function inscrever() {
    setErro(null)
    iniciar(async () => {
      try {
        const permissao = await Notification.requestPermission()
        if (permissao !== "granted") {
          setErro("O navegador não autorizou os avisos.")
          return
        }

        const registro = await navigator.serviceWorker.register("/sw-avisos.js")
        const inscricao = await registro.pushManager.subscribe({
          // Obrigatório e sem alternativa: o navegador não aceita push que a
          // pessoa não possa ver.
          userVisibleOnly: true,
          applicationServerKey: paraBytes(chavePublica),
        })

        const r = await salvarInscricaoDePush({
          endpoint: inscricao.endpoint,
          p256dh: comoTexto(inscricao.getKey("p256dh")),
          auth: comoTexto(inscricao.getKey("auth")),
          descricao: navigator.userAgent.slice(0, 120),
        })

        if (r.ok) setInscrito(true)
        else setErro(r.erro)
      } catch (e) {
        setErro(e instanceof Error ? e.message : "Não consegui ligar os avisos.")
      }
    })
  }

  function desinscrever() {
    setErro(null)
    iniciar(async () => {
      const registro = await navigator.serviceWorker.getRegistration("/sw-avisos.js")
      const inscricao = await registro?.pushManager.getSubscription()
      if (inscricao) {
        await removerInscricaoDePush(inscricao.endpoint)
        await inscricao.unsubscribe()
      }
      setInscrito(false)
    })
  }

  return (
    <div className="flex flex-wrap items-center justify-between gap-3 rounded-xl border bg-card p-3">
      <span className="text-sm text-muted-foreground">
        {imprimindoSozinho
          ? "A comanda sai na impressora assim que o pedido chega."
          : inscrito
          ? "Você recebe aviso mesmo com o navegador fechado."
          : somLigado
            ? "O som avisa enquanto esta aba estiver aberta. Ligue o aviso no aparelho para saber do pedido depois de fechá-la."
            : "Ligue os avisos para não depender de olhar a tela."}
      </span>

      <div className="flex flex-wrap gap-2">
        <ImpressoraTermica colunas={48} />

        <Button
          size="sm"
          variant={imprimindoSozinho ? "outline" : "ghost"}
          onClick={() => aoMudarImpressao(!imprimindoSozinho)}
        >
          <Printer className="size-4" aria-hidden="true" />
          {imprimindoSozinho ? "Imprimindo sozinho" : "Imprimir sozinho"}
        </Button>

        <Button
          size="sm"
          variant={somLigado ? "outline" : "default"}
          onClick={() => aoMudarSom(!somLigado)}
        >
          {somLigado ? (
            <>
              <BellOff className="size-4" aria-hidden="true" />
              Desligar som
            </>
          ) : (
            <>
              <Bell className="size-4" aria-hidden="true" />
              Ligar som
            </>
          )}
        </Button>

        {suportado ? (
          <Button
            size="sm"
            variant={inscrito ? "outline" : "default"}
            disabled={enviando}
            onClick={inscrito ? desinscrever : inscrever}
          >
            <BellRing className="size-4" aria-hidden="true" />
            {inscrito ? "Desligar no aparelho" : "Avisar neste aparelho"}
          </Button>
        ) : null}
      </div>

      {erro ? (
        <p role="alert" className="w-full text-sm font-medium text-destructive">
          {erro}
        </p>
      ) : null}
    </div>
  )
}
