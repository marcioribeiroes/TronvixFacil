"use client"

import { useState } from "react"
import { Search, UserRound, X } from "lucide-react"

import { Input } from "@/components/ui/input"
import { formatarTelefone } from "@/lib/telefone"
import { clienteCombina } from "@/modules/clientes/busca"
import { enderecoEmUmaLinha } from "@/modules/clientes/ficha"

/** O cliente do caderno da loja, como o novo pedido precisa dele. */
export type ClienteCadastrado = {
  id: string
  nome: string
  telefone: string | null
  rua: string | null
  numero: string | null
  complemento: string | null
  bairro: string | null
  cidade: string | null
  observacao: string | null
}

/** Quantos aparecem na lista de uma vez: o resto se acha digitando mais. */
const MOSTRADOS = 8

/**
 * Escolher, no novo pedido, um cliente cadastrado na tela Clientes.
 *
 * O freguês do telefone liga, a pessoa do balcão digita "joao" ou um pedaço do
 * número, escolhe - e nome, telefone e endereço já vêm preenchidos. Os campos
 * continuam editáveis: hoje ele pode estar pedindo para outro endereço.
 */
export function EscolherCliente({
  clientes,
  escolhido,
  aoEscolher,
  aoLimpar,
}: {
  clientes: ClienteCadastrado[]
  escolhido: ClienteCadastrado | null
  aoEscolher: (cliente: ClienteCadastrado) => void
  aoLimpar: () => void
}) {
  const [busca, setBusca] = useState("")
  const [aberto, setAberto] = useState(false)

  if (escolhido) {
    return (
      <div className="space-y-2 rounded-xl border border-marca/40 bg-marca-suave/40 p-3 text-sm">
        <div className="flex items-start gap-2">
          <UserRound className="mt-0.5 size-4 shrink-0 text-marca-forte" aria-hidden="true" />
          <div className="min-w-0 flex-1">
            <p className="font-semibold">{escolhido.nome}</p>
            <p className="text-xs text-muted-foreground">
              {[
                escolhido.telefone ? formatarTelefone(escolhido.telefone) : null,
                enderecoEmUmaLinha(escolhido) || null,
              ]
                .filter(Boolean)
                .join(" · ") || "sem telefone e sem endereço"}
            </p>
          </div>
          <button
            type="button"
            onClick={aoLimpar}
            className="inline-flex items-center gap-1 text-xs font-medium text-muted-foreground underline underline-offset-2 hover:text-foreground"
          >
            <X className="size-3.5" aria-hidden="true" />
            Trocar cliente
          </button>
        </div>
        {/* O que a loja anotou dele: quem lança precisa ver antes de mandar
            para a cozinha ("sem cebola", "interfone quebrado"). */}
        {escolhido.observacao ? (
          <p className="rounded-lg bg-background/70 px-2.5 py-1.5 text-xs font-semibold text-marca-forte">
            “{escolhido.observacao}”
          </p>
        ) : null}
      </div>
    )
  }

  if (clientes.length === 0) return null

  const achados = clientes.filter((c) => clienteCombina(c, busca))
  const mostrar = aberto || busca.trim() !== ""

  return (
    <div className="relative">
      <label className="relative block">
        <span className="sr-only">Procurar cliente cadastrado por nome ou telefone</span>
        <Search
          className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-muted-foreground"
          aria-hidden="true"
        />
        <Input
          value={busca}
          onChange={(e) => setBusca(e.target.value)}
          onFocus={() => setAberto(true)}
          // Fecha depois do clique na lista, e nao antes dele: sem o atraso, o
          // clique caia no campo que ja tinha sumido.
          onBlur={() => setTimeout(() => setAberto(false), 150)}
          onKeyDown={(e) => {
            if (e.key === "Escape") {
              setBusca("")
              setAberto(false)
            }
            if (e.key === "Enter" && achados.length === 1) {
              e.preventDefault()
              aoEscolher(achados[0])
              setBusca("")
            }
          }}
          placeholder="Cliente cadastrado: nome ou telefone"
          className="h-10 pl-9"
          role="combobox"
          aria-expanded={mostrar}
          aria-controls="clientes-cadastrados"
          autoComplete="off"
        />
      </label>

      {mostrar ? (
        <ul
          id="clientes-cadastrados"
          role="listbox"
          className="absolute inset-x-0 top-full z-20 mt-1 max-h-72 divide-y overflow-y-auto rounded-xl border bg-popover text-sm shadow-lg"
        >
          {achados.slice(0, MOSTRADOS).map((c) => {
            const endereco = enderecoEmUmaLinha(c)
            return (
              <li key={c.id} role="option" aria-selected={false}>
                <button
                  type="button"
                  // onMouseDown, e nao onClick: dispara antes do blur do campo.
                  onMouseDown={(e) => {
                    e.preventDefault()
                    aoEscolher(c)
                    setBusca("")
                    setAberto(false)
                  }}
                  className="block w-full px-3 py-2 text-left hover:bg-muted"
                >
                  <span className="block font-medium">{c.nome}</span>
                  <span className="block truncate text-xs text-muted-foreground">
                    {[c.telefone ? formatarTelefone(c.telefone) : "sem telefone", endereco || null]
                      .filter(Boolean)
                      .join(" · ")}
                  </span>
                </button>
              </li>
            )
          })}
          {achados.length === 0 ? (
            <li className="px-3 py-2 text-muted-foreground">
              Nenhum cliente cadastrado com esse nome ou telefone.
            </li>
          ) : achados.length > MOSTRADOS ? (
            <li className="px-3 py-2 text-xs text-muted-foreground">
              Mais {achados.length - MOSTRADOS}: digite mais do nome ou do telefone.
            </li>
          ) : null}
        </ul>
      ) : null}
    </div>
  )
}
