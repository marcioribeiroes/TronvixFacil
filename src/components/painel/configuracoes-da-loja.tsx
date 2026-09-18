"use client"

import { useState, useTransition } from "react"
import { Plus, Trash2 } from "lucide-react"

import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { formatarValor } from "@/lib/dinheiro"
import {
  mudarFormaDePagamento,
  removerHorario,
  salvarConfiguracoes,
  salvarHorario,
} from "@/modules/painel/configuracoes"
import type { Enums } from "@/types/banco"

const DIAS = ["Domingo", "Segunda", "Terça", "Quarta", "Quinta", "Sexta", "Sábado"]

/**
 * As formas que o produto oferece hoje.
 *
 * Pix e crédito aparecem como "pelo site" porque exigem gateway; enquanto o
 * provedor for simulado, um pedido assim nasce em "aguardando pagamento" e
 * nunca chega ao balcão. Ligá-las é possível — e o aviso na tela diz o que
 * acontece.
 */
const FORMAS: { metodo: Enums<"payment_method">; rotulo: string; momento: Enums<"payment_timing"> }[] = [
  { metodo: "cash", rotulo: "Dinheiro", momento: "on_delivery" },
  { metodo: "debit_card", rotulo: "Cartão de débito", momento: "on_delivery" },
  { metodo: "credit_card", rotulo: "Cartão de crédito", momento: "on_delivery" },
  { metodo: "meal_voucher", rotulo: "Vale-refeição", momento: "on_delivery" },
  { metodo: "pix", rotulo: "Pix", momento: "online" },
]

