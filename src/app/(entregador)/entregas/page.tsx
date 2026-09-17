import type { Metadata } from "next"

import { ProximaEtapa } from "@/components/proxima-etapa"

export const metadata: Metadata = { title: "Corridas" }

export default function CorridasDoEntregador() {
  return (
    <ProximaEtapa
      titulo="Corridas disponíveis"
      etapa="Etapa 4"
      descricao="Ficar online, aceitar corrida, ver os endereços e atualizar cada etapa até a entrega."
      jaPronto={[
        "Fila de corridas visível a qualquer entregador aprovado, por RLS",
        "Máquina de estados da entrega, com desistência antes da retirada",
        "Ganhos por corrida separados da taxa cobrada do cliente",
      ]}
    />
  )
}
