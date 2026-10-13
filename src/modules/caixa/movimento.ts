import "server-only"

import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import {
  FORMAS_DE_PAGAMENTO,
  type FormaDePagamento,
} from "@/modules/caixa/formas-de-pagamento"

/**
 * O movimento de um dia do caixa, como `public.movimento_do_caixa` devolve.
 *
 * O dia e calculado no banco, no fuso da loja. Aqui so se le e soma — a tela
 * do caixa e o relatorio passam pelo mesmo lugar e nao tem como discordar.
 */

export type TipoDeLancamento = "opening_float" | "withdrawal"

export const ROTULO_DO_LANCAMENTO: Record<TipoDeLancamento, string> = {
  opening_float: "Fundo de caixa",
  withdrawal: "Sangria",
}

export type Lancamento = {
  id: string
  tipo: TipoDeLancamento
  valor_cents: number
  observacao: string | null
  feito_em: string
  feito_por: string | null
  cancelado_em: string | null
  cancelado_por: string | null
}

export type Recebimento = {
  pedido_id: string
  numero: number
  cliente: string
  tipo_de_entrega: string
  mesa: string | null
  forma: string
  momento: string
  valor_cents: number
  pago_em: string
}

export type AReceber = Omit<Recebimento, "momento" | "pago_em">

export type MovimentoDoCaixa = {
  /** AAAA-MM-DD, no fuso da loja. */
  dia: string
  hoje: boolean
  /** Fuso da loja, para mostrar as horas como o balcao as viu. */
  fuso: string
  dinheiro_na_gaveta_cents: number
  lancamentos: Lancamento[]
  recebimentos: Recebimento[]
  a_receber: AReceber[]
}

export type ResumoDoCaixa = {
  fundo: number
  sangrias: number
  recebido: number
  porForma: Record<FormaDePagamento, number>
  aReceber: number
}

export async function lerMovimento(
  restauranteId: string,
  dia?: string,
): Promise<MovimentoDoCaixa> {
  const supabase = await criarClienteDoServidor()
  const { data, error } = await supabase.rpc("movimento_do_caixa", {
    p_restaurante: restauranteId,
    ...(dia ? { p_dia: dia } : {}),
  })
  if (error) throw new Error(error.message)
  return data as unknown as MovimentoDoCaixa
}

/** Cancelado aparece no relatorio, riscado, mas nao entra em soma nenhuma. */
export function resumir(m: MovimentoDoCaixa): ResumoDoCaixa {
  const valendo = m.lancamentos.filter((l) => !l.cancelado_em)
  const soma = (tipo: TipoDeLancamento) =>
    valendo.filter((l) => l.tipo === tipo).reduce((s, l) => s + l.valor_cents, 0)

  const porForma = Object.fromEntries(FORMAS_DE_PAGAMENTO.map((f) => [f, 0])) as Record<
    FormaDePagamento,
    number
  >
  for (const r of m.recebimentos) {
    if (r.forma in porForma) porForma[r.forma as FormaDePagamento] += r.valor_cents
  }

  return {
    fundo: soma("opening_float"),
    sangrias: soma("withdrawal"),
    recebido: m.recebimentos.reduce((s, r) => s + r.valor_cents, 0),
    porForma,
    aReceber: m.a_receber.reduce((s, r) => s + r.valor_cents, 0),
  }
}

/**
 * A hora no fuso da loja. A pagina renderiza no servidor, que roda em UTC: sem
 * o fuso, a sangria das 14h aparecia as 17h.
 */
export function hora(iso: string, fuso: string) {
  return new Date(iso).toLocaleTimeString("pt-BR", {
    hour: "2-digit",
    minute: "2-digit",
    timeZone: fuso,
  })
}
