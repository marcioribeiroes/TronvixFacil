"use client"

import { useRouter } from "next/navigation"
import { useState, useTransition } from "react"
import { Trash2 } from "lucide-react"

import { Button } from "@/components/ui/button"
import {
  ListaDoCardapio,
  type Escolha,
  type Grupo,
  type Secao,
} from "@/components/pedido/cardapio-para-escolher"
import { formatarReais } from "@/lib/dinheiro"
import { pedirMaisNaMesa } from "@/modules/cliente/pedidos"

/**
 * Pedir mais, sentado na mesa.
 *
 * As escolhas juntam aqui e vão para a cozinha de uma vez, no mesmo pedido —
 * a mesma conta, que o garçom fecha no fim. Nada vai antes de "Enviar": o
 * cliente que escolheu duas sobremesas e desistiu de uma não incomoda a
 * cozinha duas vezes.
 */
export function PedirMais({
  pedidoId,
  aberto,
  secoes,
  grupos,
}: {
  pedidoId: string
  aberto: boolean
  secoes: Secao[]
  grupos: Grupo[]
}) {
  const router = useRouter()
  const [enviando, iniciar] = useTransition()
  const [erro, setErro] = useState<string | null>(null)
  const [escolhas, setEscolhas] = useState<(Escolha & { chave: number })[]>([])

  const total = escolhas.reduce((s, e) => s + e.totalCentavos, 0)

  function enviar() {
    setErro(null)
    iniciar(async () => {
      const r = await pedirMaisNaMesa(
        pedidoId,
        escolhas.map((e) => ({
          produto_id: e.produto.id,
          quantidade: e.quantidade,
          observacao: e.observacao,
          adicionais: e.adicionais,
        })),
      )
      if (r.ok) router.push(`/pedidos/${pedidoId}`)
      else setErro(r.erro)
    })
  }

  return (
    <div className="space-y-6 pb-28">
      <ListaDoCardapio
        secoes={secoes}
        grupos={grupos}
        rotuloDoBotao="Pôr no pedido"
        bloqueio={aberto ? undefined : "Cozinha fechada"}
        aoEscolher={async (escolha) => {
          setEscolhas((atuais) => [...atuais, { ...escolha, chave: Date.now() }])
          return { ok: true }
        }}
      />

      {escolhas.length > 0 ? (
        <div className="fixed inset-x-0 bottom-0 z-40 border-t bg-background p-4">
          <div className="mx-auto max-w-2xl space-y-3">
            <ul className="max-h-40 space-y-1 overflow-y-auto text-sm">
              {escolhas.map((e) => (
                <li key={e.chave} className="flex items-center gap-2">
                  <span className="font-bold text-marca">{e.quantidade}×</span>
                  <span className="flex-1 truncate">{e.produto.name}</span>
                  <span className="text-muted-foreground">{formatarReais(e.totalCentavos)}</span>
                  <Button
                    size="sm"
                    variant="ghost"
                    aria-label={`Tirar ${e.produto.name}`}
                    onClick={() => setEscolhas((atuais) => atuais.filter((x) => x.chave !== e.chave))}
                  >
                    <Trash2 className="size-4" aria-hidden="true" />
                  </Button>
                </li>
              ))}
            </ul>
            {erro ? (
              <p role="alert" className="text-sm font-medium text-destructive">
                {erro}
              </p>
            ) : null}
            <Button className="w-full" onClick={enviar} disabled={enviando}>
              Enviar para a cozinha · {formatarReais(total)}
            </Button>
          </div>
        </div>
      ) : null}
    </div>
  )
}
