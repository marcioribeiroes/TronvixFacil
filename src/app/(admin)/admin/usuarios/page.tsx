import type { Metadata } from "next"

import { ProximaEtapa } from "@/components/proxima-etapa"

export const metadata: Metadata = { title: "Usuários" }

export default function Pagina() {
  return (
    <ProximaEtapa
      titulo="Usuários"
      etapa="Etapa 5"
      descricao="Quem usa a plataforma: clientes, equipes de estabelecimento e administradores."
      jaPronto={[
        "Papel na plataforma trancado no banco: ninguém se faz administrador",
        "Promoção a administrador só por quem já é, ou pelo script de serviço",
      ]}
    />
  )
}
