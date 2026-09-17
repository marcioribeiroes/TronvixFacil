import { AlertTriangle } from "lucide-react"

/**
 * Aviso mostrado quando o projeto ainda nao aponta para um Supabase.
 *
 * Existe para que a primeira execucao de quem clona o repositorio seja uma
 * instrucao, e nao uma tela branca com "Invalid API key" no console. O app
 * sobe, as telas publicas renderizam, e so o que depende de banco avisa o que
 * falta.
 */
export function AvisoDeConfiguracao() {
  return (
    <div className="rounded-lg border border-status-preparo/40 bg-status-preparo/10 p-4">
      <div className="flex items-start gap-3">
        <AlertTriangle className="mt-0.5 size-5 shrink-0 text-status-preparo" aria-hidden="true" />
        <div className="space-y-2 text-sm">
          <p className="font-semibold text-foreground">Banco de dados não configurado</p>
          <p className="text-muted-foreground">
            Copie <code className="rounded bg-muted px-1 py-0.5 text-xs">.env.example</code> para{" "}
            <code className="rounded bg-muted px-1 py-0.5 text-xs">.env.local</code> e preencha as
            chaves do seu projeto Supabase. Depois rode{" "}
            <code className="rounded bg-muted px-1 py-0.5 text-xs">npm run db:aplicar</code> para
            criar o schema.
          </p>
          <p className="text-muted-foreground">
            O passo a passo completo está no <code className="rounded bg-muted px-1 py-0.5 text-xs">README.md</code>.
          </p>
        </div>
      </div>
    </div>
  )
}
