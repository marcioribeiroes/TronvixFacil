"use client"

import { useRouter } from "next/navigation"
import { useState, useTransition } from "react"
import { Loader2, Store } from "lucide-react"

import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { cadastrarEntregador } from "@/modules/entregador/cadastro"

/**
 * O cadastro de entregador, no navegador.
 *
 * Mesmas tres perguntas do aplicativo (celular/lib/entregador/cadastro.dart):
 * para quem, com o que, e a placa quando ha placa. Escolhas em cartoes
 * grandes, e nao em radio de 16 pixels: quem preenche isto esta no celular,
 * muitas vezes de pe na porta da loja.
 */

export type EstabelecimentoParaCadastro = {
  id: string
  nome: string
  lugar: string
  logoUrl: string | null
}

const VEICULOS = [
  ["motorcycle", "Moto"],
  ["bicycle", "Bicicleta"],
  ["car", "Carro"],
  ["foot", "A pé"],
] as const

const escolha = (marcado: boolean) =>
  `rounded-xl border-2 bg-card text-left transition-colors ${
    marcado ? "border-marca bg-marca-suave" : "border-transparent ring-1 ring-border hover:bg-muted"
  }`

export function FormularioDeEntregador({
  estabelecimentos,
}: {
  estabelecimentos: EstabelecimentoParaCadastro[]
}) {
  const router = useRouter()
  const [enviando, iniciar] = useTransition()
  const [erro, setErro] = useState<string | null>(null)

  const [restauranteId, setRestauranteId] = useState("")
  const [veiculo, setVeiculo] = useState<string>("motorcycle")
  const [placa, setPlaca] = useState("")
  const temPlaca = veiculo === "motorcycle" || veiculo === "car"

  function enviar() {
    setErro(null)
    iniciar(async () => {
      const resultado = await cadastrarEntregador({ restauranteId, veiculo, placa })
      if (resultado.ok) {
        router.push("/entregas")
        router.refresh()
      } else {
        setErro(resultado.erro)
      }
    })
  }

  return (
    <form
      className="space-y-6"
      noValidate
      onSubmit={(e) => {
        e.preventDefault()
        enviar()
      }}
    >
      <fieldset className="space-y-2">
        <legend className="mb-2 font-bold">Para onde você quer entregar</legend>
        {estabelecimentos.length === 0 ? (
          <p className="text-sm text-muted-foreground">Nenhum estabelecimento aprovado ainda.</p>
        ) : (
          estabelecimentos.map((r) => (
            <button
              key={r.id}
              type="button"
              aria-pressed={restauranteId === r.id}
              onClick={() => setRestauranteId(r.id)}
              className={`flex w-full items-center gap-3 p-3 ${escolha(restauranteId === r.id)}`}
            >
              {r.logoUrl ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img src={r.logoUrl} alt="" className="size-10 rounded-lg object-cover" />
              ) : (
                <span className="grid size-10 place-items-center rounded-lg bg-muted">
                  <Store className="size-5 text-muted-foreground" aria-hidden="true" />
                </span>
              )}
              <span className="min-w-0">
                <span className="block font-semibold">{r.nome}</span>
                {r.lugar ? (
                  <span className="block text-xs text-muted-foreground">{r.lugar}</span>
                ) : null}
              </span>
            </button>
          ))
        )}
      </fieldset>

      <fieldset>
        <legend className="mb-2 font-bold">Como você entrega</legend>
        <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
          {VEICULOS.map(([valor, rotulo]) => (
            <button
              key={valor}
              type="button"
              aria-pressed={veiculo === valor}
              onClick={() => setVeiculo(valor)}
              className={`px-3 py-3 text-center text-sm font-semibold ${escolha(veiculo === valor)}`}
            >
              {rotulo}
            </button>
          ))}
        </div>
      </fieldset>

      {temPlaca ? (
        <div className="space-y-2">
          <Label htmlFor="placa">Placa</Label>
          <Input
            id="placa"
            value={placa}
            onChange={(e) => setPlaca(e.target.value.toUpperCase())}
            placeholder="ABC1D23"
            autoCapitalize="characters"
            maxLength={8}
          />
        </div>
      ) : null}

      {erro ? (
        <p role="alert" className="text-sm font-medium text-destructive">
          {erro}
        </p>
      ) : null}

      <Button
        type="submit"
        size="lg"
        className="w-full"
        disabled={enviando || estabelecimentos.length === 0}
      >
        {enviando ? <Loader2 className="size-4 animate-spin" aria-hidden="true" /> : null}
        {enviando ? "Enviando…" : "Enviar cadastro"}
      </Button>
    </form>
  )
}
