"use client"

import { useState, useTransition } from "react"
import { Check, Copy } from "lucide-react"

import { Button } from "@/components/ui/button"
import { formatarReais } from "@/lib/dinheiro"
import { gerarPagamentoDaAssinatura } from "@/modules/entregador/corridas"

/**
 * A assinatura do autonomo: se esta em dia, ate quando, e o Pix para pagar.
 *
 * Espelho de celular/lib/entregador/assinatura.dart. O copia-e-cola vem pronto
 * do banco (`minha_assinatura`), o mesmo que o aplicativo mostra. Quem confirma
 * o pagamento e a plataforma, ao ver o Pix cair - a tela diz isso, para o
 * motoboy nao achar que pagou e nada aconteceu.
 */

export type Assinatura = {
  cobrando: boolean
  inicio: string | null
  vence: string | null
  emDia: boolean
  precoCentavos: number
  pendente: { valorCentavos: number; referencia: string; copiaECola: string } | null
}

/** "2026-11-28" para "28/11/2026", sem passar pelo fuso. */
function emDia(iso: string) {
  const [ano, mes, d] = iso.split("-")
  return `${d}/${mes}/${ano}`
}

export function AssinaturaDoEntregador({ assinatura: a }: { assinatura: Assinatura }) {
  const [enviando, iniciar] = useTransition()
  const [erro, setErro] = useState<string | null>(null)
  const [copiado, setCopiado] = useState(false)

  const situacao = !a.cobrando
    ? a.inicio
      ? `Grátis até ${emDia(a.inicio)}. Depois, ${formatarReais(a.precoCentavos)} por mês.`
      : "Grátis no lançamento. Avisaremos antes de começar a cobrar."
    : a.emDia
      ? `Em dia até ${a.vence ? emDia(a.vence) : "—"}.`
      : `Vencida desde ${a.vence ? emDia(a.vence) : "—"}. Pague para voltar a receber corridas.`

  return (
    <section className="space-y-3 rounded-xl border bg-card p-4">
      <div>
        <h2 className="font-bold">Assinatura</h2>
        <p className={`mt-1 text-sm ${a.cobrando && !a.emDia ? "font-semibold text-destructive" : "text-muted-foreground"}`}>
          {situacao}
        </p>
      </div>

      {a.cobrando && a.pendente ? (
        <div className="space-y-2">
          <p className="text-sm">
            Pague <strong>{formatarReais(a.pendente.valorCentavos)}</strong> com o Pix copia e cola.
            A confirmação é feita pela equipe quando o dinheiro cair — pode levar algumas horas.
          </p>
          <p className="break-all rounded-lg bg-muted p-3 font-mono text-xs">{a.pendente.copiaECola}</p>
          <Button
            variant="outline"
            onClick={async () => {
              await navigator.clipboard.writeText(a.pendente!.copiaECola)
              setCopiado(true)
              window.setTimeout(() => setCopiado(false), 2500)
            }}
          >
            {copiado ? <Check className="size-4" aria-hidden="true" /> : <Copy className="size-4" aria-hidden="true" />}
            {copiado ? "Copiado" : "Copiar código Pix"}
          </Button>
          <p className="text-xs text-muted-foreground">Referência: {a.pendente.referencia}</p>
        </div>
      ) : a.cobrando ? (
        <Button
          disabled={enviando}
          onClick={() => {
            setErro(null)
            iniciar(async () => {
              const r = await gerarPagamentoDaAssinatura()
              if (!r.ok) setErro(r.erro)
            })
          }}
        >
          {a.emDia ? "Pagar o próximo mês" : `Pagar ${formatarReais(a.precoCentavos)} por Pix`}
        </Button>
      ) : null}

      {erro ? <p className="text-sm font-medium text-destructive">{erro}</p> : null}
    </section>
  )
}
