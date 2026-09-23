"use client"

import { useEffect, useState, useTransition } from "react"
import { Bell, BellRing } from "lucide-react"

import { Button } from "@/components/ui/button"
import { inscreverNesteAparelho, inscricaoExistente, suportaPush } from "@/lib/push"
import { salvarInscricaoDePush, temInscricao } from "@/modules/avisos"

/**
 * "Me avisa quando andar."
 *
 * Quem pede fica reabrindo a tela para ver se a loja aceitou — e esse e
 * exatamente o trabalho que o push existe para tirar das costas da pessoa. O
 * aviso chega com o navegador fechado e o telefone no bolso.
 *
 * Fica na tela de acompanhamento de propósito, e nao nas configuracoes da
 * conta: e aqui que a vontade existe. Pedir permissao de notificacao no
 * primeiro segundo do aplicativo, sem contexto, e o jeito mais rapido de
 * receber um "bloquear" que nunca mais se reverte.
 *
 * Some sozinho quando o pedido acaba: nao ha mais o que avisar, e oferecer
 * aviso de um pedido entregue e ruido.
 */
export function AvisosDoPedido({
  chavePublica,
  voltarPara,
  encerrado,
}: {
  chavePublica: string
  /** Para onde voltar se a sessao tiver expirado no meio. */
  voltarPara: string
  encerrado: boolean
}) {
  const [enviando, iniciar] = useTransition()
  const [inscrito, setInscrito] = useState(false)
  // Comeca como "sim" e so desliga se o navegador disser que nao: assumir o
  // contrario piscaria o bloco em todo carregamento.
  const [suportado, setSuportado] = useState(true)
  const [erro, setErro] = useState<string | null>(null)

  useEffect(() => {
    let vivo = true

    async function conferir() {
      if (!suportaPush()) {
        if (vivo) setSuportado(false)
        return
      }
      try {
        const inscricao = await inscricaoExistente()
        if (!inscricao || !vivo) return
        // Pergunta ao servidor, e nao ao navegador: a inscricao pode existir
        // aqui e ter sido removida la — por 410 do servico de push, ou porque
        // a pessoa entrou com outra conta neste mesmo aparelho.
        const existe = await temInscricao(inscricao.endpoint, voltarPara)
        if (vivo) setInscrito(existe)
      } catch {
        if (vivo) setSuportado(false)
      }
    }

    void conferir()
    return () => {
      vivo = false
    }
  }, [voltarPara])

  if (!suportado || encerrado) return null

  function ligar() {
    setErro(null)
    iniciar(async () => {
      try {
        const inscricao = await inscreverNesteAparelho(chavePublica)
        const r = await salvarInscricaoDePush(inscricao, voltarPara)
        if (r.ok) setInscrito(true)
        else setErro(r.erro)
      } catch (e) {
        setErro(e instanceof Error ? e.message : "Não consegui ligar os avisos.")
      }
    })
  }

  if (inscrito) {
    return (
      <p className="mt-4 flex items-center gap-2 rounded-xl border bg-muted/40 p-3 text-sm text-muted-foreground">
        <BellRing className="size-4 shrink-0" aria-hidden="true" />
        Você será avisado quando o pedido andar, mesmo com o app fechado.
      </p>
    )
  }

  return (
    <div className="mt-4 rounded-xl border border-dashed p-4">
      <p className="flex items-center gap-2 text-sm font-semibold">
        <Bell className="size-4 shrink-0" aria-hidden="true" />
        Quer que eu avise?
      </p>
      <p className="mt-1 text-sm text-muted-foreground">
        A gente te avisa quando a loja aceitar e quando o pedido sair para
        entrega — sem você precisar ficar abrindo esta tela.
      </p>
      {erro ? <p className="mt-2 text-sm text-destructive">{erro}</p> : null}
      <Button size="sm" className="mt-3" onClick={ligar} disabled={enviando}>
        Me avisar
      </Button>
    </div>
  )
}
