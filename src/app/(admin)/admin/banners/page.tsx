import type { Metadata } from "next"

import { FaixasDaVitrine } from "@/components/admin/faixas-da-vitrine"
import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirAdminDaPlataforma } from "@/modules/auth/sessao"

export const metadata: Metadata = { title: "Banners" }

export default async function PaginaDeBanners() {
  await exigirAdminDaPlataforma()
  const supabase = await criarClienteDoServidor()

  const { data: banners } = await supabase
    .from("banners")
    .select("id, title, image_url, target_url, position, starts_at, ends_at, is_active")
    .order("position")

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">Banners</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          As faixas do topo da vitrine e para onde elas levam.
        </p>
      </div>

      <FaixasDaVitrine banners={banners ?? []} />
    </div>
  )
}
