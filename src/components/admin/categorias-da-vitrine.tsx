"use client"

import { useState, useTransition } from "react"
import { Plus } from "lucide-react"

import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import {
  mudarSituacaoDaCategoria,
  salvarCategoriaDaPlataforma,
} from "@/modules/admin/plataforma"

type Categoria = {
  id: string
  nome: string
  slug: string
  posicao: number
  ativa: boolean
  estabelecimentos: number
}

export function CategoriasDaVitrine({ categorias }: { categorias: Categoria[] }) {
  const [enviando, iniciar] = useTransition()
  const [erro, setErro] = useState<string | null>(null)
  const [nova, setNova] = useState("")

  return (
    <div className="space-y-4">
      <div className="flex gap-2">
        <Input
          value={nova}
          onChange={(e) => setNova(e.target.value)}
          placeholder="Nova categoria — Japonesa, Saudável, Marmita…"
          className="max-w-sm"
        />
        <Button
          disabled={enviando || !nova.trim()}
          onClick={() =>
            iniciar(async () => {
              const r = await salvarCategoriaDaPlataforma({
                nome: nova,
                // O endereço sai do nome; ninguém precisa pensar nele.
                slug: "",
                posicao: (categorias.at(-1)?.posicao ?? 0) + 1,
              })
              if (r.ok) setNova("")
              else setErro(r.erro)
            })
          }
        >
          <Plus className="size-4" aria-hidden="true" />
          Criar
        </Button>
      </div>

      {erro ? (
        <p role="alert" className="text-sm font-medium text-destructive">
          {erro}
        </p>
      ) : null}

      <ul className="divide-y rounded-xl border bg-card">
        {categorias.map((c) => (
          <li key={c.id} className="flex items-center gap-3 p-4">
            <div className="flex-1">
              <span className="font-semibold">{c.nome}</span>
              <span className="ml-2 text-sm text-muted-foreground">
                /{c.slug} · {c.estabelecimentos} estabelecimento(s)
              </span>
            </div>

            <label className="flex cursor-pointer items-center gap-2 text-sm">
              <input
                type="checkbox"
                checked={c.ativa}
                disabled={enviando}
                className="size-4 accent-marca"
                onChange={(e) =>
                  iniciar(async () => {
                    const r = await mudarSituacaoDaCategoria(c.id, e.target.checked)
                    if (!r.ok) setErro(r.erro)
                  })
                }
              />
              {c.ativa ? "Na vitrine" : "Escondida"}
            </label>
          </li>
        ))}
      </ul>
    </div>
  )
}
