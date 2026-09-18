"use client"

import { useState, useTransition } from "react"
import { Plus, Trash2 } from "lucide-react"

import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { formatarReais } from "@/lib/dinheiro"
import {
  mudarSituacaoDoCupom,
  removerCupom,
  salvarCupom,
} from "@/modules/admin/plataforma"
import type { Enums } from "@/types/banco"

type Cupom = {
  id: string
  code: string
  description: string | null
  scope: string
  restaurant_id: string | null
  discount: string
  value: number
  min_order_cents: number
  max_discount_cents: number | null
  ends_at: string | null
  max_uses: number | null
  max_uses_per_customer: number
  used_count: number
  first_order_only: boolean
  is_active: boolean
  restaurants: { name: string } | null
}

/** O que o cupom abate, em uma frase. */
function oQueAbate(c: Cupom) {
  if (c.discount === "percentage") return `${(c.value / 100).toLocaleString("pt-BR")}%`
  if (c.discount === "fixed") return formatarReais(c.value)
  return "Frete grátis"
}

export function ListaDeCupons({
  cupons,
  estabelecimentos,
}: {
  cupons: Cupom[]
  estabelecimentos: { id: string; nome: string }[]
}) {
  const [criando, setCriando] = useState(false)

  return (
    <div className="space-y-5">
      <Button onClick={() => setCriando((v) => !v)}>
        <Plus className="size-4" aria-hidden="true" />
        Novo cupom
      </Button>

      {criando ? (
        <FormularioDeCupom
          estabelecimentos={estabelecimentos}
          aoFechar={() => setCriando(false)}
        />
      ) : null}

      {cupons.length === 0 ? (
        <div className="rounded-xl border border-dashed p-10 text-center">
          <p className="font-semibold">Nenhum cupom</p>
          <p className="mt-1 text-sm text-muted-foreground">
            Crie o primeiro acima. O desconto é calculado pelo banco, na hora de
            fechar o pedido.
          </p>
        </div>
      ) : (
        <ul className="divide-y rounded-xl border bg-card">
          {cupons.map((c) => (
            <LinhaDoCupom key={c.id} cupom={c} />
          ))}
        </ul>
      )}
    </div>
  )
}

function LinhaDoCupom({ cupom: c }: { cupom: Cupom }) {
  const [enviando, iniciar] = useTransition()
  const [erro, setErro] = useState<string | null>(null)

  const vencido = c.ends_at !== null && new Date(c.ends_at) < new Date()
  const esgotado = c.max_uses !== null && c.used_count >= c.max_uses

  return (
    <li className="flex flex-wrap items-center gap-3 p-4">
      <div className="min-w-0 flex-1">
        <div className="flex flex-wrap items-center gap-2">
          <code className="rounded bg-muted px-2 py-0.5 font-bold">{c.code}</code>
          <Badge>{oQueAbate(c)}</Badge>
          <Badge variant="secondary">
            {c.scope === "platform" ? "Plataforma" : (c.restaurants?.name ?? "Loja")}
          </Badge>
          {vencido ? <Badge variant="destructive">Vencido</Badge> : null}
          {esgotado ? <Badge variant="destructive">Esgotado</Badge> : null}
          {c.first_order_only ? <Badge variant="outline">1º pedido</Badge> : null}
        </div>

        <p className="mt-1 text-sm text-muted-foreground">
          {c.description ? `${c.description} · ` : ""}
          usado {c.used_count}
          {c.max_uses ? `/${c.max_uses}` : ""} vez(es) · {c.max_uses_per_customer} por cliente
          {c.min_order_cents > 0 ? ` · mínimo ${formatarReais(c.min_order_cents)}` : ""}
          {c.ends_at ? ` · até ${new Date(c.ends_at).toLocaleDateString("pt-BR")}` : ""}
        </p>
      </div>

      <label className="flex cursor-pointer items-center gap-2 text-sm">
        <input
          type="checkbox"
          checked={c.is_active}
          disabled={enviando}
          className="size-4 accent-marca"
          onChange={(e) =>
            iniciar(async () => {
              const r = await mudarSituacaoDoCupom(c.id, e.target.checked)
              if (!r.ok) setErro(r.erro)
            })
          }
        />
        {c.is_active ? "Ativo" : "Pausado"}
      </label>

      <Button
        size="sm"
        variant="ghost"
        disabled={enviando}
        aria-label={`Remover ${c.code}`}
        onClick={() =>
          iniciar(async () => {
            const r = await removerCupom(c.id)
            if (!r.ok) setErro(r.erro)
          })
        }
      >
        <Trash2 className="size-4" aria-hidden="true" />
      </Button>

      {erro ? (
        <p role="alert" className="w-full text-sm font-medium text-destructive">
          {erro}
        </p>
      ) : null}
    </li>
  )
}

