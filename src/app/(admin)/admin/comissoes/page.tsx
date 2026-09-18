import type { Metadata } from "next"

import { ProximaEtapa } from "@/components/proxima-etapa"

export const metadata: Metadata = { title: "Comissões" }

export default function Pagina() {
  return (
    <ProximaEtapa
      titulo="Comissões"
      etapa="Etapa 6"
      descricao="A comissão padrão da plataforma e as negociadas por estabelecimento."
      jaPronto={[
        "Comissão por estabelecimento já editável em Restaurantes",
        "Estabelecimento não baixa a própria comissão — travado no banco",
      ]}
    />
  )
}
