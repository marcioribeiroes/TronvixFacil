import type { Metadata } from "next"

import { Badge } from "@/components/ui/badge"
import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirAdminDaPlataforma } from "@/modules/auth/sessao"

export const metadata: Metadata = { title: "Erros" }

const ORIGEM: Record<string, string> = {
  servidor: "Servidor do site",
  navegador: "Navegador",
  app: "Aplicativo",
}

function quando(iso: string) {
  return new Date(iso).toLocaleString("pt-BR", {
    timeZone: "America/Sao_Paulo",
    dateStyle: "short",
    timeStyle: "short",
  })
}

/**
 * O que quebrou nos ultimos 7 dias, no site e no aplicativo.
 *
 * Agrupado pela mensagem: o mesmo erro com cliente em cliente aparece uma vez,
 * com a contagem — e a contagem e o que diz o que consertar primeiro. Abrir a
 * linha mostra a ultima ocorrencia inteira.
 */
export default async function PaginaDeErros() {
  await exigirAdminDaPlataforma()
  const supabase = await criarClienteDoServidor()

  const seteDias = new Date()
  seteDias.setDate(seteDias.getDate() - 7)

  const { data } = await supabase
    .from("app_errors")
    .select("id, created_at, source, message, stack, url, version, user_id, context")
    .gte("created_at", seteDias.toISOString())
    .order("created_at", { ascending: false })
    .limit(1000)

  type Erro = NonNullable<typeof data>[number]
  const grupos = new Map<string, { ultimo: Erro; vezes: number; pessoas: Set<string> }>()
  for (const e of data ?? []) {
    const chave = `${e.source}|${e.message}`
    const g = grupos.get(chave)
    if (g) {
      g.vezes++
      if (e.user_id) g.pessoas.add(e.user_id)
    } else {
      grupos.set(chave, { ultimo: e, vezes: 1, pessoas: new Set(e.user_id ? [e.user_id] : []) })
    }
  }
  const lista = [...grupos.values()].sort((a, b) => b.vezes - a.vezes)

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">Erros</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Últimos 7 dias, do site e do aplicativo, agrupados pela mensagem. Os que mais se
          repetem vêm primeiro.
        </p>
      </div>

      {lista.length === 0 ? (
        <p className="rounded-xl border border-dashed p-10 text-center text-sm text-muted-foreground">
          Nenhum erro registrado nos últimos 7 dias.
        </p>
      ) : (
        <ul className="space-y-2">
          {lista.map(({ ultimo: e, vezes, pessoas }) => (
            <li key={e.id} className="rounded-xl border bg-card">
              <details>
                <summary className="flex cursor-pointer flex-wrap items-center gap-x-3 gap-y-1 p-4 text-sm">
                  <Badge variant={vezes > 10 ? "destructive" : "secondary"}>{vezes}×</Badge>
                  <span className="min-w-0 flex-1 font-semibold">{e.message}</span>
                  <span className="text-xs text-muted-foreground">
                    {ORIGEM[e.source] ?? e.source}
                    {pessoas.size > 0 ? ` · ${pessoas.size} pessoa(s)` : ""} · último {quando(e.created_at)}
                  </span>
                </summary>
                <div className="space-y-2 border-t p-4 text-xs">
                  <p>
                    <span className="text-muted-foreground">Onde:</span> {e.url ?? "—"}
                    {e.version ? (
                      <>
                        {" "}
                        · <span className="text-muted-foreground">versão</span> {e.version}
                      </>
                    ) : null}
                  </p>
                  {e.context ? (
                    <pre className="overflow-x-auto rounded-lg bg-muted p-3">
                      {JSON.stringify(e.context, null, 2)}
                    </pre>
                  ) : null}
                  {e.stack ? (
                    <pre className="max-h-80 overflow-auto rounded-lg bg-muted p-3">{e.stack}</pre>
                  ) : null}
                </div>
              </details>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}
