"use client"

import { useState, useTransition } from "react"
import { Plus, Trash2 } from "lucide-react"

import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { removerBanner, salvarBanner } from "@/modules/admin/plataforma"

type Banner = {
  id: string
  title: string
  image_url: string
  target_url: string | null
  position: number
  starts_at: string
  ends_at: string | null
  is_active: boolean
}

export function FaixasDaVitrine({ banners }: { banners: Banner[] }) {
  const [enviando, iniciar] = useTransition()
  const [erro, setErro] = useState<string | null>(null)
  const [criando, setCriando] = useState(false)

  const [titulo, setTitulo] = useState("")
  const [imagem, setImagem] = useState("")
  const [destino, setDestino] = useState("")
  const [ate, setAte] = useState("")

  return (
    <div className="space-y-5">
      <Button onClick={() => setCriando((v) => !v)}>
        <Plus className="size-4" aria-hidden="true" />
        Nova faixa
      </Button>

      {criando ? (
        <div className="grid gap-4 rounded-xl border bg-card p-5 sm:grid-cols-2">
          <div>
            <Label htmlFor="titulo">Título</Label>
            <Input id="titulo" value={titulo} onChange={(e) => setTitulo(e.target.value)} />
          </div>
          <div>
            <Label htmlFor="imagem">Endereço da imagem</Label>
            <Input
              id="imagem"
              value={imagem}
              onChange={(e) => setImagem(e.target.value)}
              placeholder="https://…"
            />
          </div>
          <div>
            <Label htmlFor="destino">Leva para</Label>
            <Input
              id="destino"
              value={destino}
              onChange={(e) => setDestino(e.target.value)}
              placeholder="/restaurante/burger-house"
            />
          </div>
          <div>
            <Label htmlFor="ate">Até</Label>
            <Input id="ate" type="date" value={ate} onChange={(e) => setAte(e.target.value)} />
          </div>

          <div className="sm:col-span-2 flex gap-2">
            <Button
              disabled={enviando}
              onClick={() =>
                iniciar(async () => {
                  const r = await salvarBanner({
                    titulo,
                    imagemUrl: imagem,
                    destino,
                    posicao: (banners.at(-1)?.position ?? 0) + 1,
                    terminaEm: ate,
                  })
                  if (r.ok) {
                    setCriando(false)
                    setTitulo("")
                    setImagem("")
                    setDestino("")
                    setAte("")
                  } else setErro(r.erro)
                })
              }
            >
              Criar faixa
            </Button>
            <Button variant="ghost" onClick={() => setCriando(false)}>
              Cancelar
            </Button>
          </div>
        </div>
      ) : null}

      {erro ? (
        <p role="alert" className="text-sm font-medium text-destructive">
          {erro}
        </p>
      ) : null}

      {banners.length === 0 ? (
        <div className="rounded-xl border border-dashed p-10 text-center">
          <p className="font-semibold">Nenhuma faixa</p>
          <p className="mt-1 text-sm text-muted-foreground">
            A vitrine funciona sem elas. Servem para destacar campanha ou loja nova.
          </p>
        </div>
      ) : (
        <ul className="grid gap-3 sm:grid-cols-2">
          {banners.map((b) => {
            const vencida = b.ends_at !== null && new Date(b.ends_at) < new Date()
            return (
              <li key={b.id} className="overflow-hidden rounded-xl border bg-card">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src={b.image_url} alt="" className="h-28 w-full object-cover" />
                <div className="flex items-center gap-2 p-3">
                  <div className="min-w-0 flex-1">
                    <p className="truncate font-semibold">{b.title}</p>
                    <p className="truncate text-sm text-muted-foreground">
                      {b.target_url ?? "sem destino"}
                    </p>
                  </div>
                  {vencida ? <Badge variant="destructive">Vencida</Badge> : null}
                  {b.is_active ? null : <Badge variant="secondary">Fora</Badge>}
                  <Button
                    size="sm"
                    variant="ghost"
                    disabled={enviando}
                    aria-label={`Tirar ${b.title}`}
                    onClick={() =>
                      iniciar(async () => {
                        const r = await removerBanner(b.id)
                        if (!r.ok) setErro(r.erro)
                      })
                    }
                  >
                    <Trash2 className="size-4" aria-hidden="true" />
                  </Button>
                </div>
              </li>
            )
          })}
        </ul>
      )}
    </div>
  )
}
