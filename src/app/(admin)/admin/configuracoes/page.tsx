import type { Metadata } from "next"

import { ProximaEtapa } from "@/components/proxima-etapa"

export const metadata: Metadata = { title: "Configurações" }

export default function Pagina() {
  return (
    <ProximaEtapa
      titulo="Configurações"
      etapa="Etapa 7"
      descricao="Nome da marca, contato de suporte, comissão e taxa padrão."
      jaPronto={[
        "platform_settings já existe, em linha única",
      ]}
    />
  )
}