function FormularioDeCupom({
  estabelecimentos,
  aoFechar,
}: {
  estabelecimentos: { id: string; nome: string }[]
  aoFechar: () => void
}) {
  const [enviando, iniciar] = useTransition()
  const [erro, setErro] = useState<string | null>(null)

  const [codigo, setCodigo] = useState("")
  const [descricao, setDescricao] = useState("")
  const [tipo, setTipo] = useState<Enums<"discount_type">>("percentage")
  const [valor, setValor] = useState("")
  const [minimo, setMinimo] = useState("")
  const [tetoDoDesconto, setTeto] = useState("")
  const [terminaEm, setTerminaEm] = useState("")
  const [usosMaximos, setUsosMaximos] = useState("")
  const [usosPorCliente, setUsosPorCliente] = useState("1")
  const [soPrimeiro, setSoPrimeiro] = useState(false)
  const [restauranteId, setRestauranteId] = useState("")

  return (
    <div className="rounded-xl border bg-card p-5">
      <h2 className="font-bold">Novo cupom</h2>

      <div className="mt-4 grid gap-4 sm:grid-cols-3">
        <div>
          <Label htmlFor="codigo">Código</Label>
          <Input
            id="codigo"
            value={codigo}
            onChange={(e) => setCodigo(e.target.value.toUpperCase())}
            placeholder="BEMVINDO10"
          />
        </div>

        <div>
          <Label htmlFor="tipo">Desconto</Label>
          <select
            id="tipo"
            value={tipo}
            onChange={(e) => setTipo(e.target.value as Enums<"discount_type">)}
            className="h-10 w-full rounded-lg border bg-background px-3 text-sm"
          >
            <option value="percentage">Percentual</option>
            <option value="fixed">Valor fixo</option>
            <option value="free_shipping">Frete grátis</option>
          </select>
        </div>

        {tipo !== "free_shipping" ? (
          <div>
            <Label htmlFor="valor">{tipo === "percentage" ? "Quanto %" : "Quanto R$"}</Label>
            <Input
              id="valor"
              value={valor}
              onChange={(e) => setValor(e.target.value)}
              placeholder={tipo === "percentage" ? "10" : "15,00"}
              inputMode="decimal"
            />
          </div>
        ) : null}

        <div>
          <Label htmlFor="onde">Vale em</Label>
          <select
            id="onde"
            value={restauranteId}
            onChange={(e) => setRestauranteId(e.target.value)}
            className="h-10 w-full rounded-lg border bg-background px-3 text-sm"
          >
            <option value="">Todos (plataforma)</option>
            {estabelecimentos.map((r) => (
              <option key={r.id} value={r.id}>
                {r.nome}
              </option>
            ))}
          </select>
        </div>

        <div>
          <Label htmlFor="minimo">Pedido mínimo</Label>
          <Input
            id="minimo"
            value={minimo}
            onChange={(e) => setMinimo(e.target.value)}
            placeholder="sem mínimo"
            inputMode="decimal"
          />
        </div>

        {tipo === "percentage" ? (
          <div>
            <Label htmlFor="teto">Desconto máximo</Label>
            <Input
              id="teto"
              value={tetoDoDesconto}
              onChange={(e) => setTeto(e.target.value)}
              placeholder="sem teto"
              inputMode="decimal"
            />
          </div>
        ) : null}

        <div>
          <Label htmlFor="ate">Válido até</Label>
          <Input
            id="ate"
            type="date"
            value={terminaEm}
            onChange={(e) => setTerminaEm(e.target.value)}
          />
        </div>

        <div>
          <Label htmlFor="usos">Usos no total</Label>
          <Input
            id="usos"
            value={usosMaximos}
            onChange={(e) => setUsosMaximos(e.target.value)}
            placeholder="sem limite"
            inputMode="numeric"
          />
        </div>

        <div>
          <Label htmlFor="porcliente">Usos por cliente</Label>
          <Input
            id="porcliente"
            value={usosPorCliente}
            onChange={(e) => setUsosPorCliente(e.target.value)}
            inputMode="numeric"
          />
        </div>
      </div>

      <div className="mt-4">
        <Label htmlFor="descricao">Descrição</Label>
        <Input
          id="descricao"
          value={descricao}
          onChange={(e) => setDescricao(e.target.value)}
          placeholder="O que o cliente vê ao aplicar"
        />
      </div>

      <label className="mt-4 flex cursor-pointer items-center gap-2 text-sm">
        <input
          type="checkbox"
          checked={soPrimeiro}
          onChange={(e) => setSoPrimeiro(e.target.checked)}
          className="size-4 accent-marca"
        />
        Só no primeiro pedido do cliente
      </label>

      {erro ? (
        <p role="alert" className="mt-4 text-sm font-medium text-destructive">
          {erro}
        </p>
      ) : null}

      <div className="mt-5 flex gap-2">
        <Button
          disabled={enviando}
          onClick={() =>
            iniciar(async () => {
              const r = await salvarCupom({
                codigo,
                descricao,
                tipo,
                valor,
                pedidoMinimo: minimo,
                descontoMaximo: tetoDoDesconto,
                terminaEm,
                usosMaximos,
                usosPorCliente,
                soPrimeiroPedido: soPrimeiro,
                restauranteId,
              })
              if (r.ok) aoFechar()
              else setErro(r.erro)
            })
          }
        >
          {enviando ? "Criando…" : "Criar cupom"}
        </Button>
        <Button variant="ghost" onClick={aoFechar}>
          Cancelar
        </Button>
      </div>
    </div>
  )
}
