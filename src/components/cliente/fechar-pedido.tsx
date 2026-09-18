"use client"

import { useRouter } from "next/navigation"
import { useState, useTransition } from "react"
import Link from "next/link"
import { Minus, Plus, Trash2 } from "lucide-react"

import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { formatarReais } from "@/lib/dinheiro"
import {
  esvaziarCarrinho,
  fecharPedido,
  mudarQuantidade,
  simularCupom,
} from "@/modules/cliente/carrinho"
import type { Enums } from "@/types/banco"

type Item = {
  id: string
  quantidade: number
  observacao: string | null
  produto: {
    nome: string
    precoCentavos: number
    promoCentavos: number | null
    promoComeca: string | null
    promoTermina: string | null
  }
  adicionais: { nome: string; precoCentavos: number }[]
}

const ROTULO_DA_FORMA: Record<string, string> = {
  pix: "Pix",
  credit_card: "Cartão de crédito",
  debit_card: "Cartão de débito",
  cash: "Dinheiro",
  meal_voucher: "Vale-refeição",
}

function precoQueVale(p: Item["produto"]) {
  if (p.promoCentavos === null) return p.precoCentavos
  const agora = new Date()
  if (p.promoComeca && new Date(p.promoComeca) > agora) return p.precoCentavos
  if (p.promoTermina && new Date(p.promoTermina) < agora) return p.precoCentavos
  return p.promoCentavos
}

/**
 * Carrinho e fechamento na mesma tela.
 *
 * No celular o app separa em dois passos; aqui a tela e larga e dividir seria
 * clique a mais. O que NAO muda: os totais desta tela sao estimativa. Quem
 * cobra e `fechar_pedido`, no banco, recalculando do cardapio daquele
 * instante — e e por isso que a tela nao manda nenhum valor.
 */