export function ConfiguracoesDaLoja({
  loja,
  horarios,
  formas,
}: {
  loja: {
    name: string
    description: string | null
    phone: string | null
    delivery_fee_cents: number
    free_delivery_above_cents: number | null
    min_order_cents: number
    avg_prep_minutes: number
    avg_delivery_minutes: number
    delivery_radius_km: number
    accepts_scheduled_orders: boolean
  }
  horarios: { id: string; weekday: number; opens_at: string; closes_at: string }[]
  formas: { method: string; timing: string; is_active: boolean }[]
}) {
  const [enviando, iniciar] = useTransition()
  const [erro, setErro] = useState<string | null>(null)
  const [salvo, setSalvo] = useState(false)

  const [nome, setNome] = useState(loja.name)
  const [descricao, setDescricao] = useState(loja.description ?? "")
  const [telefone, setTelefone] = useState(loja.phone ?? "")
  const [taxa, setTaxa] = useState(formatarValor(loja.delivery_fee_cents))
  const [gratisAcima, setGratisAcima] = useState(
    loja.free_delivery_above_cents ? formatarValor(loja.free_delivery_above_cents) : "",
  )
  const [minimo, setMinimo] = useState(formatarValor(loja.min_order_cents))
  const [preparo, setPreparo] = useState(String(loja.avg_prep_minutes))
  const [entrega, setEntrega] = useState(String(loja.avg_delivery_minutes))
  const [raio, setRaio] = useState(String(loja.delivery_radius_km))
  const [agendamento, setAgendamento] = useState(loja.accepts_scheduled_orders)

  const [dia, setDia] = useState(1)
  const [abre, setAbre] = useState("11:00")
  const [fecha, setFecha] = useState("23:00")

  function ativa(metodo: string, momento: string) {
    return formas.some((f) => f.method === metodo && f.timing === momento && f.is_active)
  }

  return (
    <div className="space-y-8">
      <section className="rounded-xl border bg-card p-5">
        <h2 className="font-bold">A loja</h2>

        <div className="mt-4 grid gap-4 sm:grid-cols-2">
          <div className="sm:col-span-2">
            <Label htmlFor="nome">Nome</Label>
            <Input id="nome" value={nome} onChange={(e) => setNome(e.target.value)} />
          </div>
          <div className="sm:col-span-2">
            <Label htmlFor="descricao">Descrição</Label>
            <Input
              id="descricao"
              value={descricao}
              onChange={(e) => setDescricao(e.target.value)}
              placeholder="Hambúrgueres artesanais, porções e bebidas."
            />
          </div>
          <div>
            <Label htmlFor="telefone">Telefone</Label>
            <Input
              id="telefone"
              value={telefone}
              onChange={(e) => setTelefone(e.target.value)}
              placeholder="62 3200-0001"
            />
          </div>
          <div>
            <Label htmlFor="raio">Raio de entrega (km)</Label>
            <Input id="raio" value={raio} onChange={(e) => setRaio(e.target.value)} inputMode="decimal" />
          </div>
        </div>
      </section>

      <section className="rounded-xl border bg-card p-5">
        <h2 className="font-bold">Entrega e mínimo</h2>
        <p className="mt-1 text-sm text-muted-foreground">
          Estes números entram na conta do pedido. Quem aplica é
          <code className="mx-1 rounded bg-muted px-1">fechar_pedido</code>, no banco.
        </p>

        <div className="mt-4 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <div>
            <Label htmlFor="taxa">Taxa de entrega</Label>
            <Input id="taxa" value={taxa} onChange={(e) => setTaxa(e.target.value)} inputMode="decimal" />
          </div>
          <div>
            <Label htmlFor="gratis">Frete grátis acima de</Label>
            <Input
              id="gratis"
              value={gratisAcima}
              onChange={(e) => setGratisAcima(e.target.value)}
              placeholder="sem frete grátis"
              inputMode="decimal"
            />
          </div>
          <div>
            <Label htmlFor="minimo">Pedido mínimo</Label>
            <Input id="minimo" value={minimo} onChange={(e) => setMinimo(e.target.value)} inputMode="decimal" />
          </div>
          <div className="grid grid-cols-2 gap-2">
            <div>
              <Label htmlFor="preparo">Preparo (min)</Label>
              <Input id="preparo" value={preparo} onChange={(e) => setPreparo(e.target.value)} inputMode="numeric" />
            </div>
            <div>
              <Label htmlFor="entrega">Entrega (min)</Label>
              <Input id="entrega" value={entrega} onChange={(e) => setEntrega(e.target.value)} inputMode="numeric" />
            </div>
          </div>
        </div>

        <label className="mt-4 flex cursor-pointer items-center gap-2 text-sm">
          <input
            type="checkbox"
            checked={agendamento}
            onChange={(e) => setAgendamento(e.target.checked)}
            className="size-4 accent-marca"
          />
          Aceitar pedido agendado — a única forma de pedir com a loja fechada
        </label>

        {erro ? (
          <p role="alert" className="mt-4 text-sm font-medium text-destructive">
            {erro}
          </p>
        ) : null}

        <div className="mt-5 flex items-center gap-3">
          <Button
            disabled={enviando}
            onClick={() => {
              setErro(null)
              setSalvo(false)
              iniciar(async () => {
                const r = await salvarConfiguracoes({
                  nome,
                  descricao,
                  telefone,
                  taxaDeEntrega: taxa,
                  freteGratisAcima: gratisAcima,
                  pedidoMinimo: minimo,
                  minutosDePreparo: preparo,
                  minutosDeEntrega: entrega,
                  raioKm: raio,
                  aceitaAgendamento: agendamento,
                })
                if (r.ok) setSalvo(true)
                else setErro(r.erro)
              })
            }}
          >
            {enviando ? "Salvando…" : "Salvar"}
          </Button>
          {salvo ? <span className="text-sm text-status-pronto">Salvo.</span> : null}
        </div>
      </section>

      <section className="rounded-xl border bg-card p-5">
        <h2 className="font-bold">Horário</h2>
        <p className="mt-1 text-sm text-muted-foreground">
          A chave de abrir/fechar manda no agora; o horário é a rotina. Fechar às
          03:00 é válido — representa a madrugada.
        </p>

        <ul className="mt-4 divide-y">
          {DIAS.map((nomeDoDia, indice) => {
            const doDia = horarios.filter((h) => h.weekday === indice)
            return (
              <li key={indice} className="flex flex-wrap items-center gap-3 py-2 text-sm">
                <span className="w-24 font-medium">{nomeDoDia}</span>
                {doDia.length === 0 ? (
                  <span className="text-muted-foreground">fechado</span>
                ) : (
                  doDia.map((h) => (
                    <span
                      key={h.id}
                      className="inline-flex items-center gap-1 rounded-lg border px-2 py-1"
                    >
                      {h.opens_at.slice(0, 5)}–{h.closes_at.slice(0, 5)}
                      <button
                        type="button"
                        aria-label={`Remover turno de ${nomeDoDia}`}
                        disabled={enviando}
                        onClick={() => iniciar(async () => void (await removerHorario(h.id)))}
                        className="text-muted-foreground hover:text-destructive"
                      >
                        <Trash2 className="size-3.5" aria-hidden="true" />
                      </button>
                    </span>
                  ))
                )}
              </li>
            )
          })}
        </ul>

        <div className="mt-4 flex flex-wrap items-end gap-2">
          <div>
            <Label htmlFor="dia">Dia</Label>
            <select
              id="dia"
              value={dia}
              onChange={(e) => setDia(Number(e.target.value))}
              className="h-10 rounded-lg border bg-background px-3 text-sm"
            >
              {DIAS.map((d, i) => (
                <option key={d} value={i}>
                  {d}
                </option>
              ))}
            </select>
          </div>
          <div>
            <Label htmlFor="abre">Abre</Label>
            <Input id="abre" type="time" value={abre} onChange={(e) => setAbre(e.target.value)} className="w-32" />
          </div>
          <div>
            <Label htmlFor="fecha">Fecha</Label>
            <Input id="fecha" type="time" value={fecha} onChange={(e) => setFecha(e.target.value)} className="w-32" />
          </div>
          <Button
            variant="outline"
            disabled={enviando}
            onClick={() => {
              setErro(null)
              iniciar(async () => {
                const r = await salvarHorario({ diaDaSemana: dia, abre, fecha })
                if (!r.ok) setErro(r.erro)
              })
            }}
          >
            <Plus className="size-4" aria-hidden="true" />
            Adicionar turno
          </Button>
        </div>
      </section>

      <section className="rounded-xl border bg-card p-5">
        <h2 className="font-bold">Formas de pagamento</h2>
        <p className="mt-1 text-sm text-muted-foreground">
          O que o cliente vê no checkout. Pix e crédito pelo site dependem de
          provedor de pagamento — enquanto ele for simulado, o pedido nasce em
          &ldquo;aguardando pagamento&rdquo; e não chega à sua fila.
        </p>

        <ul className="mt-4 divide-y">
          {FORMAS.map((f) => (
            <li key={`${f.metodo}-${f.momento}`} className="flex items-center gap-3 py-2.5">
              <span className="flex-1 text-sm font-medium">{f.rotulo}</span>
              <span className="text-xs text-muted-foreground">
                {f.momento === "online" ? "pelo site" : "na entrega"}
              </span>
              <label className="flex cursor-pointer items-center gap-2 text-sm">
                <input
                  type="checkbox"
                  checked={ativa(f.metodo, f.momento)}
                  disabled={enviando}
                  className="size-4 accent-marca"
                  onChange={(e) =>
                    iniciar(async () => {
                      const r = await mudarFormaDePagamento(f.metodo, f.momento, e.target.checked)
                      if (!r.ok) setErro(r.erro)
                    })
                  }
                />
                {ativa(f.metodo, f.momento) ? "Aceita" : "Não aceita"}
              </label>
            </li>
          ))}
        </ul>
      </section>
    </div>
  )
}
