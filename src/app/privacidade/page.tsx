import type { Metadata } from "next"
import Link from "next/link"

import { LogoTronvixFacil } from "@/components/marca/logo"

export const metadata: Metadata = {
  title: "Política de privacidade",
  description:
    "O que o Tronvix Fácil coleta, por quê, com quem compartilha e como apagar.",
}

/**
 * Política de privacidade.
 *
 * Existe por duas razões, nessa ordem: a LGPD, e a Play Store — que não
 * publica aplicativo sem uma URL pública de política. Por isso esta página
 * fica fora de qualquer grupo autenticado e não depende de banco: precisa
 * abrir para um revisor da Google que nunca teve conta aqui.
 *
 * **Regra para quem for editar:** cada linha aqui descreve algo que o código
 * realmente faz. Se um dia o aplicativo passar a mandar dado para um lugar
 * novo — analytics, anúncio, provedor de pagamento — a linha entra aqui no
 * mesmo dia, e o formulário de Segurança dos Dados da Play muda junto. Uma
 * política que promete mais do que o código cumpre é pior do que não ter.
 */

/**
 * Para onde escrever. Precisa ser um endereço que alguém lê: a LGPD dá ao
 * titular o direito de pedir os dados e o apagamento, e a Play confere se a
 * política tem contato.
 */
const CONTATO = "suporte@tronvix.com.br"

/** Última revisão do texto. Muda quando o que está escrito aqui muda. */
const REVISADA_EM = "18 de setembro de 2026"

