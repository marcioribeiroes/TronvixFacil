import type { Metadata } from "next"
import Link from "next/link"
import { redirect } from "next/navigation"

import {
  FormularioDeEntregador,
  type EstabelecimentoParaCadastro,
} from "@/components/entregador/formulario-de-entregador"
import { FormularioDoAutonomo } from "@/components/entregador/formulario-do-autonomo"
import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { obterContexto } from "@/modules/auth/sessao"

export const metadata: Metadata = { title: "Quero entregar" }

/**
 * A porta de entrada de quem quer entregar, em dois caminhos:
 *
 *   ?tipo=restaurante   entrega para um estabelecimento, que aprova a pessoa
 *                       que conhece - sem documento
 *   ?tipo=autonomo      entrega para a plataforma, atendendo varios
 *                       estabelecimentos; manda documentos, e quem aprova e a
 *                       plataforma
 *
 * Exige conta, mas nao a cria aqui. Quem nao esta logado vai para o login, que
 * volta para esta tela; quem ainda nao tem conta acha o "Cadastre-se" ali.
 *
 * Quem ja tem cadastro vai para as corridas - menos o autonomo recusado, que
 * volta aqui para corrigir e reenviar.
 */
export default async function CadastroDeEntregador({
  searchParams,
}: PageProps<"/entregas/cadastro">) {
  const contexto = await obterContexto()
  if (!contexto) redirect("/entrar?voltar_para=%2Fentregas%2Fcadastro")

  const supabase = await criarClienteDoServidor()
  const parametros = await searchParams

  let recusa: string | null = null
  if (contexto.entregadorId) {
    const { data: eu } = await supabase
      .from("couriers")
      .select("status, restaurant_id, review_note")
      .eq("id", contexto.entregadorId)
      .single()
    if (!(eu?.status === "rejected" && eu.restaurant_id === null)) redirect("/entregas")
    recusa = eu.review_note
  }

  const tipo = recusa !== null || parametros.tipo === "autonomo" ? "autonomo" : parametros.tipo

  if (tipo === "autonomo") {
    const { data: cidades } = await supabase.rpc("cidades_para_entregador")
    return (
      <div className="mx-auto max-w-lg space-y-6">
        <div>
          <h1 className="text-xl font-bold tracking-tight">Entregador autônomo</h1>
          <p className="mt-1 text-sm text-muted-foreground">
            Você entrega para os estabelecimentos da sua cidade que aceitam entregadores da
            plataforma. A equipe do Tronvix Fácil confere os documentos e aprova o cadastro.
          </p>
        </div>
        {recusa ? (
          <p className="rounded-xl border border-destructive/40 bg-destructive/5 p-4 text-sm">
            <strong className="block text-destructive">Seu cadastro precisa de correção</strong>
            {recusa}
          </p>
        ) : null}
        <FormularioDoAutonomo usuarioId={contexto.id} cidades={cidades ?? []} />
        {recusa === null ? (
          <Link href="/entregas/cadastro" className="block text-center text-sm text-muted-foreground underline">
            Voltar
          </Link>
        ) : null}
      </div>
    )
  }

  if (tipo === "restaurante") {
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
          <h1 className="text-xl font-bold tracking-tight">Entregar para um estabelecimento</h1>
          <p className="mt-1 text-sm text-muted-foreground">
            Você entrega para um estabelecimento. É ele que aprova seu cadastro e é dele que vêm
            as corridas.
          </p>
        </div>
        <FormularioDeEntregador estabelecimentos={estabelecimentos} />
        <Link href="/entregas/cadastro" className="block text-center text-sm text-muted-foreground underline">
          Voltar
        </Link>
      </div>
    )
  }

  return (
    <div className="mx-auto max-w-lg space-y-6">
      <div>
        <h1 className="text-xl font-bold tracking-tight">Entregar pelo Tronvix Fácil</h1>
        <p className="mt-1 text-sm text-muted-foreground">Como você quer trabalhar?</p>
      </div>
      <div className="grid gap-3">
        <Link
          href="/entregas/cadastro?tipo=restaurante"
          className="rounded-xl border bg-card p-4 transition-colors hover:bg-muted"
        >
          <span className="block font-bold">Para um estabelecimento</span>
          <span className="mt-1 block text-sm text-muted-foreground">
            Você já entrega (ou vai entregar) para um restaurante específico. Ele aprova seu
            cadastro.
          </span>
        </Link>
        <Link
          href="/entregas/cadastro?tipo=autonomo"
          className="rounded-xl border bg-card p-4 transition-colors hover:bg-muted"
        >
          <span className="block font-bold">Autônomo</span>
          <span className="mt-1 block text-sm text-muted-foreground">
            Entrega para vários estabelecimentos da sua cidade. Pede CNH, documento do veículo e
            selfie; a plataforma aprova.
          </span>
        </Link>
      </div>
    </div>
  )
}
