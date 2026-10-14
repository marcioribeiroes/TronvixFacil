import type { Metadata } from "next"

import { EnderecosDoCliente } from "@/components/cliente/enderecos-do-cliente"
import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirUsuario } from "@/modules/auth/sessao"

export const metadata: Metadata = { title: "Endereços" }

export default async function PaginaDeEnderecos({
  searchParams,
}: PageProps<"/conta/enderecos">) {
  const contexto = await exigirUsuario("/conta/enderecos")
  const parametros = await searchParams

  // So destino interno: um ?voltar_para=https://outro-site viraria
  // redirecionamento aberto com a cara da plataforma.
  const pedido = typeof parametros.voltar_para === "string" ? parametros.voltar_para : null
  const voltarPara = pedido && pedido.startsWith("/") && !pedido.startsWith("//") ? pedido : null

  const supabase = await criarClienteDoServidor()
  const { data: enderecos } = await supabase
    .from("addresses")
    .select("id, label, street, number, complement, district, city, state, is_default, latitude")
    .eq("user_id", contexto.id)
    .is("deleted_at", null)
    .order("is_default", { ascending: false })
    .order("created_at")

  return (
    <div className="mx-auto max-w-2xl space-y-6 py-2">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">Endereços</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          O principal aparece no topo do site e decide quais lojas entregam e por quanto.
        </p>
      </div>
      <EnderecosDoCliente
        voltarPara={voltarPara}
        enderecos={(enderecos ?? []).map((e) => ({
          id: e.id,
          rotulo: e.label,
          resumo: `${e.street}, ${e.number}${e.complement ? ` — ${e.complement}` : ""}, ${e.district}, ${e.city}-${e.state}`,
          padrao: e.is_default,
          semLocalizacao: e.latitude === null,
        }))}
      />
    </div>
  )
}
