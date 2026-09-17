import type { Metadata } from "next"

import { ProximaEtapa } from "@/components/proxima-etapa"

export const metadata: Metadata = { title: "Administração" }

export default function DashboardDaPlataforma() {
  return (
    <ProximaEtapa
      titulo="Dashboard da plataforma"
      etapa="Etapa 5"
      descricao="Restaurantes cadastrados, pedidos, faturamento, comissões e crescimento."
      jaPronto={[
        "Aprovação e suspensão de estabelecimento só pela plataforma, travado no banco",
        "Comissão por estabelecimento em pontos base, congelada em cada pedido",
        "Cadastro de entregador com aprovação obrigatória antes de ficar disponível",
      ]}
    />
  )
}
