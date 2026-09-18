import type { Metadata } from "next"

import { ProximaEtapa } from "@/components/proxima-etapa"

export const metadata: Metadata = { title: "Pedidos" }

export default function Pagina() {
  return (
    <ProximaEtapa
      titulo="Pedidos"
      etapa="Etapa 5"
      descricao="Todos os pedidos da plataforma, de todos os estabelecimentos."
      jaPronto={[
        "Máquina de estados fechada: nenhum pedido anda para trás",
        "Valores congelados no fechamento e imutáveis pela API",
      ]}
    />
  )
}
