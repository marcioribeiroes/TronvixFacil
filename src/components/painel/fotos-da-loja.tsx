"use client"

import { EnviarImagem } from "@/components/painel/enviar-imagem"
import { MEDIDA_DA_CAPA, MEDIDA_DA_LOGO } from "@/lib/imagem"
import { salvarImagemDaLoja } from "@/modules/painel/configuracoes"

/**
 * A cara da loja na vitrine.
 *
 * Duas fotos, com papéis diferentes: a logo aparece no quadradinho da lista e
 * ao lado do nome, em todo lugar; a capa só na página da loja, atrás do nome.
 * Por isso as medidas são diferentes — guardar as duas grandes é pagar banda
 * do cliente à toa.
 */
export function FotosDaLoja({
  restauranteId,
  logoUrl,
  capaUrl,
}: {
  restauranteId: string
  logoUrl: string | null
  capaUrl: string | null
}) {
  return (
    <section className="rounded-xl border bg-card p-4">
      <h2 className="text-sm font-bold uppercase tracking-wide text-muted-foreground">
        Fotos da loja
      </h2>
      <p className="mt-1 text-xs text-muted-foreground">
        É o que o cliente vê antes de abrir o cardápio.
      </p>

      <div className="mt-4 grid gap-6 sm:grid-cols-[auto_1fr]">
        <div>
          <p className="mb-2 text-sm font-semibold">Logo</p>
          <EnviarImagem
            restauranteId={restauranteId}
            pasta="logo"
            medida={MEDIDA_DA_LOGO}
            urlAtual={logoUrl}
            aoTrocar={(url) => salvarImagemDaLoja("logo", url)}
          />
        </div>

        <div>
          <p className="mb-2 text-sm font-semibold">Capa</p>
          <EnviarImagem
            restauranteId={restauranteId}
            pasta="capa"
            medida={MEDIDA_DA_CAPA}
            urlAtual={capaUrl}
            formato="largo"
            aoTrocar={(url) => salvarImagemDaLoja("capa", url)}
          />
        </div>
      </div>
    </section>
  )
}
