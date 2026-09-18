import type { Metadata } from "next"

import { formatarReais } from "@/lib/dinheiro"
import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirGestao } from "@/modules/auth/sessao"

export const metadata: Metadata = { title: "Clientes" }

/**
 * Quem ja comprou aqui.
 *
 * Nao ha cadastro de cliente no painel, de proposito: o cliente e dono do
 * proprio cadastro, e a loja o conhece pelos pedidos. O que esta tela mostra e
 * o que a loja aprendeu vendendo - quem volta, quanto gasta, ha quanto tempo
 * sumiu.
 *
 * A RLS so deixa esta loja ver os pedidos dela; o agrupamento e feito aqui
 * porque e sobre esse recorte, e nao sobre a base inteira de clientes.
 */

type Cliente = {
  chave: string
  nome: string
  telefone: string | null
  pedidos: number
  total: number
  ultimo: string
}

function diasDesde(iso: string) {
  return Math.floor((Date.now() - new Date(iso).getTime()) / 86_400_000)
}

export default async function ClientesDoRestaurante() {
  const { vinculo } = await exigirGestao()
  const supabase = await criarClienteDoServidor()

  const { data: pedidos } = await supabase
    .from("orders")
    .select("customer_id, customer_name, customer_phone, total_cents, status, created_at, address_district")
    .eq("restaurant_id", vinculo.restauranteId)
    .not("status", "in", "(cancelled,rejected)")
    .order("created_at", { ascending: false })

  const porCliente = new Map<string, Cliente>()
  const porBairro = new Map<string, number>()

  for (const p of pedidos ?? []) {
    // Cliente sem conta (pedido anotado no balcao) nao tem id: agrupa pelo
    // telefone. Sem telefone, cada pedido e uma pessoa - preferivel a juntar
    // dois "Maria" diferentes num cliente so.
    const chave = p.customer_id ?? p.customer_phone ?? `avulso:${p.created_at}`
    const atual = porCliente.get(chave) ?? {
      chave,
      nome: p.customer_name,
      telefone: p.customer_phone,
      pedidos: 0,
      total: 0,
      ultimo: p.created_at,
    }
    atual.pedidos += 1
    atual.total += p.total_cents
    if (p.created_at > atual.ultimo) atual.ultimo = p.created_at
    porCliente.set(chave, atual)

    if (p.address_district) {
      porBairro.set(p.address_district, (porBairro.get(p.address_district) ?? 0) + 1)
    }
  }

  const clientes = [...porCliente.values()].sort((a, b) => b.total - a.total)
  const recorrentes = clientes.filter((c) => c.pedidos > 1)
  const sumidos = clientes.filter((c) => c.pedidos > 1 && diasDesde(c.ultimo) >= 30)

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">Clientes</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Quem já pediu aqui, pelos pedidos da própria loja.
        </p>
      </div>

      <dl className="grid gap-3 sm:grid-cols-3">
        <div className="rounded-xl border bg-card p-4">
          <dt className="text-xs font-semibold uppercase text-muted-foreground">Clientes</dt>
          <dd className="text-2xl font-bold">{clientes.length}</dd>
        </div>
        <div className="rounded-xl border bg-card p-4">
          <dt className="text-xs font-semibold uppercase text-muted-foreground">
            Voltaram ao menos uma vez
          </dt>
          <dd className="text-2xl font-bold">{recorrentes.length}</dd>
          <dd className="mt-0.5 text-xs text-muted-foreground">
            {clientes.length > 0
              ? `${Math.round((recorrentes.length / clientes.length) * 100)}% da base`
              : "—"}
          </dd>
        </div>
        <div className="rounded-xl border bg-card p-4">
          <dt className="text-xs font-semibold uppercase text-muted-foreground">
            Sumidos há 30 dias
          </dt>
          <dd className="text-2xl font-bold">{sumidos.length}</dd>
          <dd className="mt-0.5 text-xs text-muted-foreground">já foram fregueses</dd>
        </div>
      </dl>

      {porBairro.size > 0 ? (
        <section>
          <h2 className="text-sm font-bold uppercase tracking-wide text-muted-foreground">
            De onde vêm os pedidos
          </h2>
          <ul className="mt-2 flex flex-wrap gap-2">
            {[...porBairro.entries()]
              .sort((a, b) => b[1] - a[1])
              .slice(0, 12)
              .map(([bairro, quantos]) => (
                <li key={bairro} className="rounded-lg border bg-card px-3 py-2 text-sm">
                  <span className="font-bold">{quantos}</span>{" "}
                  <span className="text-muted-foreground">{bairro}</span>
                </li>
              ))}
          </ul>
        </section>
      ) : null}

      <section>
        <h2 className="text-sm font-bold uppercase tracking-wide text-muted-foreground">
          Quem mais gastou
        </h2>
        <ul className="mt-2 divide-y rounded-xl border bg-card">
          {clientes.slice(0, 40).map((c) => {
            const dias = diasDesde(c.ultimo)
            return (
              <li key={c.chave} className="flex flex-wrap items-center gap-x-3 gap-y-1 p-3 text-sm">
                <span className="min-w-0 flex-1">
                  <span className="block truncate font-medium">{c.nome}</span>
                  <span className="block text-xs text-muted-foreground">
                    {c.telefone ?? "sem telefone"}
                  </span>
                </span>
                <span className="shrink-0 text-muted-foreground">
                  {c.pedidos} {c.pedidos === 1 ? "pedido" : "pedidos"}
                </span>
                <span className="shrink-0 text-xs text-muted-foreground">
                  {dias === 0 ? "hoje" : dias === 1 ? "ontem" : `há ${dias} dias`}
                </span>
                <span className="shrink-0 font-bold">{formatarReais(c.total)}</span>
              </li>
            )
          })}
          {clientes.length === 0 ? (
            <li className="p-4 text-sm text-muted-foreground">
              Ninguém pediu ainda. Assim que o primeiro pedido entrar, ele aparece aqui.
            </li>
          ) : null}
        </ul>
        {clientes.length > 40 ? (
          <p className="mt-2 text-xs text-muted-foreground">
            Mostrando os 40 maiores de {clientes.length}.
          </p>
        ) : null}
      </section>
    </div>
  )
}
