import type { Metadata } from "next"
import Link from "next/link"

import { ApagarPreparo } from "@/components/painel/apagar-preparo"
import { LancarPreparo } from "@/components/painel/lancar-preparo"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirVinculo } from "@/modules/auth/sessao"
import type { Tabelas } from "@/types/banco"

export const metadata: Metadata = { title: "Cozinha" }

/**
 * A cozinha: lancar o que foi preparado e achar depois.
 *
 * Os filtros vivem na URL, e nao em estado da tela: "os preparos com aquele
 * tomate" vira um link que o gerente manda para o cozinheiro, e o voltar do
 * navegador devolve a busca anterior.
 */

const DIA = /^\d{4}-\d{2}-\d{2}$/

function texto(valor: string | string[] | undefined) {
  return typeof valor === "string" ? valor.trim().slice(0, 120) : ""
}

function dia(valor: string | string[] | undefined) {
  return typeof valor === "string" && DIA.test(valor) ? valor : ""
}

/** "2026-10-29" para "29/10/2026", sem passar por Date e pelo fuso do servidor. */
function emDia(iso: string) {
  const [ano, mes, d] = iso.split("-")
  return `${d}/${mes}/${ano}`
}

function quantidade(q: number | null, unidade: string | null) {
  if (q === null) return unidade ?? ""
  const numero = q.toLocaleString("pt-BR", { maximumFractionDigits: 3 })
  return unidade ? `${numero} ${unidade}` : numero
}

type Preparo = Tabelas<"kitchen_preps">

