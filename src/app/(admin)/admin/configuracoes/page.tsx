import type { Metadata } from "next"

import { ConfiguracoesDaPlataforma } from "@/components/admin/configuracoes-da-plataforma"
import { AssinaturaDosEntregadores } from "@/components/admin/assinatura-dos-entregadores"
import { LimitesDosEntregadores } from "@/components/admin/limites-dos-entregadores"
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

  const [{ data: configuracao }, { data: limites }] = await Promise.all([
    supabase
      .from("platform_settings")
      .select(
        "brand_name, support_email, support_phone, default_commission_bps, default_courier_fee_cents, min_order_cents, allow_new_signups, maintenance_mode, platform_courier_delay_minutes, courier_subscription_starts_on, courier_subscription_price_cents, platform_pix_key, platform_pix_holder, platform_pix_city",
      )
      .maybeSingle(),
    supabase.from("courier_vehicle_rules").select("vehicle_type, max_trip_km, max_pickup_km"),
  ])

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">Configurações</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Vale para a plataforma inteira.
        </p>
      </div>

      {configuracao ? (
        <>
          <ConfiguracoesDaPlataforma configuracao={configuracao} />
          <LimitesDosEntregadores
            espera={configuracao.platform_courier_delay_minutes}
            limites={(limites ?? []).map((l) => ({
              veiculo: l.vehicle_type,
              viagemKm: l.max_trip_km === null ? "" : String(l.max_trip_km).replace(".", ","),
              buscaKm: l.max_pickup_km === null ? "" : String(l.max_pickup_km).replace(".", ","),
            }))}
          />
          <AssinaturaDosEntregadores
            inicio={configuracao.courier_subscription_starts_on}
            precoCentavos={configuracao.courier_subscription_price_cents}
            chave={configuracao.platform_pix_key}
            titular={configuracao.platform_pix_holder}
            cidade={configuracao.platform_pix_city}
          />
        </>
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