export function FecharPedido({
  loja,
  itens,
  enderecos,
  formasAceitas,
}: {
  loja: {
    id: string
    nome: string
    aberta: boolean
    taxaCentavos: number
    freteGratisAcima: number | null
    minimoCentavos: number
  }
  itens: Item[]
  enderecos: { id: string; rotulo: string; resumo: string }[]
  formasAceitas: string[]
}) {
  const router = useRouter()
  const [enviando, iniciar] = useTransition()
  const [erro, setErro] = useState<string | null>(null)

  const [tipo, setTipo] = useState<Enums<"fulfillment_type">>("delivery")
  const [enderecoId, setEnderecoId] = useState(enderecos[0]?.id ?? "")
  const [observacao, setObservacao] = useState("")
  const [cupom, setCupom] = useState("")
  const [cupomAplicado, setCupomAplicado] = useState<string | null>(null)
  const [desconto, setDesconto] = useState(0)
  const [troco, setTroco] = useState("")

  // Sem forma cadastrada, dinheiro na entrega — o padrão que nunca depende de
  // integração. E a preferida é uma de porta enquanto o gateway é simulado:
  // pedido "pago pelo app" nasce aguardando pagamento e nunca chega ao balcão.
  const formas = formasAceitas.length > 0 ? formasAceitas : ["cash"]
  const [forma, setForma] = useState<Enums<"payment_method">>(
    (formas.find((f) => f !== "pix" && f !== "credit_card") ?? formas[0]) as Enums<"payment_method">,
  )

  const subtotal = itens.reduce(
    (soma, i) =>
      soma +
      (precoQueVale(i.produto) + i.adicionais.reduce((s, a) => s + a.precoCentavos, 0)) *
        i.quantidade,
    0,
  )

  const taxa =
    tipo === "pickup"
      ? 0
      : loja.freteGratisAcima !== null && subtotal >= loja.freteGratisAcima
        ? 0
        : loja.taxaCentavos

  const total = subtotal + taxa - desconto
  const falta = Math.max(0, loja.minimoCentavos - subtotal)

  function aplicarCupom() {
    if (!cupom.trim()) return
    setErro(null)
    iniciar(async () => {
      const r = await simularCupom({
        codigo: cupom,
        restauranteId: loja.id,
        subtotalCentavos: subtotal,
        taxaCentavos: taxa,
      })
      if (r.ok) {
        setDesconto(r.descontoCentavos)
        setCupomAplicado(cupom.trim().toUpperCase())
      } else {
        setDesconto(0)
        setCupomAplicado(null)
        setErro(r.erro)
      }
    })
  }

  function fechar() {
    setErro(null)
    if (tipo === "delivery" && !enderecoId) {
      setErro("Escolha onde entregar.")
      return
    }
    iniciar(async () => {
      const r = await fecharPedido({
        tipo,
        forma,
        enderecoId,
        cupom: cupomAplicado ?? undefined,
        observacao,
        trocoPara: troco,
      })
      if (r.ok && r.id) router.push(`/pedidos/${r.id}`)
      else if (!r.ok) setErro(r.erro)
    })
  }

  return (
    <div className="space-y-6">
      <ul className="divide-y rounded-xl border bg-card">
        {itens.map((i) => (
          <li key={i.id} className="flex items-start gap-3 p-4">
            <div className="min-w-0 flex-1">
              <p className="font-semibold">{i.produto.nome}</p>
              {i.adicionais.map((a) => (
                <p key={a.nome} className="text-sm text-muted-foreground">
                  + {a.nome}
                </p>
              ))}
              {i.observacao ? (
                <p className="text-sm italic text-muted-foreground">“{i.observacao}”</p>
              ) : null}
            </div>

            <div className="flex items-center rounded-lg border">
              <Button
                size="sm"
                variant="ghost"
                disabled={enviando}
                aria-label="Menos um"
                onClick={() => iniciar(async () => void (await mudarQuantidade(i.id, i.quantidade - 1)))}
              >
                {i.quantidade === 1 ? (
                  <Trash2 className="size-4" aria-hidden="true" />
                ) : (
                  <Minus className="size-4" aria-hidden="true" />
                )}
              </Button>
              <span className="w-7 text-center text-sm font-bold">{i.quantidade}</span>
              <Button
                size="sm"
                variant="ghost"
                disabled={enviando}
                aria-label="Mais um"
                onClick={() => iniciar(async () => void (await mudarQuantidade(i.id, i.quantidade + 1)))}
              >
                <Plus className="size-4" aria-hidden="true" />
              </Button>
            </div>

            <span className="w-20 text-right font-semibold">
              {formatarReais(
                (precoQueVale(i.produto) +
                  i.adicionais.reduce((s, a) => s + a.precoCentavos, 0)) *
                  i.quantidade,
              )}
            </span>
          </li>
        ))}
      </ul>

      <section>
        <h2 className="font-bold">Como você quer receber</h2>
        <div className="mt-2 flex gap-2">
          {(["delivery", "pickup"] as const).map((t) => (
            <Button
              key={t}
              variant={tipo === t ? "default" : "outline"}
              onClick={() => setTipo(t)}
            >
              {t === "delivery" ? "Entrega" : "Retirar no balcão"}
            </Button>
          ))}
        </div>
      </section>

      {tipo === "delivery" ? (
        <section>
          <h2 className="font-bold">Onde entregar</h2>
          {enderecos.length === 0 ? (
            <p className="mt-2 text-sm text-muted-foreground">
              Você ainda não tem endereço salvo.{" "}
              <Link href="/conta/enderecos" className="font-semibold text-marca hover:underline">
                Cadastrar
              </Link>
            </p>
          ) : (
            <ul className="mt-2 divide-y rounded-xl border bg-card">
              {enderecos.map((e) => (
                <li key={e.id}>
                  <label className="flex cursor-pointer items-center gap-3 p-3">
                    <input
                      type="radio"
                      name="endereco"
                      checked={enderecoId === e.id}
                      onChange={() => setEnderecoId(e.id)}
                      className="size-4 accent-marca"
                    />
                    <span>
                      <span className="font-semibold">{e.rotulo}</span>
                      <span className="block text-sm text-muted-foreground">{e.resumo}</span>
                    </span>
                  </label>
                </li>
              ))}
            </ul>
          )}
        </section>
      ) : null}

      <section>
        <h2 className="font-bold">Como pagar</h2>
        <ul className="mt-2 divide-y rounded-xl border bg-card">
          {formas.map((f) => (
            <li key={f}>
              <label className="flex cursor-pointer items-center gap-3 p-3">
                <input
                  type="radio"
                  name="forma"
                  checked={forma === f}
                  onChange={() => setForma(f as Enums<"payment_method">)}
                  className="size-4 accent-marca"
                />
                <span className="flex-1">{ROTULO_DA_FORMA[f] ?? f}</span>
                <span className="text-sm text-muted-foreground">
                  {f === "pix" || f === "credit_card" ? "pelo site" : "na entrega"}
                </span>
              </label>
            </li>
          ))}
        </ul>

        {forma === "cash" ? (
          <div className="mt-3">
            <label htmlFor="troco" className="text-sm font-medium">
              Precisa de troco para quanto?
            </label>
            <Input
              id="troco"
              value={troco}
              onChange={(e) => setTroco(e.target.value)}
              placeholder="deixe vazio se tiver o valor certo"
              inputMode="decimal"
              className="mt-1"
            />
          </div>
        ) : null}
      </section>

      <section>
        <h2 className="font-bold">Cupom</h2>
        <div className="mt-2 flex gap-2">
          <Input
            value={cupom}
            onChange={(e) => setCupom(e.target.value.toUpperCase())}
            placeholder="Tem um código?"
          />
          <Button variant="outline" onClick={aplicarCupom} disabled={enviando}>
            Aplicar
          </Button>
        </div>
      </section>

      <section>
        <label htmlFor="obs-pedido" className="font-bold">
          Observação para o restaurante
        </label>
        <Input
          id="obs-pedido"
          value={observacao}
          onChange={(e) => setObservacao(e.target.value)}
          placeholder="Interfone quebrado, ligar ao chegar"
          maxLength={200}
          className="mt-2"
        />
      </section>

      <dl className="space-y-1.5 rounded-xl border bg-card p-4 text-sm">
        <div className="flex justify-between">
          <dt className="text-muted-foreground">Subtotal</dt>
          <dd>{formatarReais(subtotal)}</dd>
        </div>
        <div className="flex justify-between">
          <dt className="text-muted-foreground">
            {tipo === "pickup" ? "Retirada no balcão" : "Entrega"}
          </dt>
          <dd className={taxa === 0 ? "font-semibold text-status-pronto" : ""}>
            {taxa === 0 ? "Grátis" : formatarReais(taxa)}
          </dd>
        </div>
        {desconto > 0 ? (
          <div className="flex justify-between text-status-pronto">
            <dt>Cupom {cupomAplicado}</dt>
            <dd>− {formatarReais(desconto)}</dd>
          </div>
        ) : null}
        <div className="flex justify-between border-t pt-2 text-base font-bold">
          <dt>Total</dt>
          <dd>{formatarReais(total)}</dd>
        </div>
      </dl>

      {falta > 0 ? (
        <p className="rounded-lg bg-marca-suave px-4 py-3 text-sm text-marca-forte">
          Faltam {formatarReais(falta)} para o pedido mínimo deste estabelecimento.
        </p>
      ) : null}

      {erro ? (
        <p role="alert" className="text-sm font-medium text-destructive">
          {erro}
        </p>
      ) : null}

      <div className="flex gap-2">
        <Button
          className="flex-1"
          onClick={fechar}
          disabled={enviando || falta > 0 || !loja.aberta}
        >
          {!loja.aberta
            ? "Restaurante fechado"
            : enviando
              ? "Enviando…"
              : `Fazer pedido · ${formatarReais(total)}`}
        </Button>
        <Button
          variant="ghost"
          disabled={enviando}
          onClick={() => iniciar(async () => void (await esvaziarCarrinho()))}
        >
          Esvaziar
        </Button>
      </div>
    </div>
  )
}
