"use client"

import { useRouter } from "next/navigation"
import { useState, useTransition } from "react"
import { MapPin, Plus, Star, Trash2 } from "lucide-react"

import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { buscarCep, formatarCep } from "@/lib/cep"
import {
  removerEndereco,
  salvarEndereco,
  tornarEnderecoPadrao,
  type DadosDoEndereco,
} from "@/modules/cliente/enderecos"

export type EnderecoSalvo = {
  id: string
  rotulo: string
  resumo: string
  padrao: boolean
  semLocalizacao: boolean
}

const VAZIO: DadosDoEndereco = {
  rotulo: "Casa",
  cep: "",
  rua: "",
  numero: "",
  complemento: "",
  bairro: "",
  cidade: "",
  uf: "",
  referencia: "",
  padrao: false,
}

/**
 * Os enderecos de entrega: a lista e o formulario.
 *
 * O CEP preenche rua, bairro, cidade e estado; a pessoa so completa numero e
 * complemento. O padrao e o que aparece no topo do site e decide, na vitrine,
 * quais lojas entregam.
 */
export function EnderecosDoCliente({
  enderecos,
  voltarPara,
}: {
  enderecos: EnderecoSalvo[]
  /** Depois de salvar, volta para onde a pessoa estava (o carrinho, por exemplo). */
  voltarPara: string | null
}) {
  const router = useRouter()
  const [enviando, iniciar] = useTransition()
  const [erro, setErro] = useState<string | null>(null)
  const [abrindo, setAbrindo] = useState(enderecos.length === 0)
  const [dados, setDados] = useState<DadosDoEndereco>(VAZIO)
  const [buscando, setBuscando] = useState(false)

  function mudar<K extends keyof DadosDoEndereco>(campo: K, valor: DadosDoEndereco[K]) {
    setDados((d) => ({ ...d, [campo]: valor }))
  }

  async function aoMudarCep(valor: string) {
    const formatado = formatarCep(valor)
    mudar("cep", formatado)
    if (formatado.replace(/\D/g, "").length !== 8) return
    setBuscando(true)
    const achado = await buscarCep(formatado)
    setBuscando(false)
    if (achado) {
      setDados((d) => ({
        ...d,
        rua: achado.rua || d.rua,
        bairro: achado.bairro || d.bairro,
        cidade: achado.cidade,
        uf: achado.estado,
      }))
    }
  }

  function salvar(e: React.FormEvent) {
    e.preventDefault()
    setErro(null)
    iniciar(async () => {
      const r = await salvarEndereco(dados)
      if (!r.ok) return setErro(r.erro)
      setDados(VAZIO)
      setAbrindo(false)
      if (voltarPara) router.push(voltarPara)
      else router.refresh()
    })
  }

  function acao(fazer: () => Promise<{ ok: boolean; erro?: string }>) {
    setErro(null)
    iniciar(async () => {
      const r = await fazer()
      if (!r.ok) setErro(r.erro ?? "Não deu certo.")
      else router.refresh()
    })
  }

  return (
    <div className="space-y-6">
      {enderecos.length > 0 ? (
        <ul className="divide-y rounded-xl border bg-card">
          {enderecos.map((e) => (
            <li key={e.id} className="flex items-start gap-3 p-4">
              <MapPin className="mt-0.5 size-4 shrink-0 text-marca" aria-hidden="true" />
              <div className="min-w-0 flex-1">
                <p className="font-semibold">
                  {e.rotulo}
                  {e.padrao ? (
                    <span className="ml-2 rounded-full bg-marca-suave px-2 py-0.5 text-xs text-marca-forte">
                      principal
                    </span>
                  ) : null}
                </p>
                <p className="text-sm text-muted-foreground">{e.resumo}</p>
                {e.semLocalizacao ? (
                  <p className="mt-1 text-xs text-muted-foreground">
                    Sem localização pelo CEP: as lojas cobram a maior taxa de entrega.
                  </p>
                ) : null}
              </div>
              <div className="flex shrink-0 gap-1">
                {!e.padrao ? (
                  <Button
                    size="sm"
                    variant="ghost"
                    disabled={enviando}
                    onClick={() => acao(() => tornarEnderecoPadrao(e.id))}
                  >
                    <Star className="size-4" aria-hidden="true" />
                    Usar este
                  </Button>
                ) : null}
                <Button
                  size="sm"
                  variant="ghost"
                  aria-label={`Apagar o endereço ${e.rotulo}`}
                  disabled={enviando}
                  onClick={() => acao(() => removerEndereco(e.id))}
                >
                  <Trash2 className="size-4" aria-hidden="true" />
                </Button>
              </div>
            </li>
          ))}
        </ul>
      ) : null}

      {abrindo ? (
        <form onSubmit={salvar} className="grid grid-cols-6 gap-3 rounded-xl border bg-card p-4">
          <h2 className="col-span-6 font-bold">Novo endereço</h2>
          <label className="col-span-3 text-sm sm:col-span-2">
            <span className="text-xs text-muted-foreground">CEP</span>
            <Input
              value={dados.cep}
              onChange={(e) => void aoMudarCep(e.target.value)}
              inputMode="numeric"
              placeholder="74000-000"
              autoComplete="postal-code"
            />
          </label>
          <p className="col-span-3 self-end pb-2 text-xs text-muted-foreground sm:col-span-4">
            {buscando ? "Buscando o CEP…" : "O CEP preenche rua, bairro e cidade."}
          </p>
          <label className="col-span-6 text-sm sm:col-span-4">
            <span className="text-xs text-muted-foreground">Rua</span>
            <Input value={dados.rua} onChange={(e) => mudar("rua", e.target.value)} autoComplete="address-line1" />
          </label>
          <label className="col-span-2 text-sm">
            <span className="text-xs text-muted-foreground">Número</span>
            <Input value={dados.numero} onChange={(e) => mudar("numero", e.target.value)} />
          </label>
          <label className="col-span-4 text-sm sm:col-span-3">
            <span className="text-xs text-muted-foreground">Complemento</span>
            <Input
              value={dados.complemento}
              onChange={(e) => mudar("complemento", e.target.value)}
              placeholder="Apto, bloco, casa 2"
            />
          </label>
          <label className="col-span-6 text-sm sm:col-span-3">
            <span className="text-xs text-muted-foreground">Bairro</span>
            <Input value={dados.bairro} onChange={(e) => mudar("bairro", e.target.value)} />
          </label>
          <label className="col-span-4 text-sm">
            <span className="text-xs text-muted-foreground">Cidade</span>
            <Input value={dados.cidade} onChange={(e) => mudar("cidade", e.target.value)} />
          </label>
          <label className="col-span-2 text-sm">
            <span className="text-xs text-muted-foreground">UF</span>
            <Input value={dados.uf} onChange={(e) => mudar("uf", e.target.value)} maxLength={2} />
          </label>
          <label className="col-span-6 text-sm sm:col-span-3">
            <span className="text-xs text-muted-foreground">Ponto de referência</span>
            <Input value={dados.referencia} onChange={(e) => mudar("referencia", e.target.value)} />
          </label>
          <label className="col-span-6 text-sm sm:col-span-3">
            <span className="text-xs text-muted-foreground">Nome do endereço</span>
            <Input value={dados.rotulo} onChange={(e) => mudar("rotulo", e.target.value)} placeholder="Casa, Trabalho" />
          </label>
          {enderecos.length > 0 ? (
            <label className="col-span-6 flex items-center gap-2 text-sm">
              <input
                type="checkbox"
                checked={dados.padrao}
                onChange={(e) => mudar("padrao", e.target.checked)}
                className="size-4 accent-marca"
              />
              Usar como endereço principal
            </label>
          ) : null}
          <div className="col-span-6 flex gap-2">
            <Button type="submit" disabled={enviando}>
              Salvar endereço
            </Button>
            {enderecos.length > 0 ? (
              <Button type="button" variant="ghost" onClick={() => setAbrindo(false)}>
                Cancelar
              </Button>
            ) : null}
          </div>
        </form>
      ) : (
        <Button variant="outline" onClick={() => setAbrindo(true)}>
          <Plus className="size-4" aria-hidden="true" />
          Novo endereço
        </Button>
      )}

      {erro ? (
        <p role="alert" className="text-sm font-medium text-destructive">
          {erro}
        </p>
      ) : null}
    </div>
  )
}
