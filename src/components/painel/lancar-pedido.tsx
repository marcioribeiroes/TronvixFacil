"use client"

import { useRouter } from "next/navigation"
import { useState, useTransition } from "react"
import { Bike, Store, Trash2, UtensilsCrossed } from "lucide-react"

import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import {
  ListaDoCardapio,
  type Escolha,
  type Grupo,
  type Secao,
} from "@/components/pedido/cardapio-para-escolher"
import { formatarReais, paraCentavos } from "@/lib/dinheiro"
import {
  FORMAS_DE_PAGAMENTO,
  ROTULO_DA_FORMA,
  formaDePagamento,
  type FormaDePagamento,
} from "@/modules/caixa/formas-de-pagamento"
import { lancarPedido } from "@/modules/painel/pedidos"

type Tipo = "pickup" | "dine_in" | "delivery"

const TIPOS: { tipo: Tipo; rotulo: string; Icone: typeof Store }[] = [
  { tipo: "pickup", rotulo: "Balcão", Icone: Store },
  { tipo: "dine_in", rotulo: "Mesa", Icone: UtensilsCrossed },
  { tipo: "delivery", rotulo: "Entrega", Icone: Bike },
]

/**
 * Lançar um pedido do zero, pelo balcão.
 *
 * Do lado direito o cardápio; do esquerdo, quem pediu, para onde vai e como
 * paga. Nada vai para o banco até "Lançar pedido". O total é prévia: frete e
 * preço de verdade são os que `lancar_pedido` calcula.
 */
