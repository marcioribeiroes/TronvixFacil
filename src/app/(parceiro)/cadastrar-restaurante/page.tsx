import type { Metadata } from "next"
import Link from "next/link"
import { redirect } from "next/navigation"
import { CheckCircle2 } from "lucide-react"

import { FormularioDeEstabelecimento } from "@/components/parceiro/formulario-de-estabelecimento"
import { supabaseConfigurado } from "@/lib/ambiente"
import { AvisoDeConfiguracao } from "@/components/aviso-de-configuracao"
import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { obterContexto } from "@/modules/auth/sessao"

export const metadata: Metadata = {
  title: "Cadastre seu restaurante",
  description: "Coloque seu restaurante na plataforma Tronvix Fácil.",
}

/**
 * A porta de entrada de um estabelecimento novo.
 *
 * Exige conta, mas nao pede para cria-la aqui: quem nao esta logado vai para o
 * cadastro normal e volta. Um formulario unico com conta + loja teria vinte
 * campos e perderia gente no meio - e, pior, faria a pessoa que ja tem conta
 * criar uma segunda.
 */
export default async function PaginaDeCadastroDeRestaurante() {
  if (!supabaseConfigurado()) {
    return <AvisoDeConfiguracao />
  }

  const contexto = await obterContexto()

  if (!contexto) {
    redirect("/criar-conta?voltar_para=%2Fcadastrar-restaurante")
  }

  // Aceitar novos cadastros e uma chave da plataforma. Se ela esta desligada,
  // dizer isso aqui e melhor do que deixar a pessoa preencher quinze campos
  // para ouvir "nao" no final.
  const supabase = await criarClienteDoServidor()
  const { data: configuracao } = await supabase
    .from("platform_settings")
    .select("allow_new_signups, support_email, support_phone")
    .maybeSingle()

  if (configuracao && !configuracao.allow_new_signups) {
    return (
      <div className="rounded-xl border bg-card p-8 text-center">
        <h1 className="text-xl font-bold">Cadastros temporariamente fechados</h1>
        <p className="mt-2 text-sm text-muted-foreground">
          A plataforma não está aceitando novos estabelecimentos agora.
          {configuracao.support_email ? (
            <>
              {" "}
              Fale com{" "}
              <a className="font-semibold text-marca" href={`mailto:${configuracao.support_email}`}>
                {configuracao.support_email}
              </a>
              .
            </>
          ) : null}
        </p>
      </div>
    )
  }

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-bold tracking-tight sm:text-3xl">
          Coloque seu restaurante no ar
        </h1>
        <p className="mt-2 text-sm text-muted-foreground">
          Preencha o essencial. Cardápio, taxa de entrega e horário você monta depois, no seu
          painel — com calma e sem ninguém esperando.
        </p>
      </div>

      <ul className="grid gap-3 sm:grid-cols-3">
        {[
          ["Sem mensalidade", "Você paga uma comissão só sobre o que vender."],
          ["Entregador é seu", "A plataforma não gerencia a entrega. Quem leva é gente sua."],
          ["Pedido direto", "Do cliente para a sua cozinha, sem intermediário no meio."],
        ].map(([titulo, texto]) => (
          <li key={titulo} className="rounded-xl border bg-card p-4">
            <p className="flex items-center gap-2 text-sm font-bold">
              <CheckCircle2 className="size-4 text-marca" aria-hidden="true" />
              {titulo}
            </p>
            <p className="mt-1 text-xs text-muted-foreground">{texto}</p>
          </li>
        ))}
      </ul>

      <div className="rounded-xl border bg-card p-5 sm:p-6">
        <p className="mb-6 text-xs text-muted-foreground">
          Cadastrando como{" "}
          <strong className="text-foreground">
            {contexto.perfil.full_name || contexto.email}
          </strong>
          . Não é você?{" "}
          <Link href="/entrar" className="font-semibold text-marca hover:underline">
            Entrar com outra conta
          </Link>
        </p>

        <FormularioDeEstabelecimento />
      </div>
    </div>
  )
}
