"use client"

import { useState, useTransition } from "react"
import { Pencil, Plus, Search, Trash2 } from "lucide-react"

import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { formatarReais } from "@/lib/dinheiro"
import { formatarTelefone } from "@/lib/telefone"
import { enderecoEmUmaLinha, type FichaDigitada } from "@/modules/clientes/ficha"
import { removerCliente, salvarCliente } from "@/modules/painel/clientes"

export type ClienteDoCaderno = {
  id: string
  nome: string
  telefone: string | null
  rua: string | null
  numero: string | null
  complemento: string | null
  bairro: string | null
  cidade: string | null
  observacao: string | null
  /** O que os pedidos dizem dele, achados pelo telefone. */
  pedidos: number
  totalCents: number
  diasDesdeOUltimo: number | null
}

const FICHA_VAZIA: FichaDigitada = {
  nome: "",
  telefone: "",
  rua: "",
  numero: "",
  complemento: "",
  bairro: "",
  cidade: "",
  observacao: "",
}

function fichaDe(c: ClienteDoCaderno): FichaDigitada {
  return {
    nome: c.nome,
    telefone: c.telefone ? formatarTelefone(c.telefone) : "",
    rua: c.rua ?? "",
    numero: c.numero ?? "",
    complemento: c.complemento ?? "",
    bairro: c.bairro ?? "",
    cidade: c.cidade ?? "",
    observacao: c.observacao ?? "",
  }
}

/** Sem acento e sem maiuscula: "joao" acha "João". */
function paraBusca(texto: string) {
  return texto.normalize("NFD").replace(/\p{Diacritic}/gu, "").toLowerCase()
}

/**
 * O caderno de clientes da loja.
 *
 * O freguês do telefone e do balcão, anotado: nome, telefone, endereço e o que
 * vale lembrar ("sem cebola", "interfone quebrado"). Ao lado de cada um, o que
 * os pedidos dizem dele - achados pelo telefone.
 */