export function LancarPedido({
  secoes,
  grupos,
  mesas,
  frete,
}: {
  secoes: Secao[]
  grupos: Grupo[]
  mesas: { id: string; rotulo: string }[]
  /** Regra de frete da loja, para a prévia. */
  frete: { centavos: number; gratisAcimaDe: number | null }
}) {
  const router = useRouter()
  const [enviando, iniciar] = useTransition()
  const [erro, setErro] = useState<string | null>(null)

  const [tipo, setTipo] = useState<Tipo>("pickup")
  const [cliente, setCliente] = useState("")
  const [telefone, setTelefone] = useState("")
  const [mesaId, setMesaId] = useState(mesas[0]?.id ?? "")
  const [mesa, setMesa] = useState("")
  const [endereco, setEndereco] = useState({
    rua: "",
    numero: "",
    complemento: "",
    bairro: "",
    cidade: "",
    cep: "",
  })
  const [forma, setForma] = useState<FormaDePagamento>("cash")
  const [troco, setTroco] = useState("")
  const [receberAgora, setReceberAgora] = useState(false)
  const [observacao, setObservacao] = useState("")
  const [itens, setItens] = useState<(Escolha & { chave: number })[]>([])

  const subtotal = itens.reduce((s, i) => s + i.totalCentavos, 0)
  const freteAgora =
    tipo !== "delivery"
      ? 0
      : frete.gratisAcimaDe !== null && subtotal >= frete.gratisAcimaDe
        ? 0
        : frete.centavos
  const total = subtotal + freteAgora

  function lancar() {
    setErro(null)
    const trocoCentavos = forma === "cash" && troco.trim() ? paraCentavos(troco) : null
    iniciar(async () => {
      const r = await lancarPedido({
        tipo,
        cliente,
        telefone,
        mesa_id: tipo === "dine_in" && mesaId ? mesaId : null,
        mesa,
        endereco,
        forma,
        troco_para_cents: trocoCentavos && trocoCentavos > 0 ? trocoCentavos : null,
        receber_agora: receberAgora,
        observacao,
        itens: itens.map((i) => ({
          produto_id: i.produto.id,
          quantidade: i.quantidade,
          observacao: i.observacao,
          adicionais: i.adicionais,
        })),
      })
      if (r.ok) router.push("/painel/pedidos")
      else setErro(r.erro)
    })
  }

  const campo = (rotulo: string, chave: keyof typeof endereco, classe = "") => (
    <label className={`text-sm ${classe}`}>
      <span className="text-xs text-muted-foreground">{rotulo}</span>
      <Input
        value={endereco[chave]}
        onChange={(e) => setEndereco((atual) => ({ ...atual, [chave]: e.target.value }))}
      />
    </label>
  )

  return (
    <div className="grid gap-6 lg:grid-cols-[minmax(0,1fr)_minmax(0,1.2fr)]">
      <section className="space-y-4 lg:sticky lg:top-20 lg:self-start">
        <div className="grid grid-cols-3 gap-2" role="radiogroup" aria-label="Tipo do pedido">
          {TIPOS.map(({ tipo: t, rotulo, Icone }) => (
            <button
              key={t}
              type="button"
              role="radio"
              aria-checked={tipo === t}
              onClick={() => setTipo(t)}
              className={`flex items-center justify-center gap-2 rounded-lg border px-3 py-2.5 text-sm font-semibold transition-colors ${
                tipo === t ? "border-marca bg-marca-suave text-marca-forte" : "hover:bg-muted"
              }`}
            >
              <Icone className="size-4" aria-hidden="true" />
              {rotulo}
            </button>
          ))}
        </div>

        <div className="grid grid-cols-2 gap-3 rounded-xl border bg-card p-4">
          <label className="text-sm">
            <span className="text-xs text-muted-foreground">Cliente</span>
            <Input
              value={cliente}
              onChange={(e) => setCliente(e.target.value)}
              placeholder={tipo === "dine_in" ? "Opcional" : "Nome"}
            />
          </label>
          <label className="text-sm">
            <span className="text-xs text-muted-foreground">
              Telefone{tipo === "delivery" ? "" : " (opcional)"}
            </span>
            <Input
              value={telefone}
              onChange={(e) => setTelefone(e.target.value)}
              inputMode="tel"
              placeholder="(62) 99999-0000"
            />
          </label>

          {tipo === "dine_in" ? (
            mesas.length > 0 ? (
              <label className="col-span-2 text-sm">
                <span className="text-xs text-muted-foreground">Mesa</span>
                <select
                  value={mesaId}
                  onChange={(e) => setMesaId(e.target.value)}
                  className="h-9 w-full rounded-md border bg-background px-2 text-sm"
                >
                  {mesas.map((m) => (
                    <option key={m.id} value={m.id}>
                      {m.rotulo}
                    </option>
                  ))}
                </select>
              </label>
            ) : (
              <label className="col-span-2 text-sm">
                <span className="text-xs text-muted-foreground">Mesa</span>
                <Input value={mesa} onChange={(e) => setMesa(e.target.value)} placeholder="Mesa 3" />
              </label>
            )
          ) : null}

          {tipo === "delivery" ? (
            <>
              {campo("Rua", "rua", "col-span-2")}
              {campo("Número", "numero")}
              {campo("Complemento", "complemento")}
              {campo("Bairro", "bairro")}
              {campo("Cidade", "cidade")}
            </>
          ) : null}

          <label className="col-span-2 text-sm">
            <span className="text-xs text-muted-foreground">Observação do pedido</span>
            <Input value={observacao} onChange={(e) => setObservacao(e.target.value)} />
          </label>
        </div>

        <ul className="divide-y rounded-xl border bg-card">
          {itens.length === 0 ? (
            <li className="p-4 text-center text-sm text-muted-foreground">
              Escolha os itens no cardápio ao lado.
            </li>
          ) : null}
          {itens.map((i) => (
            <li key={i.chave} className="flex items-start gap-3 p-3 text-sm">
              <div className="min-w-0 flex-1">
                <p className="font-semibold">
                  {i.quantidade}× {i.produto.name}
                </p>
                {grupos
                  .flatMap((g) => g.adicionais)
                  .filter((a) => i.adicionais.includes(a.id))
                  .map((a) => (
                    <p key={a.id} className="text-xs text-muted-foreground">
                      + {a.nome}
                    </p>
                  ))}
                {i.observacao ? (
                  <p className="text-xs font-semibold text-marca-forte">“{i.observacao}”</p>
                ) : null}
              </div>
              <span>{formatarReais(i.totalCentavos)}</span>
              <Button
                size="sm"
                variant="ghost"
                aria-label={`Tirar ${i.produto.name}`}
                onClick={() => setItens((atuais) => atuais.filter((x) => x.chave !== i.chave))}
              >
                <Trash2 className="size-4" aria-hidden="true" />
              </Button>
            </li>
          ))}
        </ul>

        <div className="space-y-3 rounded-xl border bg-card p-4 text-sm">
          <div className="flex flex-wrap items-end gap-3">
            <label>
              <span className="block text-xs text-muted-foreground">Pagamento</span>
              <select
                value={forma}
                onChange={(e) => setForma(formaDePagamento(e.target.value) ?? "cash")}
                className="h-9 rounded-md border bg-background px-2 text-sm"
              >
                {FORMAS_DE_PAGAMENTO.map((f) => (
                  <option key={f} value={f}>
                    {ROTULO_DA_FORMA[f]}
                  </option>
                ))}
              </select>
            </label>
            {forma === "cash" && !receberAgora ? (
              <label>
                <span className="block text-xs text-muted-foreground">Troco para</span>
                <Input
                  value={troco}
                  onChange={(e) => setTroco(e.target.value)}
                  inputMode="decimal"
                  placeholder="R$ 0,00"
                  className="w-28"
                />
              </label>
            ) : null}
            <label className="flex items-center gap-2 pb-2">
              <input
                type="checkbox"
                checked={receberAgora}
                onChange={(e) => setReceberAgora(e.target.checked)}
                className="size-4 accent-marca"
              />
              Já recebido
            </label>
          </div>

          <dl className="space-y-1 border-t pt-3">
            <div className="flex justify-between">
              <dt className="text-muted-foreground">Subtotal</dt>
              <dd>{formatarReais(subtotal)}</dd>
            </div>
            {tipo === "delivery" ? (
              <div className="flex justify-between">
                <dt className="text-muted-foreground">Entrega</dt>
                <dd>{freteAgora === 0 ? "Grátis" : formatarReais(freteAgora)}</dd>
              </div>
            ) : null}
            <div className="flex justify-between text-base font-bold">
              <dt>Total</dt>
              <dd>{formatarReais(total)}</dd>
            </div>
          </dl>
        </div>

        {erro ? (
          <p role="alert" className="text-sm font-medium text-destructive">
            {erro}
          </p>
        ) : null}

        <div className="flex gap-2">
          <Button className="flex-1" onClick={lancar} disabled={enviando || itens.length === 0}>
            Lançar pedido
          </Button>
          <Button variant="outline" onClick={() => router.push("/painel/pedidos")}>
            Voltar
          </Button>
        </div>
      </section>

      <section className="space-y-3">
        <h2 className="text-sm font-bold uppercase tracking-wide">Cardápio</h2>
        <ListaDoCardapio
          secoes={secoes}
          grupos={grupos}
          rotuloDoBotao="Pôr no pedido"
          aoEscolher={async (escolha) => {
            setItens((atuais) => [...atuais, { ...escolha, chave: Date.now() }])
            return { ok: true }
          }}
        />
      </section>
    </div>
  )
}
