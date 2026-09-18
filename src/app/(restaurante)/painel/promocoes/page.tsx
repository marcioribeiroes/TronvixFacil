import type { Metadata } from "next"

import { ProximaEtapa } from "@/components/proxima-etapa"

export const metadata: Metadata = { title: "Promoções" }

export default function Pagina() {
  return (
    <ProximaEtapa
      titulo="Promoções"
      etapa="Etapa 6"
      descricao="Preço promocional com janela de início e fim."
      jaPronto={[
        "A janela já vale: promoção vencida volta ao preço cheio no fechamento",
      ]}
    />
  )
}
