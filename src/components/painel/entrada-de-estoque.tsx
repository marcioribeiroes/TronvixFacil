"use client"

import { useRef, useState, useTransition } from "react"
import { Minus, Plus, ScanBarcode, Trash2 } from "lucide-react"

import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { darEntradaNoEstoque } from "@/modules/painel/estoque"

type Produto = {
  id: string
  nome: string
  codigoDeBarras: string | null
  saldo: number
  controlaEstoque: boolean
}

type Item = { produto: Produto; quantidade: string }

/** Sem acento e sem caixa: "acai" acha "Açaí". */
function normalizar(texto: string) {
  return texto.normalize("NFD").replace(/\p{Diacritic}/gu, "").toLowerCase()
}

/**
 * O leitor de codigo de barras USB e um teclado: digita o codigo e aperta
 * Enter. Entao o campo de leitura faz as duas coisas - recebe o leitor e aceita
 * nome digitado - e o Enter decide: codigo exato entra direto (lido de novo,
 * soma mais um), nome com um resultado so tambem. O foco volta ao campo depois
 * de cada item, para a proxima embalagem poder ser lida sem tocar no mouse.
 */
export function EntradaDeEstoque({ produtos }: { produtos: Produto[] }) {
  const [enviando, iniciar] = useTransition()
  const [busca, setBusca] = useState("")
  const [itens, setItens] = useState<Item[]>([])
  const [observacao, setObservacao] = useState("")
  const [aviso, setAviso] = useState<{ tipo: "erro" | "ok"; texto: string } | null>(null)
  const campo = useRef<HTMLInputElement>(null)

  const termo = normalizar(busca.trim())
  const sugestoes =
    termo.length >= 2
      ? produtos
          .filter(
            (p) => normalizar(p.nome).includes(termo) || p.codigoDeBarras?.includes(busca.trim()),
          )
          .slice(0, 8)
      : []

  function acrescentar(produto: Produto) {
    setItens((atuais) => {
      const existente = atuais.find((i) => i.produto.id === produto.id)
      if (existente) {
        return atuais.map((i) =>
          i.produto.id === produto.id
            ? { ...i, quantidade: String((Number(i.quantidade) || 0) + 1) }
            : i,
        )
      }
      return [...atuais, { produto, quantidade: "1" }]
    })
    setBusca("")
    setAviso(null)
    campo.current?.focus()
  }

  function lerCampo() {
    const lido = busca.replace(/\s+/g, "")
    if (!lido) return

    const peloCodigo = produtos.find((p) => p.codigoDeBarras === lido)
    if (peloCodigo) return acrescentar(peloCodigo)
    if (sugestoes.length === 1) return acrescentar(sugestoes[0])

    setAviso({
      tipo: "erro",
      texto:
        sugestoes.length > 1
          ? "Mais de um produto com esse nome: escolha na lista."
          : `Nenhum produto com o código ${lido}. Cadastre o código em Produtos ou procure pelo nome.`,
    })
    if (sugestoes.length === 0) setBusca("")
  }

  function mudarQuantidade(id: string, quantidade: string) {
    setItens((atuais) =>
      atuais.map((i) => (i.produto.id === id ? { ...i, quantidade: quantidade.replace(/\D/g, "") } : i)),
    )
  }

  function remover(id: string) {
    setItens((atuais) => atuais.filter((i) => i.produto.id !== id))
  }

  const unidades = itens.reduce((soma, i) => soma + (Number(i.quantidade) || 0), 0)

  function confirmar() {
    setAviso(null)
    iniciar(async () => {
      const r = await darEntradaNoEstoque({
        itens: itens.map((i) => ({ produto: i.produto.id, quantidade: Number(i.quantidade) })),
        observacao,
      })
      if (r.ok) {
        setItens([])
        setObservacao("")
        setAviso({
          tipo: "ok",
          texto: `Entrada registrada: ${r.unidades} ${r.unidades === 1 ? "unidade" : "unidades"}.`,
        })
        campo.current?.focus()
      } else {
        setAviso({ tipo: "erro", texto: r.erro })
      }
    })
  }

  return (
    <div className="space-y-4 rounded-xl border bg-card p-5">
      <div className="relative">
        <Label htmlFor="leitura">Código de barras ou nome do produto</Label>
        <div className="relative mt-1">
          <ScanBarcode
            className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-muted-foreground"
            aria-hidden="true"
          />
          <Input
            id="leitura"
            ref={campo}
            value={busca}
            onChange={(e) => setBusca(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter") {
                e.preventDefault()
                lerCampo()
              }
            }}
            placeholder="Leia com o leitor ou digite e aperte Enter"
            autoComplete="off"
            autoFocus
            className="pl-9"
          />
        </div>

        {sugestoes.length > 0 ? (
          <ul className="absolute z-10 mt-1 w-full divide-y overflow-hidden rounded-lg border bg-popover shadow-md">
            {sugestoes.map((p) => (
              <li key={p.id}>
                <button
                  type="button"
                  onClick={() => acrescentar(p)}
                  className="flex w-full items-center justify-between gap-3 px-3 py-2 text-left text-sm hover:bg-muted"
                >
                  <span className="min-w-0 truncate font-medium">{p.nome}</span>
                  <span className="shrink-0 text-xs text-muted-foreground">
                    {p.controlaEstoque ? `${p.saldo} em estoque` : "sem controle"}
                  </span>
                </button>
              </li>
            ))}
          </ul>
        ) : null}
      </div>

      {aviso ? (
        <p
          role={aviso.tipo === "erro" ? "alert" : "status"}
          className={
            aviso.tipo === "erro"
              ? "text-sm font-medium text-destructive"
              : "text-sm font-medium text-status-pronto"
          }
        >
          {aviso.texto}
        </p>
      ) : null}

      {itens.length > 0 ? (
        <>
          <ul className="divide-y rounded-lg border">
            {itens.map(({ produto: p, quantidade }) => {
              const qtd = Number(quantidade) || 0
              return (
                <li key={p.id} className="flex flex-wrap items-center gap-3 p-3 text-sm">
                  <span className="min-w-0 flex-1">
                    <span className="block truncate font-medium">{p.nome}</span>
                    <span className="block text-xs text-muted-foreground">
                      {p.controlaEstoque ? `tem ${p.saldo}, fica com ${p.saldo + qtd}` : `passa a controlar estoque: fica com ${qtd}`}
                    </span>
                  </span>
                  <div className="flex items-center gap-1">
                    <Button
                      size="sm"
                      variant="ghost"
                      aria-label={`Uma unidade a menos de ${p.nome}`}
                      disabled={qtd <= 1}
                      onClick={() => mudarQuantidade(p.id, String(qtd - 1))}
                    >
                      <Minus className="size-4" aria-hidden="true" />
                    </Button>
                    <Input
                      value={quantidade}
                      onChange={(e) => mudarQuantidade(p.id, e.target.value)}
                      className="w-20 text-center"
                      inputMode="numeric"
                      aria-label={`Quantidade de ${p.nome}`}
                    />
                    <Button
                      size="sm"
                      variant="ghost"
                      aria-label={`Uma unidade a mais de ${p.nome}`}
                      onClick={() => mudarQuantidade(p.id, String(qtd + 1))}
                    >
                      <Plus className="size-4" aria-hidden="true" />
                    </Button>
                    <Button
                      size="sm"
                      variant="ghost"
                      aria-label={`Tirar ${p.nome} da entrada`}
                      onClick={() => remover(p.id)}
                    >
                      <Trash2 className="size-4" aria-hidden="true" />
                    </Button>
                  </div>
                </li>
              )
            })}
          </ul>

          <div>
            <Label htmlFor="observacao">Observação</Label>
            <Input
              id="observacao"
              value={observacao}
              onChange={(e) => setObservacao(e.target.value)}
              placeholder="Nota fiscal, fornecedor (opcional)"
              maxLength={200}
            />
          </div>

          <div className="flex flex-wrap gap-2">
            <Button onClick={confirmar} disabled={enviando || unidades === 0}>
              {enviando
                ? "Registrando…"
                : `Dar entrada · ${unidades} ${unidades === 1 ? "unidade" : "unidades"}`}
            </Button>
            <Button variant="ghost" onClick={() => setItens([])} disabled={enviando}>
              Limpar
            </Button>
          </div>
        </>
      ) : (
        <p className="text-sm text-muted-foreground">
          Os produtos lidos aparecem aqui. Ler o mesmo código de novo soma mais uma unidade.
        </p>
      )}
    </div>
  )
}
