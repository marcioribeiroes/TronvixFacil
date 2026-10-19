import type { Metadata } from "next"
import Link from "next/link"

import { LogoTronvixFacil } from "@/components/marca/logo"

export const metadata: Metadata = {
  title: "Suporte",
  description: "Ajuda com pedidos, pagamento, conta e lojas no Tronvix Fácil.",
}

/**
 * Suporte.
 *
 * A App Store nao publica sem uma URL de suporte que abra para quem nunca teve
 * conta — o revisor da Apple entra aqui. Por isso, como a politica de
 * privacidade, fica fora de qualquer grupo autenticado e nao depende de banco.
 *
 * As respostas descrevem o que o sistema faz hoje. Mudou o fluxo, muda aqui.
 */

/** O mesmo da politica de privacidade: um endereco que alguem le. */
const CONTATO = "suporte@tronvix.com.br"

const PERGUNTAS: { pergunta: string; resposta: React.ReactNode }[] = [
  {
    pergunta: "Como eu pago?",
    resposta: (
      <>
        Ao receber, direto para a loja: dinheiro, cartão ou Pix na maquininha — na entrega, no
        balcão ou na mesa. Algumas lojas aceitam também o Pix pelo app, com a chave da própria
        loja; nesse caso o pedido entra na cozinha quando a loja confirma o recebimento.
      </>
    ),
  },
  {
    pergunta: "Por que aparece “não entrega no seu endereço”?",
    resposta: (
      <>
        Cada loja entrega até uma distância. Confira se o endereço principal está certo em{" "}
        <strong>Conta → Endereços</strong>. Mesmo fora da área, dá para ver o cardápio e
        retirar no balcão.
      </>
    ),
  },
  {
    pergunta: "Posso cancelar o pedido?",
    resposta: (
      <>
        Sim, pelo app, enquanto a loja ainda não aceitou. Depois disso a comida já está sendo
        feita: fale direto com a loja pelo telefone que aparece no pedido.
      </>
    ),
  },
  {
    pergunta: "Meu pedido está atrasado ou veio errado.",
    resposta: (
      <>
        Quem prepara e entrega é a loja: o telefone dela aparece na tela do pedido. Se não
        conseguir falar com ela, escreva para nós com o número do pedido.
      </>
    ),
  },
  {
    pergunta: "Como peço pela mesa?",
    resposta: (
      <>
        Leia o QR Code colado na mesa com a câmera, ou digite o código impresso embaixo dele. O
        pedido vai para a cozinha com o número da mesa, e você pode pedir mais no mesmo pedido.
      </>
    ),
  },
  {
    pergunta: "Como apago minha conta?",
    resposta: (
      <>
        No app, em <strong>Conta → Apagar minha conta</strong>, ou pela página{" "}
        <Link href="/excluir-conta" className="font-semibold text-marca hover:underline">
          Excluir conta
        </Link>
        .
      </>
    ),
  },
  {
    pergunta: "Tenho um restaurante. Como coloco no ar?",
    resposta: (
      <>
        Pelo{" "}
        <Link href="/cadastrar-restaurante" className="font-semibold text-marca hover:underline">
          cadastro de restaurante
        </Link>
        . Depois da aprovação, a loja recebe pedidos no painel do site e no app, com os próprios
        entregadores e sem mensalidade.
      </>
    ),
  },
]

export default function Suporte() {
  return (
    <div className="mx-auto w-full max-w-3xl px-6 py-12">
      <header className="mb-10">
        <Link href="/" aria-label="Início">
          <LogoTronvixFacil className="h-8 w-auto" />
        </Link>
        <h1 className="mt-8 text-3xl font-bold tracking-tight">Suporte</h1>
        <p className="mt-2 text-muted-foreground">
          Respostas rápidas para as dúvidas mais comuns. Não achou? Fale com a gente.
        </p>
      </header>

      <section className="mb-10 rounded-xl border bg-card p-5">
        <h2 className="font-bold">Fale com a gente</h2>
        <p className="mt-1 text-sm text-muted-foreground">
          Escreva para{" "}
          <a href={`mailto:${CONTATO}`} className="font-semibold text-marca hover:underline">
            {CONTATO}
          </a>
          . Se for sobre um pedido, mande o número dele e o nome da loja. Respondemos em até um dia
          útil.
        </p>
      </section>

      <section className="space-y-6">
        {PERGUNTAS.map((p) => (
          <div key={p.pergunta}>
            <h2 className="font-semibold">{p.pergunta}</h2>
            <p className="mt-1 text-sm leading-relaxed text-muted-foreground">{p.resposta}</p>
          </div>
        ))}
      </section>

      <footer className="mt-12 border-t pt-6 text-sm text-muted-foreground">
        <Link href="/privacidade" className="hover:underline">
          Política de privacidade
        </Link>
      </footer>
    </div>
  )
}
