import type { Metadata } from "next"

import { ProximaEtapa } from "@/components/proxima-etapa"

export const metadata: Metadata = { title: "Dashboard" }

export default function DashboardDoRestaurante() {
  return (
    <ProximaEtapa
      titulo="Dashboard do restaurante"
      etapa="Etapa 3"
      descricao="Pedidos do dia, faturamento, ticket médio, produtos mais vendidos e o Kanban de produção."
      jaPronto={[
        "Schema de pedidos, itens e histórico, com valores conferidos pelo banco",
        "Numeração de pedidos sequencial por estabelecimento",
        "Máquina de estados que bloqueia transição inválida",
        "Isolamento por RLS: este painel só enxerga os dados desta loja",
      ]}
    />
  )
}
