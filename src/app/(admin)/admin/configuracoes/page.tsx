import type { Metadata } from "next"

import { ConfiguracoesDaPlataforma } from "@/components/admin/configuracoes-da-plataforma"
import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirAdminDaPlataforma } from "@/modules/auth/sessao"

export const metadata: Metadata = { title: "Configurações" }

/**
 * A configuracao da plataforma.
 *
 * A tabela platform_settings tem uma linha so - `id boolean` com check `id` -,
 * entao nao ha o que escolher nem o que criar aqui. Se ela nao existir, o
 * banco esta sem a semente, e dizer isso e melhor do que desenhar um formulario
 * vazio que nao salva.
 */
export default async function PaginaDeConfiguracoes() {
  await exigirAdminDaPlataforma()
  const supabase = await criarClienteDoServidor()

  const { data: configuracao } = await supabase
    .from("platform_settings")
    .select(
      "brand_name, support_email, support_phone, default_commission_bps, default_courier_fee_cents, min_order_cents, allow_new_signups, maintenance_mode",
    )
    .maybeSingle()

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">Configurações</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Vale para a plataforma inteira.
        </p>
      </div>

      {configuracao ? (
        <ConfiguracoesDaPlataforma configuracao={configuracao} />
      ) : (
        <div className="rounded-xl border border-dashed p-10 text-center">
          <p className="font-semibold">A configuração da plataforma não existe no banco</p>
          <p className="mt-1 text-sm text-muted-foreground">
            A linha única de <code>platform_settings</code> vem da semente. Rode{" "}
            <code className="rounded bg-muted px-1.5 py-0.5 text-xs">npm run db:aplicar</code>.
          </p>
        </div>
      )}
    </div>
  )
}
