"use client"

import { useState, useTransition } from "react"
import { Check, Pencil, Plus, Power, Printer, Trash2, X } from "lucide-react"

import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { criarMesas, mudarUsoDaMesa, removerMesa, renomearMesa } from "@/modules/painel/mesas"

/**
 * As mesas, e as etiquetas para imprimir.
 *
 * A impressao e o produto real desta tela: de nada serve cadastrar vinte mesas
 * se ninguem consegue por o QR na mesa. Por isso a folha de etiquetas abre em
 * uma pagina propria, pronta para o papel, e nao num modal que a impressora
 * corta pela metade.
 */

export type MesaNaTela = {
  id: string
  rotulo: string
  codigo: string
  emUso: boolean
  pedidosAbertos: number
  contaAbertaCentavos: number
}

export function MesasDoSalao({
  mesas,
  enderecoDoSite,
}: {
  mesas: MesaNaTela[]
  enderecoDoSite: string
}) {
  const [enviando, iniciar] = useTransition()
  const [erro, setErro] = useState<string | null>(null)
  const [quantidade, setQuantidade] = useState("10")
  const [prefixo, setPrefixo] = useState("Mesa")
  const [editando, setEditando] = useState<string | null>(null)
  const [nome, setNome] = useState("")

  function rodar(acao: () => Promise<{ ok: true } | { ok: false; erro: string }>) {
    setErro(null)
    iniciar(async () => {
      const r = await acao()
      if (r.ok) setEditando(null)
      else setErro(r.erro)
    })
  }

  return (
    <div className="space-y-6">
      <div className="rounded-xl border bg-card p-4">
        <p className="text-sm font-bold">Criar mesas</p>
        <p className="mt-0.5 text-xs text-muted-foreground">
          Sai numerado, continuando de onde parou. Renomeie depois as que têm nome.
        </p>
        <div className="mt-3 flex flex-wrap items-end gap-2">
          <div className="w-24">
            <label htmlFor="quantidade" className="text-xs font-medium text-muted-foreground">
              Quantas
            </label>
            <Input
              id="quantidade"
              inputMode="numeric"
              value={quantidade}
              onChange={(e) => setQuantidade(e.target.value)}
            />
          </div>
          <div className="w-40">
            <label htmlFor="prefixo" className="text-xs font-medium text-muted-foreground">
              Chamadas de
            </label>
            <Input id="prefixo" value={prefixo} onChange={(e) => setPrefixo(e.target.value)} />
          </div>
          <Button
            disabled={enviando}
            onClick={() => rodar(() => criarMesas(Number(quantidade) || 0, prefixo))}
          >
            <Plus className="size-4" aria-hidden="true" />
            Criar
          </Button>
        </div>
      </div>

      {erro ? <p className="text-sm text-destructive">{erro}</p> : null}

      {mesas.length === 0 ? (
        <div className="rounded-xl border border-dashed p-10 text-center">
          <p className="font-semibold">Nenhuma mesa ainda</p>
          <p className="mt-1 text-sm text-muted-foreground">
            Crie as mesas acima. Cada uma ganha um QR Code para imprimir e colar.
          </p>
        </div>
      ) : (
        <>
          <div className="flex flex-wrap items-center justify-between gap-3">
            <p className="text-sm text-muted-foreground">
              {mesas.length} {mesas.length === 1 ? "mesa" : "mesas"} ·{" "}
              {mesas.filter((m) => m.emUso).length} em uso
            </p>
            {/* Link, e nao window.print(): a folha de etiquetas e outra pagina,
                sem menu nem barra lateral, para o papel sair limpo. */}
            <a
              href="/painel/mesas/etiquetas"
              target="_blank"
              rel="noopener"
              className="inline-flex h-9 items-center gap-2 rounded-md bg-marca px-4 text-sm font-semibold text-white transition-colors hover:bg-marca-forte"
            >
              <Printer className="size-4" aria-hidden="true" />
              Imprimir os QR Codes
            </a>
          </div>

          <ul className="divide-y rounded-xl border bg-card">
            {mesas.map((m) => (
              <li key={m.id} className="flex flex-wrap items-center gap-3 p-3 text-sm">
                {editando === m.id ? (
                  <>
                    <Input
                      autoFocus
                      value={nome}
                      onChange={(e) => setNome(e.target.value)}
                      onKeyDown={(e) => e.key === "Enter" && rodar(() => renomearMesa(m.id, nome))}
                      className="max-w-48"
                    />
                    <Button
                      size="sm"
                      disabled={enviando}
                      onClick={() => rodar(() => renomearMesa(m.id, nome))}
                    >
                      <Check className="size-4" aria-hidden="true" />
                    </Button>
                    <Button size="sm" variant="outline" onClick={() => setEditando(null)}>
                      <X className="size-4" aria-hidden="true" />
                    </Button>
                  </>
                ) : (
                  <>
                    <span className="min-w-0 flex-1">
                      <span className="block font-semibold">{m.rotulo}</span>
                      <span className="block font-mono text-[11px] text-muted-foreground">
                        {enderecoDoSite.replace(/^https?:\/\//, "")}/m/{m.codigo}
                      </span>
                    </span>

                    {m.pedidosAbertos > 0 ? (
                      <span className="shrink-0 rounded-md bg-marca/10 px-2 py-1 text-xs font-semibold text-marca">
                        {m.pedidosAbertos} em aberto ·{" "}
                        {(m.contaAbertaCentavos / 100).toFixed(2).replace(".", ",")}
                      </span>
                    ) : null}

                    {!m.emUso ? (
                      <span className="shrink-0 rounded-md bg-muted px-2 py-1 text-xs font-semibold text-muted-foreground">
                        fora de uso
                      </span>
                    ) : null}

                    <div className="flex shrink-0 gap-1">
                      <Button
                        size="sm"
                        variant="ghost"
                        aria-label={`Renomear ${m.rotulo}`}
                        onClick={() => {
                          setEditando(m.id)
                          setNome(m.rotulo)
                        }}
                      >
                        <Pencil className="size-4" aria-hidden="true" />
                      </Button>
                      <Button
                        size="sm"
                        variant="ghost"
                        aria-label={m.emUso ? `Tirar ${m.rotulo} de uso` : `Pôr ${m.rotulo} em uso`}
                        disabled={enviando}
                        onClick={() => rodar(() => mudarUsoDaMesa(m.id, !m.emUso))}
                      >
                        <Power className={`size-4 ${m.emUso ? "" : "text-muted-foreground"}`} aria-hidden="true" />
                      </Button>
                      <Button
                        size="sm"
                        variant="ghost"
                        aria-label={`Remover ${m.rotulo}`}
                        disabled={enviando}
                        onClick={() => rodar(() => removerMesa(m.id))}
                      >
                        <Trash2 className="size-4 text-destructive" aria-hidden="true" />
                      </Button>
                    </div>
                  </>
                )}
              </li>
            ))}
          </ul>
        </>
      )}
    </div>
  )
}
