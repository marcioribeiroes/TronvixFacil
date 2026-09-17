import Link from "next/link"
import { ShieldAlert } from "lucide-react"

import { Button } from "@/components/ui/button"

/**
 * Destino de quem esta logado mas nao trabalha em nenhum estabelecimento.
 *
 * Em vez de uma tela de erro, oferece a saida: voltar ao aplicativo ou pedir
 * acesso a quem administra a loja.
 */
export default function SemAcessoAoPainel() {
  return (
    <div className="mx-auto max-w-md rounded-xl border bg-card p-8 text-center">
      <ShieldAlert className="mx-auto size-8 text-status-preparo" aria-hidden="true" />
      <h2 className="mt-4 text-lg font-bold tracking-tight">Você ainda não tem um restaurante</h2>
      <p className="mt-2 text-sm text-muted-foreground">
        Este painel é de quem administra um estabelecimento. Se você faz parte de uma equipe, peça
        ao proprietário para incluir seu e-mail em Configurações → Funcionários.
      </p>
      <Button className="mt-6" render={<Link href="/" />}>
        Voltar ao aplicativo
      </Button>
    </div>
  )
}
