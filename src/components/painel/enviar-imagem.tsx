"use client"

import Image from "next/image"
import { useRef, useState, useTransition } from "react"
import { ImageUp, Loader2, Trash2 } from "lucide-react"

import { Button } from "@/components/ui/button"
import {
  ehImagemAceita,
  reduzirImagem,
  type MedidaDaImagem,
} from "@/lib/imagem"
import { criarClienteDoNavegador } from "@/lib/supabase/navegador"

/**
 * Escolher uma foto e guardá-la.
 *
 * O arquivo vai do navegador direto para o balde, com a sessão da pessoa — não
 * passa pelo servidor do Next. Passar dobraria a banda (sobe uma vez para o
 * Next, outra para o Supabase) e poria um limite de corpo de requisição no
 * caminho de uma foto de celular.
 *
 * Quem autoriza é a política do balde: só grava na pasta de um estabelecimento
 * quem gerencia aquele estabelecimento. A tela não é a tranca.
 */
export function EnviarImagem({
  restauranteId,
  pasta,
  medida,
  urlAtual,
  formato = "quadrado",
  aoTrocar,
}: {
  restauranteId: string
  /** Prefixo dentro da pasta da loja: "logo", "capa", "produtos/<id>". */
  pasta: string
  medida: MedidaDaImagem
  urlAtual: string | null
  formato?: "quadrado" | "largo"
  /** Recebe a URL nova, ou null quando a foto é removida. */
  aoTrocar: (url: string | null) => Promise<{ ok: boolean; erro?: string }>
}) {
  const campo = useRef<HTMLInputElement>(null)
  const [enviando, setEnviando] = useState(false)
  const [salvando, iniciar] = useTransition()
  const [erro, setErro] = useState<string | null>(null)
  const [url, setUrl] = useState(urlAtual)

  async function escolher(arquivo: File) {
    setErro(null)

    if (!ehImagemAceita(arquivo)) {
      setErro("Use uma foto em JPG, PNG ou WebP.")
      return
    }

    setEnviando(true)
    try {
      const menor = await reduzirImagem(arquivo, medida)

      // O momento no nome: sobrescrever o mesmo caminho deixa a foto velha no
      // cache do navegador e da CDN, e a pessoa trocaria a imagem sem ver
      // diferença nenhuma.
      const caminho = `${restauranteId}/${pasta}-${Date.now()}.jpg`

      const supabase = criarClienteDoNavegador()
      const { error } = await supabase.storage
        .from("imagens")
        .upload(caminho, menor, { contentType: "image/jpeg" })

      if (error) throw new Error(error.message)

      const { data } = supabase.storage.from("imagens").getPublicUrl(caminho)
      const publica = data.publicUrl

      const r = await aoTrocar(publica)
      if (!r.ok) throw new Error(r.erro ?? "Não consegui salvar.")

      setUrl(publica)
    } catch (e) {
      setErro(e instanceof Error ? e.message : "Não consegui enviar a foto.")
    } finally {
      setEnviando(false)
      // Sem isto, escolher o mesmo arquivo de novo não dispara nada: o input
      // só avisa quando o valor muda.
      if (campo.current) campo.current.value = ""
    }
  }

  const ocupado = enviando || salvando

  return (
    <div className="space-y-2">
      <div
        className={`relative overflow-hidden rounded-xl border bg-muted ${
          formato === "largo" ? "aspect-[3/1] w-full" : "size-28"
        }`}
      >
        {url ? (
          <Image src={url} alt="" fill sizes="400px" className="object-cover" unoptimized />
        ) : (
          <span className="flex size-full items-center justify-center text-muted-foreground">
            <ImageUp className="size-6" aria-hidden="true" />
          </span>
        )}

        {ocupado ? (
          <span className="absolute inset-0 grid place-items-center bg-background/70">
            <Loader2 className="size-5 animate-spin" aria-hidden="true" />
          </span>
        ) : null}
      </div>

      <div className="flex flex-wrap gap-2">
        <input
          ref={campo}
          type="file"
          accept="image/jpeg,image/png,image/webp,image/avif"
          className="hidden"
          onChange={(e) => {
            const f = e.target.files?.[0]
            if (f) escolher(f)
          }}
        />
        <Button
          type="button"
          size="sm"
          variant="outline"
          disabled={ocupado}
          onClick={() => campo.current?.click()}
        >
          {url ? "Trocar foto" : "Escolher foto"}
        </Button>

        {url ? (
          <Button
            type="button"
            size="sm"
            variant="ghost"
            disabled={ocupado}
            onClick={() =>
              iniciar(async () => {
                const r = await aoTrocar(null)
                if (r.ok) setUrl(null)
                else setErro(r.erro ?? "Não consegui remover.")
              })
            }
          >
            <Trash2 className="size-4 text-destructive" aria-hidden="true" />
          </Button>
        ) : null}
      </div>

      {erro ? <p className="text-sm text-destructive">{erro}</p> : null}
    </div>
  )
}
