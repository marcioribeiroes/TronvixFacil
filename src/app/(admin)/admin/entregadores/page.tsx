import type { Metadata } from "next"

import { ProximaEtapa } from "@/components/proxima-etapa"

export const metadata: Metadata = { title: "Entregadores" }

export default function Pagina() {
  return (
    <ProximaEtapa
      titulo="Entregadores"
      etapa="Etapa 5"
      descricao="Os entregadores da plataforma e os autônomos."
      jaPronto={[
        "Entregador é do estabelecimento, e é ele que aprova",
        "Não aprovado não consegue nem ficar disponível",
      ]}
    />
  )
}
