import type { Metadata } from "next"

import { ProximaEtapa } from "@/components/proxima-etapa"

export const metadata: Metadata = { title: "Clientes" }

export default function Pagina() {
  return (
    <ProximaEtapa
      titulo="Clientes"
      etapa="Etapa 7"
      descricao="Quem pede de você, com que frequência e quanto gasta."
      jaPronto={[
        "Cada pedido guarda o contato copiado no momento da compra",
      ]}
    />
  )
}
