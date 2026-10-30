"use client"

import { useState, useTransition } from "react"

import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { formatarReais, paraCentavos } from "@/lib/dinheiro"
import { salvarValorDoEntregador } from "@/modules/painel/configuracoes"

/**
 * Quanto a loja paga ao entregador por corrida.
 *
 * O entregador ve este valor antes de aceitar, e escolhe: a loja que paga
 * melhor tem as corridas aceitas primeiro. O piso da plataforma vale sempre -
 * e e ele que impede o frete gratis de virar corrida de graca.
 */
export function ValorDoEntregador({
  fixoCentavos,
  porKmCentavos,
  freteCentavos,
  pisoCentavos,
}: {
  fixoCentavos: number | null
  porKmCentavos: number
  freteCentavos: number
  pisoCentavos: number
}) {
  const [enviando, iniciar] = useTransition()
  const [aviso, setAviso] = useState<{ tipo: "erro" | "ok"; texto: string } | null>(null)
  const [fixo, setFixo] = useState(
    fixoCentavos === null ? "" : (fixoCentavos / 100).toFixed(2).replace(".", ","),
  )
  const [porKm, setPorKm] = useState((porKmCentavos / 100).toFixed(2).replace(".", ","))

  // O exemplo do formulario: uma corrida de 3 km, com a conta do banco.
  const exemplo = (km: number) => {
    const base = fixo.trim() === "" ? freteCentavos : (paraCentavos(fixo) ?? 0)
    const adicional = Math.round((paraCentavos(porKm) ?? 0) * km)
    return Math.max(pisoCentavos, base + adicional)
  }

  function salvar() {
    setAviso(null)
    iniciar(async () => {
      const r = await salvarValorDoEntregador({ fixo, porKm })
      setAviso(r.ok ? { tipo: "ok", texto: "Valor salvo. Vale para as próximas corridas." } : { tipo: "erro", texto: r.erro })
    })
  }

  return (
    <form
      className="space-y-4 rounded-xl border bg-card p-5"
      noValidate
      onSubmit={(e) => {
        e.preventDefault()
        salvar()
      }}
    >
      <div>
        <h2 className="font-bold">Quanto você paga por corrida</h2>
        <p className="mt-1 text-sm text-muted-foreground">
          O entregador vê o valor antes de aceitar. Quem paga melhor tem as corridas aceitas
          primeiro. Nenhuma corrida paga menos que {formatarReais(pisoCentavos)}, o mínimo da
          plataforma — nem com frete grátis.
        </p>
      </div>

      <div className="grid gap-4 sm:grid-cols-2">
        <div className="space-y-2">
          <Label htmlFor="valor-fixo">Valor por corrida (R$)</Label>
          <Input
            id="valor-fixo"
            inputMode="decimal"
            value={fixo}
            onChange={(e) => setFixo(e.target.value)}
            placeholder={`o frete do cliente (${formatarReais(freteCentavos)})`}
          />
          <p className="text-xs text-muted-foreground">
            Em branco, o entregador recebe o frete que o cliente pagou.
          </p>
        </div>
        <div className="space-y-2">
          <Label htmlFor="valor-km">Adicional por km (R$)</Label>
          <Input
            id="valor-km"
            inputMode="decimal"
            value={porKm}
            onChange={(e) => setPorKm(e.target.value)}
            placeholder="0,00"
          />
          <p className="text-xs text-muted-foreground">Opcional. Conta a distância da loja ao cliente.</p>
        </div>
      </div>

      <p className="rounded-lg bg-muted px-3 py-2 text-sm">
        Exemplos: corrida de 1 km paga <strong>{formatarReais(exemplo(1))}</strong>, de 3 km{" "}
        <strong>{formatarReais(exemplo(3))}</strong>, de 6 km <strong>{formatarReais(exemplo(6))}</strong>.
      </p>

      <div className="flex flex-wrap items-center gap-3">
        <Button type="submit" disabled={enviando}>
          {enviando ? "Salvando…" : "Salvar valor"}
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
    </form>
  )
}