export default async function PaginaDaCozinha({ searchParams }: PageProps<"/painel/cozinha">) {
  const { vinculo } = await exigirVinculo()
  const ehGestao = vinculo.cargo === "owner" || vinculo.cargo === "manager"
  const parametros = await searchParams
  const supabase = await criarClienteDoServidor()

  const filtros = {
    de: dia(parametros.de),
    ate: dia(parametros.ate),
    numero: /^\d{1,9}$/.test(texto(parametros.numero)) ? texto(parametros.numero) : "",
    preparo: texto(parametros.preparo),
    prato: texto(parametros.prato),
    ingrediente: texto(parametros.ingrediente),
  }
  const filtrando = Object.values(filtros).some(Boolean)

  const [{ data: loja }, { data: produtos }, { data: encontrados, error }] = await Promise.all([
    supabase.from("restaurants").select("timezone").eq("id", vinculo.restauranteId).single(),
    supabase
      .from("products")
      .select("name")
      .eq("restaurant_id", vinculo.restauranteId)
      .is("deleted_at", null)
      .order("name"),
    supabase.rpc("buscar_preparos", {
      p_restaurante: vinculo.restauranteId,
      ...(filtros.de ? { p_de: filtros.de } : {}),
      ...(filtros.ate ? { p_ate: filtros.ate } : {}),
      ...(filtros.numero ? { p_numero: Number(filtros.numero) } : {}),
      ...(filtros.preparo ? { p_preparo: filtros.preparo } : {}),
      ...(filtros.prato ? { p_prato: filtros.prato } : {}),
      ...(filtros.ingrediente ? { p_ingrediente: filtros.ingrediente } : {}),
    }),
  ])

  const preparos = (encontrados ?? []) as Preparo[]
  const ids = preparos.map((p) => p.id)

  // Os ingredientes dos preparos da tela, e o cadastro do estoque - que vira a
  // sugestao do formulario, com a unidade de cada um.
  const [{ data: ingredientes }, { data: doEstoque }] = await Promise.all([
    ids.length > 0
      ? supabase
          .from("kitchen_prep_ingredients")
          .select("prep_id, name, quantity, unit, position")
          .in("prep_id", ids)
          .order("position")
      : Promise.resolve({ data: [] as never[] }),
    supabase
      .from("ingredients")
      .select("name, unit")
      .eq("restaurant_id", vinculo.restauranteId)
      .is("deleted_at", null)
      .order("name"),
  ])

  const porPreparo = new Map<string, NonNullable<typeof ingredientes>>()
  for (const i of ingredientes ?? []) {
    porPreparo.set(i.prep_id, [...(porPreparo.get(i.prep_id) ?? []), i])
  }


  const hoje = new Date().toLocaleDateString("en-CA", {
    timeZone: loja?.timezone ?? "America/Sao_Paulo",
  })

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">Cozinha</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          O que foi preparado, quando, para qual prato e com quais ingredientes.
        </p>
      </div>

      <LancarPreparo
        hoje={hoje}
        pratos={[...new Set((produtos ?? []).map((p) => p.name))]}
        ingredientes={(doEstoque ?? []).map((i) => ({ nome: i.name, unidade: i.unit }))}
      />

      <section className="space-y-4">
        <h2 className="font-bold">Preparos lançados</h2>

        <form className="grid gap-3 rounded-xl border bg-muted/40 p-4 sm:grid-cols-3 lg:grid-cols-6">
          <label className="space-y-1 text-sm">
            <span className="block text-xs text-muted-foreground">De</span>
            <Input type="date" name="de" defaultValue={filtros.de} />
          </label>
          <label className="space-y-1 text-sm">
            <span className="block text-xs text-muted-foreground">Até</span>
            <Input type="date" name="ate" defaultValue={filtros.ate} />
          </label>
          <label className="space-y-1 text-sm">
            <span className="block text-xs text-muted-foreground">Número</span>
            <Input name="numero" inputMode="numeric" defaultValue={filtros.numero} placeholder="12" />
          </label>
          <label className="space-y-1 text-sm">
            <span className="block text-xs text-muted-foreground">Preparo</span>
            <Input name="preparo" defaultValue={filtros.preparo} placeholder="Molho" />
          </label>
          <label className="space-y-1 text-sm">
            <span className="block text-xs text-muted-foreground">Prato</span>
            <Input name="prato" defaultValue={filtros.prato} placeholder="Parmegiana" />
          </label>
          <label className="space-y-1 text-sm">
            <span className="block text-xs text-muted-foreground">Ingrediente</span>
            <Input name="ingrediente" defaultValue={filtros.ingrediente} placeholder="Tomate" />
          </label>
          <div className="flex gap-2 sm:col-span-3 lg:col-span-6">
            <Button type="submit">Procurar</Button>
            {filtrando ? (
              <Button variant="ghost" render={<Link href="/painel/cozinha" />}>
                Limpar
              </Button>
            ) : null}
          </div>
        </form>

        {error ? (
          <p role="alert" className="text-sm font-medium text-destructive">
            Não deu para carregar os preparos: {error.message}
          </p>
        ) : preparos.length === 0 ? (
          <p className="rounded-xl border border-dashed p-6 text-center text-sm text-muted-foreground">
            {filtrando
              ? "Nenhum preparo com esses filtros."
              : "Nenhum preparo lançado ainda. O primeiro entra pelo formulário acima."}
          </p>
        ) : (
          <>
            <p className="text-xs text-muted-foreground">
              {preparos.length === 200
                ? "Mostrando os 200 mais recentes. Use os filtros para achar os anteriores."
                : `${preparos.length} ${preparos.length === 1 ? "preparo" : "preparos"}`}
            </p>
            <ul className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
              {preparos.map((p) => (
                <li key={p.id} className="rounded-xl border bg-card p-4">
                  <div className="flex items-start justify-between gap-3">
                    <div className="min-w-0">
                      <p className="text-xs font-semibold text-muted-foreground">
                        nº {p.number} · {emDia(p.prep_date)}
                      </p>
                      <p className="font-bold">{p.name}</p>
                      <p className="text-sm text-muted-foreground">
                        Prato: <span className="font-medium text-foreground">{p.product_name}</span>
                      </p>
                    </div>
                    {ehGestao ? <ApagarPreparo id={p.id} numero={p.number} /> : null}
                  </div>

                  <ul className="mt-3 space-y-1 border-t pt-3 text-sm">
                    {(porPreparo.get(p.id) ?? []).map((i) => (
                      <li key={i.position} className="flex justify-between gap-3">
                        <span>{i.name}</span>
                        <span className="shrink-0 text-muted-foreground">
                          {quantidade(i.quantity, i.unit)}
                        </span>
                      </li>
                    ))}
                  </ul>

                  {p.notes ? (
                    <p className="mt-3 text-xs text-muted-foreground">{p.notes}</p>
                  ) : null}
                </li>
              ))}
            </ul>
          </>
        )}
      </section>
    </div>
  )
}
