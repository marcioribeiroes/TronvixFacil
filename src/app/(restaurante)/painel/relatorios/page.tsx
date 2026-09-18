import type { Metadata } from "next"

import { ProximaEtapa } from "@/components/proxima-etapa"

export const metadata: Metadata = { title: "Relatórios" }

export default function Pagina() {
  return (
    <ProximaEtapa
      titulo="Relatórios"
      etapa="Etapa 7"
      descricao="Vendas do dia, ticket médio e os itens que mais saem."
      jaPronto={[
        "sold_count por produto já é mantido pelo banco a cada venda",
      ]}
    />
  )
}
