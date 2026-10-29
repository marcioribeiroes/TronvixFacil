"use client"

import { useState, useTransition } from "react"
import { Check, Pencil, Plus, Power, Printer, Trash2, X } from "lucide-react"

import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { formatarReais } from "@/lib/dinheiro"
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

/**
 * A situacao da mesa vira a cor do cartao, para o salao inteiro ser lido de
 * longe: verde esta livre, vermelho tem pedido na conta, preto esta fora de uso.
 * Mesa fora de uso com pedido antigo ainda aberto fica vermelha - a conta vem
 * antes, e e ela que alguem precisa fechar.
 */
type Situacao = "livre" | "ocupada" | "fora"

function situacao(m: MesaNaTela): Situacao {
  if (m.pedidosAbertos > 0) return "ocupada"
  return m.emUso ? "livre" : "fora"
}

const COR: Record<Situacao, string> = {
  livre: "bg-emerald-600",
  ocupada: "bg-red-600",
  fora: "bg-zinc-900 dark:bg-zinc-800",
}

const ROTULO: Record<Situacao, string> = {
  livre: "Livre",
  ocupada: "Ocupada",
  fora: "Fora de uso",
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

          <ul aria-label="Legenda" className="flex flex-wrap gap-x-4 gap-y-1 text-xs text-muted-foreground">
            {(["livre", "ocupada", "fora"] as const).map((s) => (
              <li key={s} className="inline-flex items-center gap-1.5">
                <span className={`size-3 rounded-sm ${COR[s]}`} aria-hidden="true" />
                {ROTULO[s]}
              </li>
            ))}
          </ul>

          <ul className="grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-4 xl:grid-cols-6">
            {mesas.map((m) => {
              const s = situacao(m)
              return (
                <li
                  key={m.id}
                  className={`flex aspect-square flex-col rounded-xl p-3 text-white shadow-sm ${COR[s]}`}
                >
                  {editando === m.id ? (
                    <div className="flex flex-1 flex-col justify-center gap-2">
                      <Input
                        autoFocus
                        aria-label="Novo nome da mesa"
                        value={nome}
                        onChange={(e) => setNome(e.target.value)}
                        onKeyDown={(e) => e.key === "Enter" && rodar(() => renomearMesa(m.id, nome))}
                        className="bg-white text-foreground"
                      />
                      <div className="flex gap-1">
                        <Button
                          size="sm"
                          variant="secondary"
                          aria-label="Salvar o nome"
                          disabled={enviando}
                          onClick={() => rodar(() => renomearMesa(m.id, nome))}
                        >
                          <Check className="size-4" aria-hidden="true" />
                        </Button>
                        <Button
                          size="sm"
                          variant="secondary"
                          aria-label="Cancelar"
                          onClick={() => setEditando(null)}
                        >
                          <X className="size-4" aria-hidden="true" />
                        </Button>
                      </div>
                    </div>
                  ) : (
                    <>
                      <p className="text-[11px] font-semibold uppercase tracking-wide text-white/80">
                        {ROTULO[s]}
                      </p>
                      <div className="flex flex-1 flex-col items-center justify-center text-center">
                        <p className="text-xl font-bold leading-tight break-words">{m.rotulo}</p>
                        {m.pedidosAbertos > 0 ? (
                          <p className="mt-1 text-sm font-semibold">
                            {m.pedidosAbertos} {m.pedidosAbertos === 1 ? "pedido" : "pedidos"} ·{" "}
                            {formatarReais(m.contaAbertaCentavos)}
                          </p>
                        ) : null}
                        <p
                          className="mt-1 font-mono text-[10px] text-white/70"
                          title={`${enderecoDoSite}/m/${m.codigo}`}
                        >
                          /m/{m.codigo}
                        </p>
                      </div>
                      <div className="flex justify-center gap-0.5">
                        <Button
                          size="sm"
                          variant="ghost"
                          className="text-white hover:bg-white/15 hover:text-white"
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
                          className="text-white hover:bg-white/15 hover:text-white"
                          aria-label={m.emUso ? `Tirar ${m.rotulo} de uso` : `Pôr ${m.rotulo} em uso`}
                          disabled={enviando}
                          onClick={() => rodar(() => mudarUsoDaMesa(m.id, !m.emUso))}
                        >
                          <Power className="size-4" aria-hidden="true" />
                        </Button>
                        <Button
                          size="sm"
                          variant="ghost"
                          className="text-white hover:bg-white/15 hover:text-white"
                          aria-label={`Remover ${m.rotulo}`}
                          disabled={enviando}
                          onClick={() => rodar(() => removerMesa(m.id))}
                        >
                          <Trash2 className="size-4" aria-hidden="true" />
                        </Button>
                      </div>
                    </>
                  )}
                </li>
              )
            })}
          </ul>
        </>
      )}
    </div>
  )
}
