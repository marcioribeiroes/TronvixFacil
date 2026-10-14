import "server-only"

import { cache } from "react"

import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { obterContexto } from "@/modules/auth/sessao"

/**
 * O endereco que vale agora: o principal do cliente.
 *
 * E o mesmo que o aplicativo usa como padrao, para o site e o celular
 * concordarem sobre "onde estou". O topo do site mostra; a vitrine usa para
 * dizer quem entrega e por quanto. Trocar de endereco e trocar o principal.
 */
export const enderecoAtual = cache(async () => {
  const contexto = await obterContexto()
  if (!contexto) return null

  const supabase = await criarClienteDoServidor()
  const { data } = await supabase
    .from("addresses")
    .select("id, label, street, number, district")
    .eq("user_id", contexto.id)
    .is("deleted_at", null)
    .order("is_default", { ascending: false })
    .order("created_at")
    .limit(1)
    .maybeSingle()

  if (!data) return null
  return {
    id: data.id,
    rotulo: data.label,
    resumo: `${data.street}, ${data.number}`,
    bairro: data.district,
  }
})