export function CadernoDeClientes({ clientes }: { clientes: ClienteDoCaderno[] }) {
  const [enviando, iniciar] = useTransition()
  const [erro, setErro] = useState<string | null>(null)
  const [busca, setBusca] = useState("")
  // null: so a lista. "novo": ficha em branco. Um id: corrigindo esse cliente.
  const [editando, setEditando] = useState<string | null>(null)
  const [ficha, setFicha] = useState<FichaDigitada>(FICHA_VAZIA)
  const [tirando, setTirando] = useState<string | null>(null)

  const termo = paraBusca(busca.trim())
  const digitos = busca.replace(/\D/g, "")
  const filtrados = termo
    ? clientes.filter(
        (c) =>
          paraBusca(c.nome).includes(termo) ||
          (digitos.length >= 3 && (c.telefone ?? "").includes(digitos)),
      )
    : clientes

  function abrir(qual: string, inicial: FichaDigitada) {
    setErro(null)
    setTirando(null)
    setEditando(qual)
    setFicha(inicial)
  }

  function salvar() {
    setErro(null)
    iniciar(async () => {
      const r = await salvarCliente(editando === "novo" ? null : editando, ficha)
      if (r.ok) setEditando(null)
      else setErro(r.erro)
    })
  }

  function tirar(id: string) {
    setErro(null)
    iniciar(async () => {
      const r = await removerCliente(id)
      if (r.ok) setTirando(null)
      else setErro(r.erro)
    })
  }

  const campo = (
    rotulo: string,
    chave: keyof FichaDigitada,
    extra: { classe?: string; placeholder?: string; inputMode?: "tel" } = {},
  ) => (
    <label className={`text-sm ${extra.classe ?? ""}`}>
      <span className="text-xs text-muted-foreground">{rotulo}</span>
      <Input
        value={ficha[chave]}
        onChange={(e) => setFicha((atual) => ({ ...atual, [chave]: e.target.value }))}
        placeholder={extra.placeholder}
        inputMode={extra.inputMode}
        disabled={enviando}
      />
    </label>
  )

  return (
    <section className="space-y-3">
      <div className="flex flex-wrap items-center gap-2">
        <h2 className="text-sm font-bold uppercase tracking-wide text-muted-foreground">
          Clientes cadastrados · {clientes.length}
        </h2>
        <div className="ml-auto flex flex-wrap items-center gap-2">
          <label className="relative">
            <span className="sr-only">Procurar cliente</span>
            <Search
              className="pointer-events-none absolute top-1/2 left-2.5 size-4 -translate-y-1/2 text-muted-foreground"
              aria-hidden="true"
            />
            <Input
              value={busca}
              onChange={(e) => setBusca(e.target.value)}
              placeholder="Nome ou telefone"
              className="w-56 pl-8"
            />
          </label>
          <Button onClick={() => abrir("novo", FICHA_VAZIA)} disabled={enviando}>
            <Plus className="size-4" aria-hidden="true" />
            Novo cliente
          </Button>
        </div>
      </div>

      {editando !== null ? (
        <form
          className="grid gap-3 rounded-xl border bg-card p-4 sm:grid-cols-2"
          onSubmit={(e) => {
            e.preventDefault()
            salvar()
          }}
        >
          <p className="font-semibold sm:col-span-2">
            {editando === "novo" ? "Novo cliente" : "Corrigir cliente"}
          </p>
          {campo("Nome", "nome", { placeholder: "Seu João" })}
          {campo("Telefone", "telefone", { placeholder: "(62) 99999-0000", inputMode: "tel" })}
          {campo("Rua", "rua", { classe: "sm:col-span-2" })}
          {campo("Número", "numero")}
          {campo("Complemento", "complemento", { placeholder: "Apto 302, fundos" })}
          {campo("Bairro", "bairro")}
          {campo("Cidade", "cidade")}
          <label className="text-sm sm:col-span-2">
            <span className="text-xs text-muted-foreground">Observação</span>
            <textarea
              value={ficha.observacao}
              onChange={(e) => setFicha((atual) => ({ ...atual, observacao: e.target.value }))}
              placeholder="Sem cebola. Interfone quebrado, ligar quando chegar."
              rows={2}
              maxLength={500}
              disabled={enviando}
              className="w-full rounded-md border bg-background px-3 py-2 text-sm"
            />
          </label>

          {erro ? (
            <p role="alert" className="text-sm font-medium text-destructive sm:col-span-2">
              {erro}
            </p>
          ) : null}

          <div className="flex gap-2 sm:col-span-2">
            <Button type="submit" disabled={enviando}>
              {editando === "novo" ? "Cadastrar" : "Salvar"}
            </Button>
            <Button
              type="button"
              variant="outline"
              onClick={() => setEditando(null)}
              disabled={enviando}
            >
              Cancelar
            </Button>
          </div>
        </form>
      ) : erro ? (
        <p role="alert" className="text-sm font-medium text-destructive">
          {erro}
        </p>
      ) : null}

      <ul className="divide-y rounded-xl border bg-card">
        {filtrados.map((c) => {
          const endereco = enderecoEmUmaLinha(c)
          return (
            <li key={c.id} className="flex flex-wrap items-start gap-x-3 gap-y-1 p-3 text-sm">
              <span className="min-w-0 flex-1">
                <span className="block truncate font-medium">{c.nome}</span>
                <span className="block text-xs text-muted-foreground">
                  {c.telefone ? formatarTelefone(c.telefone) : "sem telefone"}
                  {endereco ? ` · ${endereco}` : ""}
                </span>
                {c.observacao ? (
                  <span className="mt-0.5 block text-xs font-semibold text-marca-forte">
                    “{c.observacao}”
                  </span>
                ) : null}
              </span>

              <span className="shrink-0 text-right text-xs text-muted-foreground">
                {c.pedidos > 0 ? (
                  <>
                    <span className="block font-bold text-foreground">
                      {formatarReais(c.totalCents)}
                    </span>
                    {c.pedidos} {c.pedidos === 1 ? "pedido" : "pedidos"}
                    {c.diasDesdeOUltimo !== null
                      ? ` · ${
                          c.diasDesdeOUltimo === 0
                            ? "hoje"
                            : c.diasDesdeOUltimo === 1
                              ? "ontem"
                              : `há ${c.diasDesdeOUltimo} dias`
                        }`
                      : ""}
                  </>
                ) : (
                  "nenhum pedido ainda"
                )}
              </span>

              {tirando === c.id ? (
                <span className="flex shrink-0 items-center gap-1">
                  <span className="text-xs text-muted-foreground">Tirar da lista?</span>
                  <Button
                    size="sm"
                    variant="destructive"
                    onClick={() => tirar(c.id)}
                    disabled={enviando}
                  >
                    Tirar
                  </Button>
                  <Button
                    size="sm"
                    variant="ghost"
                    onClick={() => setTirando(null)}
                    disabled={enviando}
                  >
                    Não
                  </Button>
                </span>
              ) : (
                <span className="flex shrink-0 gap-1">
                  <Button
                    size="sm"
                    variant="ghost"
                    aria-label={`Corrigir ${c.nome}`}
                    onClick={() => abrir(c.id, fichaDe(c))}
                    disabled={enviando}
                  >
                    <Pencil className="size-4" aria-hidden="true" />
                  </Button>
                  <Button
                    size="sm"
                    variant="ghost"
                    aria-label={`Tirar ${c.nome} da lista`}
                    onClick={() => setTirando(c.id)}
                    disabled={enviando}
                  >
                    <Trash2 className="size-4" aria-hidden="true" />
                  </Button>
                </span>
              )}
            </li>
          )
        })}

        {filtrados.length === 0 ? (
          <li className="p-4 text-center text-sm text-muted-foreground">
            {clientes.length === 0
              ? "Nenhum cliente cadastrado ainda. Use “Novo cliente” para anotar o primeiro."
              : "Nenhum cliente com esse nome ou telefone."}
          </li>
        ) : null}
      </ul>
    </section>
  )
}
