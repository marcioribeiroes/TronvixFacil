import type { Metadata } from "next"
import Link from "next/link"

import { ApagarConta } from "@/components/conta/apagar-conta"
import { LogoTronvixFacil } from "@/components/marca/logo"
import { obterContexto } from "@/modules/auth/sessao"

export const metadata: Metadata = {
  title: "Excluir conta",
  description: "Apague sua conta do Tronvix Fácil e saiba o que acontece com os dados.",
}

/**
 * Excluir a conta.
 *
 * A Play Store exige duas coisas de quem deixa criar conta: um caminho dentro
 * do aplicativo e uma pagina publica, alcancavel sem instalar nada, dizendo o
 * que e apagado. Esta e a pagina — e ela nao se limita a explicar: quem esta
 * conectado apaga aqui mesmo.
 *
 * Fica fora dos grupos autenticados de proposito. Um revisor da Google abre
 * este endereco sem conta nenhuma e precisa ler a explicacao inteira.
 */
export default async function ExcluirConta() {
  const contexto = await obterContexto()

  return (
    <div className="mx-auto w-full max-w-2xl px-6 py-12">
      <Link href="/" aria-label="Início">
        <LogoTronvixFacil className="h-8 w-auto" />
      </Link>

      <h1 className="mt-8 text-3xl font-bold tracking-tight">Excluir sua conta</h1>
      <p className="mt-3 text-sm text-muted-foreground">
        Isto não tem volta. Leia o que sai e o que fica antes de confirmar.
      </p>

      <div className="mt-8 grid gap-4 sm:grid-cols-2">
        <section className="rounded-lg border border-border p-5">
          <h2 className="text-sm font-semibold tracking-tight">Apagamos</h2>
          <ul className="mt-3 space-y-1.5 text-sm text-muted-foreground">
            <li>Seu acesso, com e-mail e senha</li>
            <li>Seu nome, telefone e foto</li>
            <li>Seus endereços de entrega</li>
            <li>Seus favoritos e avaliações</li>
            <li>Seu nome e telefone nos pedidos antigos</li>
          </ul>
        </section>

        <section className="rounded-lg border border-border p-5">
          <h2 className="text-sm font-semibold tracking-tight">Continua existindo</h2>
          <ul className="mt-3 space-y-1.5 text-sm text-muted-foreground">
            <li>O registro das vendas do restaurante — valores, itens e data</li>
            <li>Sem apontar para você: sem nome, telefone, rua nem CEP</li>
          </ul>
          <p className="mt-3 text-xs text-muted-foreground">
            O restaurante tem obrigação fiscal sobre o que vendeu. Apagar a venda dele
            junto com a sua conta seria tirar o faturamento de ontem de quem não fez nada.
          </p>
        </section>
      </div>

      <div className="mt-8 space-y-3">
        <h2 className="text-lg font-semibold tracking-tight">Antes de conseguir apagar</h2>
        <ul className="space-y-1.5 text-sm text-muted-foreground">
          <li>
            Nenhum pedido pode estar em andamento — espere a entrega ou cancele.
          </li>
          <li>
            Contas de <strong>restaurante</strong> e de <strong>entregador</strong> não
            se apagam sozinhas: elas carregam pedidos, comissões e corridas de outras
            pessoas. Escreva para{" "}
            <a className="underline" href="mailto:suporte@tronvix.com.br">
              suporte@tronvix.com.br
            </a>{" "}
            e encerramos junto com você.
          </li>
        </ul>
      </div>

      <div className="mt-8">
        {contexto ? (
          <>
            <p className="mb-3 text-sm">
              Conectado como <strong>{contexto.email ?? contexto.perfil.full_name}</strong>.
            </p>
            <ApagarConta />
          </>
        ) : (
          <div className="rounded-lg border border-border p-5">
            <p className="text-sm text-muted-foreground">
              Entre com a conta que você quer apagar — é assim que temos certeza de que
              é você quem está pedindo.
            </p>
            <Link
              href="/entrar?voltar_para=%2Fexcluir-conta"
              className="mt-4 inline-block rounded-md bg-marca px-5 py-2.5 text-sm font-semibold text-white transition-colors hover:bg-marca-forte"
            >
              Entrar para apagar a conta
            </Link>
            <p className="mt-4 text-xs text-muted-foreground">
              Sem acesso ao e-mail da conta? Escreva para{" "}
              <a className="underline" href="mailto:suporte@tronvix.com.br">
                suporte@tronvix.com.br
              </a>{" "}
              — respondemos em até 15 dias.
            </p>
          </div>
        )}
      </div>

      <p className="mt-10 text-xs text-muted-foreground">
        O que guardamos e por quê está na{" "}
        <Link className="underline" href="/privacidade">
          política de privacidade
        </Link>
        .
      </p>
    </div>
  )
}
