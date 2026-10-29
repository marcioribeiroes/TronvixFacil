import type { Metadata } from "next"
import { redirect } from "next/navigation"

import {
  FormularioDeEntregador,
  type EstabelecimentoParaCadastro,
} from "@/components/entregador/formulario-de-entregador"
import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { obterContexto } from "@/modules/auth/sessao"

export const metadata: Metadata = { title: "Quero entregar" }

/**
 * A porta de entrada de quem quer entregar.
 *
 * Exige conta, mas nao a cria aqui. Quem nao esta logado vai para o login, que
 * volta para esta tela; quem ainda nao tem conta acha o "Cadastre-se" ali.
 *
 * Lista so os estabelecimentos aprovados — e de um deles que vem a corrida, e
 * e ele quem aprova. O autonomo da plataforma nao se cadastra por aqui, pelo
 * mesmo motivo do aplicativo: e excecao, e a plataforma resolve por fora.
 */
export default async function CadastroDeEntregador() {
  const contexto = await obterContexto()
  if (!contexto) redirect("/entrar?voltar_para=%2Fentregas%2Fcadastro")
  if (contexto.entregadorId) redirect("/entregas")

  const supabase = await criarClienteDoServidor()
  const { data } = await supabase
    .from("restaurants")
    .select("id, name, district, city, logo_url")
    .eq("status", "approved")
    .order("name")

  const estabelecimentos: EstabelecimentoParaCadastro[] = (data ?? []).map((r) => ({
    id: r.id,
    nome: r.name,
    lugar: [r.district, r.city].filter(Boolean).join(", "),
    logoUrl: r.logo_url,
  }))

  return (
    <div className="mx-auto max-w-lg space-y-6">
      <div>
        <h1 className="text-xl font-bold tracking-tight">Entregar pelo Tronvix Fácil</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Você entrega para um estabelecimento. É ele que aprova seu cadastro e é dele que vêm
          as corridas.
        </p>
      </div>

      <FormularioDeEntregador estabelecimentos={estabelecimentos} />
    </div>
  )
}
