"use client"

import { useState, useTransition } from "react"
import { MapPinned, Plus, Trash2 } from "lucide-react"

import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { formatarValor } from "@/lib/dinheiro"
import { salvarFaixasDeEntrega } from "@/modules/painel/configuracoes"

type Faixa = { chave: number; ateKm: string; taxa: string }

/**
 * A taxa de entrega por distancia.
 *
 * Cada linha e "ate X km, R$ Y". O endereco cai na primeira faixa que o
 * alcanca; acima da ultima, a loja nao entrega — a vitrine avisa o cliente e
 * o fechamento recusa. Sem nenhuma faixa, vale a taxa unica e o raio de cima.
 */
export function FaixasDeEntrega({
  faixas: iniciais,
  lojaTemLocalizacao,
}: {
  faixas: { up_to_km: number; fee_cents: number }[]
  lojaTemLocalizacao: boolean
}) {
  const [enviando, iniciar] = useTransition()
  const [aviso, setAviso] = useState<{ ok: boolean; texto: string } | null>(null)
  const [faixas, setFaixas] = useState<Faixa[]>(() =>
    iniciais.map((f, i) => ({
      chave: i,
      ateKm: String(f.up_to_km).replace(".", ","),
      taxa: formatarValor(f.fee_cents),
    })),
  )

  function mudar(chave: number, campo: "ateKm" | "taxa", valor: string) {
    setFaixas((atuais) => atuais.map((f) => (f.chave === chave ? { ...f, [campo]: valor } : f)))
  }

  function acrescentar() {
    setFaixas((atuais) => [...atuais, { chave: Date.now(), ateKm: "", taxa: "" }])
  }

  function salvar() {
    setAviso(null)
    iniciar(async () => {
      const r = await salvarFaixasDeEntrega(faixas.map(({ ateKm, taxa }) => ({ ateKm, taxa })))
      setAviso(
        r.ok
          ? {
              ok: true,
              texto:
                faixas.length === 0
                  ? "Sem faixas: vale a taxa única e o raio acima."
                  : "Faixas salvas. Já valem para o próximo pedido.",
            }
          : { ok: false, texto: r.erro },
      )
    })
  }

  // Ordenadas so para mostrar; o banco acha a faixa certa sozinho.
  const ordenadas = [...faixas].sort(
    (a, b) => (Number(a.ateKm.replace(",", ".")) || 999) - (Number(b.ateKm.replace(",", ".")) || 999),
  )

  return (
    <section className="space-y-4 rounded-xl border bg-card p-5">
      <div className="flex items-start gap-2">
        <MapPinned className="mt-0.5 size-4 text-muted-foreground" aria-hidden="true" />
        <div>
          <h2 className="font-bold">Taxa por distância</h2>
          <p className="text-sm text-muted-foreground">
            A distância é em linha reta, da loja ao endereço — deixe uma folga. Acima da última
            faixa, a loja não entrega. O frete grátis acima de um valor continua valendo.
          </p>
        </div>
      </div>

      {!lojaTemLocalizacao ? (
        <p className="rounded-lg bg-marca-suave px-3 py-2 text-sm text-marca-forte">
          A loja ainda não tem localização, então não dá para medir distância: todo pedido paga a
          maior faixa. Peça ao suporte para localizar a loja pelo endereço.
        </p>
      ) : null}

      {ordenadas.length === 0 ? (
        <p className="text-sm text-muted-foreground">
          Nenhuma faixa: a loja cobra a taxa única de &quot;Entrega e mínimo&quot; e entrega até o
          raio da seção &quot;A loja&quot;.
        </p>
      ) : (
        <ul className="space-y-2">
          {ordenadas.map((f) => (
            <li key={f.chave} className="flex flex-wrap items-center gap-2 text-sm">
              <span className="text-muted-foreground">até</span>
              <Input
                aria-label="Distância máxima da faixa, em km"
                value={f.ateKm}
                onChange={(e) => mudar(f.chave, "ateKm", e.target.value)}
                inputMode="decimal"
                placeholder="2"
                className="w-20"
              />
              <span className="text-muted-foreground">km —</span>
              <Input
                aria-label="Taxa da faixa"
                value={f.taxa}
                onChange={(e) => mudar(f.chave, "taxa", e.target.value)}
                inputMode="decimal"
                placeholder="R$ 0,00"
                className="w-28"
              />
              <Button
                size="sm"
                variant="ghost"
                aria-label="Tirar esta faixa"
                onClick={() => setFaixas((atuais) => atuais.filter((x) => x.chave !== f.chave))}
              >
                <Trash2 className="size-4" aria-hidden="true" />
              </Button>
            </li>
          ))}
        </ul>
      )}

      <div className="flex flex-wrap gap-2">
        <Button variant="outline" size="sm" onClick={acrescentar} disabled={faixas.length >= 10}>
          <Plus className="size-4" aria-hidden="true" />
          Faixa
        </Button>
        <Button size="sm" onClick={salvar} disabled={enviando}>
          Salvar faixas
        </Button>
      </div>

      {aviso ? (
        <p
          role={aviso.ok ? "status" : "alert"}
          className={`text-sm font-medium ${aviso.ok ? "text-status-pronto" : "text-destructive"}`}
        >
          {aviso.texto}
        </p>
      ) : null}
    </section>
  )
}
