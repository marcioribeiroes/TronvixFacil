"use client"

import { useState, useTransition } from "react"

import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { salvarLimitesDosEntregadores } from "@/modules/admin/plataforma"

/**
 * Quanto cada veiculo roda, e quanto a loja espera antes de chamar autonomo.
 *
 * Numeros para ajustar com o uso: os primeiros meses em cada cidade dizem o
 * raio certo melhor do que qualquer palpite. Vazio e "sem limite".
 */

export type LimiteDoVeiculo = { veiculo: string; viagemKm: string; buscaKm: string }

const ROTULO: Record<string, string> = {
  foot: "A pé",
  bicycle: "Bicicleta",
  motorcycle: "Moto",
  car: "Carro",
}

const ORDEM = ["foot", "bicycle", "motorcycle", "car"]

export function LimitesDosEntregadores({
  espera,
  limites,
}: {
  espera: number
  limites: LimiteDoVeiculo[]
}) {
  const [enviando, iniciar] = useTransition()
  const [aviso, setAviso] = useState<{ tipo: "erro" | "ok"; texto: string } | null>(null)
  const [minutos, setMinutos] = useState(String(espera))
  const [linhas, setLinhas] = useState(
    [...limites].sort((a, b) => ORDEM.indexOf(a.veiculo) - ORDEM.indexOf(b.veiculo)),
  )

  function mudar(veiculo: string, campo: "viagemKm" | "buscaKm", valor: string) {
    setLinhas((atuais) => atuais.map((l) => (l.veiculo === veiculo ? { ...l, [campo]: valor } : l)))
  }

  function salvar() {
    setAviso(null)
    iniciar(async () => {
      const r = await salvarLimitesDosEntregadores({ esperaEmMinutos: minutos, limites: linhas })
      setAviso(r.ok ? { tipo: "ok", texto: "Limites salvos." } : { tipo: "erro", texto: r.erro })
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
        <h2 className="font-bold">Entregadores autônomos</h2>
        <p className="mt-1 text-sm text-muted-foreground">
          A corrida vai primeiro para os entregadores do estabelecimento. Se ninguém aceitar no
          tempo de espera, abre para os autônomos dentro dos limites do veículo de cada um.
        </p>
      </div>

      <div className="max-w-56 space-y-2">
        <Label htmlFor="espera">Espera antes de abrir (minutos)</Label>
        <Input
          id="espera"
          inputMode="numeric"
          value={minutos}
          onChange={(e) => setMinutos(e.target.value)}
        />
      </div>

      <table className="w-full text-sm">
        <thead>
          <tr className="text-left text-xs text-muted-foreground">
            <th className="pb-2 font-medium">Veículo</th>
            <th className="pb-2 font-medium">Loja → cliente (km)</th>
            <th className="pb-2 font-medium">Entregador → loja (km)</th>
          </tr>
        </thead>
        <tbody>
          {linhas.map((l) => (
            <tr key={l.veiculo}>
              <td className="py-1 pr-3 font-medium">{ROTULO[l.veiculo] ?? l.veiculo}</td>
              <td className="py-1 pr-3">
                <Input
                  aria-label={`Limite da viagem, ${ROTULO[l.veiculo]}`}
                  inputMode="decimal"
                  value={l.viagemKm}
                  onChange={(e) => mudar(l.veiculo, "viagemKm", e.target.value)}
                  placeholder="sem limite"
                />
              </td>
              <td className="py-1">
                <Input
                  aria-label={`Limite até a loja, ${ROTULO[l.veiculo]}`}
                  inputMode="decimal"
                  value={l.buscaKm}
                  onChange={(e) => mudar(l.veiculo, "buscaKm", e.target.value)}
                  placeholder="sem limite"
                />
              </td>
            </tr>
          ))}
        </tbody>
      </table>

      <div className="flex flex-wrap items-center gap-3">
        <Button type="submit" disabled={enviando}>
          {enviando ? "Salvando…" : "Salvar limites"}
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