export default function Privacidade() {
  return (
    <div className="mx-auto w-full max-w-3xl px-6 py-12">
      <header className="mb-10">
        <Link href="/" aria-label="Início">
          <LogoTronvixFacil className="h-8 w-auto" />
        </Link>
        <h1 className="mt-8 text-3xl font-bold tracking-tight">
          Política de privacidade
        </h1>
        <p className="mt-2 text-sm text-muted-foreground">
          Última revisão em {REVISADA_EM}.
        </p>
      </header>

      <div className="space-y-8 text-sm leading-relaxed text-foreground/90">
        <Secao titulo="Em uma frase">
          <p>
            O Tronvix Fácil guarda o necessário para o restaurante receber o seu
            pedido e entregá-lo: como você se chama, como falar com você, para
            onde vai a comida e o que você pediu. Não vendemos esses dados, não
            exibimos anúncios e não usamos o que você pede para perfilar você
            fora do aplicativo.
          </p>
        </Secao>

        <Secao titulo="Quem é responsável pelos dados">
          <p>
            O Tronvix Fácil é a plataforma. Cada restaurante cadastrado é quem
            recebe e prepara o seu pedido, e vê os dados daquele pedido — nome,
            telefone, endereço de entrega e itens. A plataforma trata os dados
            para operar o serviço; o restaurante os trata para cumprir o que
            você comprou.
          </p>
        </Secao>

        <Secao titulo="O que coletamos, e por quê">
          <ul className="space-y-3">
            <Item titulo="Conta">
              Nome, e-mail e telefone. É o que identifica você para entrar e o
              que o restaurante usa para falar com você se algo do pedido
              precisar de confirmação.
            </Item>
            <Item titulo="Endereço de entrega">
              CEP, rua, número, bairro, cidade e complemento. Sem isso não há
              entrega. Quando você digita o CEP, ele é consultado no ViaCEP ou
              na BrasilAPI só para preencher a rua e o bairro.
            </Item>
            <Item titulo="Localização do aparelho">
              Só quando você toca para usá-la, e só enquanto o aplicativo está
              aberto: para centralizar o mapa e para o entregador acompanhar o
              trajeto. Não guardamos histórico de onde você esteve, e o
              aplicativo funciona sem essa permissão — basta digitar o endereço.
            </Item>
            <Item titulo="Câmera">
              Só para ler o QR Code da mesa. A leitura acontece dentro do seu
              aparelho; nenhuma imagem é enviada nem gravada. O mesmo pedido
              pode ser feito digitando o código da mesa, sem câmera.
            </Item>
            <Item titulo="Pedidos e pagamentos">
              Itens, valores, horário, forma de pagamento e o que você escreveu
              como observação. Ficam no histórico porque são a prova da compra —
              sua e do restaurante — e porque há obrigação fiscal sobre a venda.
              Quando o pagamento é por Pix, o código é gerado para a chave do
              próprio restaurante: o dinheiro vai direto para ele, e nós não
              recebemos nem guardamos dado bancário ou número de cartão.
            </Item>
            <Item titulo="Fotos">
              Só as que o restaurante envia — da loja e dos produtos. Elas são
              públicas por natureza: aparecem no cardápio para qualquer pessoa.
            </Item>
          </ul>
        </Secao>

        <Secao titulo="O que não coletamos">
          <p>
            Não há SDK de publicidade, nem de analytics de terceiro, nem
            rastreamento entre aplicativos. Não pedimos sua agenda de contatos,
            suas fotos, seus arquivos nem seu microfone. Não guardamos número de
            cartão.
          </p>
        </Secao>

        <Secao titulo="Com quem compartilhamos">
          <ul className="space-y-3">
            <Item titulo="O restaurante do pedido">
              Vê o pedido e o que é preciso para entregá-lo. Um restaurante
              nunca vê o pedido que você fez em outro.
            </Item>
            <Item titulo="O entregador daquela entrega">
              Vê o endereço e o telefone enquanto a entrega está em andamento.
            </Item>
            <Item titulo="Supabase">
              Banco de dados e autenticação. É onde os dados ficam guardados.
            </Item>
            <Item titulo="Vercel">
              Hospeda o site e o painel.
            </Item>
            <Item titulo="ViaCEP, BrasilAPI e OpenStreetMap">
              Recebem, respectivamente, o CEP que você digita e a região do mapa
              que está na tela. Não recebem seu nome nem seu pedido.
            </Item>
          </ul>
          <p>
            Além disso, só entregamos dados a autoridade pública quando houver
            determinação legal. Não vendemos dado a ninguém.
          </p>
        </Secao>

        <Secao titulo="Por quanto tempo guardamos">
          <p>
            A conta e seus dados ficam enquanto ela existir. O histórico de
            pedidos é mantido por cinco anos, prazo do Código de Defesa do
            Consumidor para discussão de compra. Apagada a conta, o pedido
            antigo permanece apenas como registro da venda do restaurante — sem
            o seu nome, telefone, rua, CEP ou coordenadas.
          </p>
        </Secao>

        <Secao titulo="Seus direitos">
          <p>
            A LGPD (Lei 13.709/2018) garante a você confirmar que tratamos seus
            dados, acessá-los, corrigi-los, pedir cópia, revogar consentimento e
            pedir o apagamento. Nome, telefone e endereços você altera na
            própria conta, dentro do aplicativo. Para os demais pedidos,
            escreva para{" "}
            <a className="font-medium underline" href={`mailto:${CONTATO}`}>
              {CONTATO}
            </a>{" "}
            — respondemos em até 15 dias.
          </p>
          <p>
            Para apagar a conta, use{" "}
            <Link className="font-medium underline" href="/excluir-conta">
              a página de exclusão de conta
            </Link>{" "}
            — dá para fazer sozinho, na hora, e a mesma opção está dentro do
            aplicativo, em Sua conta. A página diz o que sai e o que fica.
          </p>
        </Secao>

        <Secao titulo="Segurança">
          <p>
            Todo tráfego é cifrado (HTTPS). O acesso ao banco é controlado
            linha a linha: as regras do próprio banco decidem quem pode ler cada
            pedido, e é por isso que um restaurante não alcança o pedido de
            outro mesmo que tente. Senhas não são guardadas em texto.
          </p>
        </Secao>

        <Secao titulo="Crianças">
          <p>
            O serviço é para maiores de 18 anos, que é quem pode comprar. Não
            coletamos dado de criança conscientemente; se isso acontecer,
            apagamos ao sermos avisados.
          </p>
        </Secao>

        <Secao titulo="Mudanças nesta política">
          <p>
            Quando o texto mudar, a data no topo muda. Se a mudança alterar o
            que fazemos com o seu dado, avisamos dentro do aplicativo antes de
            passar a valer.
          </p>
        </Secao>

        <Secao titulo="Contato">
          <p>
            <a className="font-medium underline" href={`mailto:${CONTATO}`}>
              {CONTATO}
            </a>
          </p>
        </Secao>
      </div>
    </div>
  )
}

function Secao({ titulo, children }: { titulo: string; children: React.ReactNode }) {
  return (
    <section className="space-y-3">
      <h2 className="text-lg font-semibold tracking-tight">{titulo}</h2>
      {children}
    </section>
  )
}

function Item({ titulo, children }: { titulo: string; children: React.ReactNode }) {
  return (
    <li className="border-l-2 border-border pl-4">
      <strong className="font-semibold">{titulo}.</strong> {children}
    </li>
  )
}
