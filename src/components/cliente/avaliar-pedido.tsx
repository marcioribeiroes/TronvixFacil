"use client"

import { useState, useTransition } from "react"
import { Star } from "lucide-react"

import { Button } from "@/components/ui/button"
import { avaliarPedido } from "@/modules/cliente/pedidos"

/**
 * A nota do pedido que chegou: o estabelecimento e, quando houve entrega, o
 * entregador. Avaliar de novo corrige - o cliente que deu 2 no calor da
 * fome e pensou melhor depois nao fica preso a primeira nota.
 */

function Estrelas({
  rotulo,
  nota,
  aoEscolher,
}: {
  rotulo: string
  nota: number
  aoEscolher: (n: number) => void
}) {
  return (
    <fieldset>
      <legend className="text-sm font-semibold">{rotulo}</legend>
      <div className="mt-1 flex gap-1">
        {[1, 2, 3, 4, 5].map((n) => (
          <button
            key={n}
            type="button"
            aria-label={`${n} ${n === 1 ? "estrela" : "estrelas"}`}
            aria-pressed={nota === n}
            onClick={() => aoEscolher(n)}
            className="rounded-md p-1 transition-colors hover:bg-muted"
          >
            <Star
              className={`size-7 ${n <= nota ? "fill-amber-400 text-amber-400" : "text-muted-foreground"}`}
              aria-hidden="true"
            />
          </button>
        ))}
      </div>
    </fieldset>
  )
}

export function AvaliarPedido({
  id,
  comEntregador,
  atual,
}: {
  id: string
  comEntregador: boolean
  atual: { loja: number; entregador: number | null; comentario: string | null } | null
}) {
  const [enviando, iniciar] = useTransition()
  const [aviso, setAviso] = useState<{ tipo: "erro" | "ok"; texto: string } | null>(null)
  const [loja, setLoja] = useState(atual?.loja ?? 0)
  const [entregador, setEntregador] = useState(atual?.entregador ?? 0)
  const [comentario, setComentario] = useState(atual?.comentario ?? "")

  function enviar() {
    setAviso(null)
    iniciar(async () => {
      const r = await avaliarPedido({
        id,
        notaDaLoja: loja,
        notaDoEntregador: comEntregador && entregador > 0 ? entregador : null,
        comentario,
      })
      setAviso(
        r.ok ? { tipo: "ok", texto: "Obrigado pela avaliação!" } : { tipo: "erro", texto: r.erro },
      )
    })
  }

  return (
    <section className="space-y-4 rounded-xl border bg-card p-4">
      <h2 className="font-bold">{atual ? "Sua avaliação" : "Como foi o pedido?"}</h2>
      <Estrelas rotulo="Estabelecimento" nota={loja} aoEscolher={setLoja} />
      {comEntregador ? (
        <Estrelas rotulo="Entregador" nota={entregador} aoEscolher={setEntregador} />
      ) : null}
      <textarea
        aria-label="Comentário"
        value={comentario}
        onChange={(e) => setComentario(e.target.value)}
        placeholder="Quer contar mais? (opcional)"
        maxLength={1000}
        rows={3}
        className="w-full rounded-lg border border-input bg-transparent px-3 py-2 text-sm"
      />
      <div className="flex flex-wrap items-center gap-3">
        <Button onClick={enviar} disabled={enviando || loja === 0}>
          {enviando ? "Enviando…" : atual ? "Atualizar avaliação" : "Enviar avaliação"}
        </Button>
        {aviso ? (
          <p
            role={aviso.tipo === "erro" ? "alert" : "status"}
            className={`text-sm font-medium ${aviso.tipo === "erro" ? "text-destructive" : "text-marca"}`}
          >
            {aviso.texto}
          </p>
        ) : null}
      </div>
    </section>
  )
}
