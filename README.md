# Tronvix Fácil

Plataforma de pedidos e entregas para restaurantes, lanchonetes, pizzarias,
açaiterias e hamburguerias. Multi-tenant: vários estabelecimentos na mesma
instalação, cada um com seu painel, cardápio, pedidos, entregadores e
relatórios.

Quatro aplicativos, um deploy:

| Aplicativo | Rota | Para quem |
|---|---|---|
| Cliente | `/` | Quem pede |
| Restaurante | `/painel` | Quem prepara |
| Entregador | `/entregas` | Quem leva |
| Administração | `/admin` | Quem opera a plataforma |

E, no celular, um aplicativo **nativo** em Flutter: [`celular/`](celular/).
Android e iOS, mesmo banco, três frentes — cliente, balcão e entregador. Quem
entra não escolhe qual abrir: o banco é que diz quem a pessoa é.

O aplicativo tem dois modos, escolhidos por configuração: **multi**, com a
vitrine de todos os estabelecimentos, e **unique**, o aplicativo de uma loja só.
Marca e cores também vêm de configuração — o mesmo código vira o aplicativo de
outro restaurante sem tocar em nenhuma tela.

## Delivery e salão, no mesmo sistema

Três jeitos de receber o pedido, e o terceiro é o que quase nenhum concorrente
faz junto com os outros dois:

| | quem pede | como termina |
|---|---|---|
| Entrega | de casa | o entregador leva |
| Retirada | de casa | o cliente busca |
| **Mesa** | **sentado no salão** | **o garçom serve** |

No salão, cada mesa ganha um QR Code para imprimir e colar
(`/painel/mesas` → *Imprimir os QR Codes*). O cliente aponta a câmera, vê o
cardápio, pede e paga pelo próprio celular; o pedido cai na fila da cozinha com
o nome da mesa. Sem garçom anotando, sem comanda de papel.

O QR não leva o número da mesa: leva um código sorteado. Número de mesa é
adivinhável, e "pedido para a mesa 7" feito de casa às duas da manhã é uma
brincadeira que o restaurante paga.

Duas regras deixam de valer na mesa, e por um motivo: **pedido mínimo** existe
para a entrega valer a pena — quem já está sentado e pede uma água não deve
ouvir "o mínimo é vinte reais" —, e **agendamento** não faz sentido para quem
está na mesa agora. A **taxa de entrega** é zero, e disso o banco cuida sozinho
(`orders_no_fee_off_street`).

Não há entidade "comanda". Uma mesa acumula vários pedidos — entrada, bebida,
sobremesa — e a conta é a soma deles, mostrada em `/painel/mesas`.

E o sistema **não gerencia a entrega**: o entregador é do estabelecimento, que o
aprova e despacha as próprias corridas. Durante a corrida o cliente acompanha a
moto no mapa — por uma função que devolve só a posição, nunca a linha do
entregador.

## Stack

Next.js 16 (App Router) · React 19 · TypeScript · Tailwind CSS 4 ·
shadcn/ui (Base UI) · Lucide · Zod · React Hook Form · Supabase
(PostgreSQL + Auth + Storage + Realtime) · Vitest

## Começando

### 1. Dependências

```bash
npm install
```

### 2. Projeto Supabase

Crie um projeto em [supabase.com](https://supabase.com), copie `.env.example`
para `.env.local` e preencha:

```
NEXT_PUBLIC_SUPABASE_URL=https://xxxx.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=...
SUPABASE_SERVICE_ROLE_KEY=...
SUPABASE_ACCESS_TOKEN=...
```

### 3. Schema

```bash
supabase link --project-ref <ref-do-projeto>
npm run db:aplicar     # aplica supabase/migrations
npm run db:semente     # dados de demonstração + usuários de teste
```

### 4. Rodar

```bash
npm run dev
```

O projeto sobe mesmo sem Supabase configurado: as telas públicas renderizam e
avisam o que falta, em vez de quebrar com erro de chave inválida.

## Pôr um restaurante de verdade no ar

Três passos, nesta ordem. A ordem importa: a limpeza vem depois do cadastro,
para que nunca exista um momento com o banco vazio e um cliente esperando.

```sh
cp docs/abrir-restaurante.exemplo.json loja.json   # e preencha com os dados reais
npm run loja:abrir -- loja.json                    # conta do dono, loja, cardápio
npm run demo:limpar                                # mostra o que sairia
npm run demo:limpar -- --confirmar                 # tira a demonstração do ar
```

`loja:abrir` cadastra o estabelecimento **já aprovado e fechado**, com o
cardápio que vier no arquivo, e sorteia a senha do dono — mostrada uma única
vez. O dono abre a loja no painel quando o cardápio estiver conferido; loja que
nasce aberta com cardápio pela metade recebe pedido que não consegue atender.

Este é o caminho de quem já fechou negócio: alguém da plataforma abre a loja
pelo cliente, com a chave de serviço na mão.

Quem chega sozinho entra por **`/cadastrar-restaurante`** — a loja nasce
`pending` e a plataforma libera em `/admin/restaurantes`. O dono já entra no
painel antes da aprovação, para montar o cardápio enquanto espera.

A tabela `restaurants` continua fechada a INSERT: quem escreve nela é a função
`cadastrar_estabelecimento`, e é lá dentro que mora a regra de que a loja nasce
esperando, fechada e com a comissão padrão. Fosse um `with check` na política,
cada coluna nova da tabela viraria uma chance de esquecer uma proibição.

`demo:limpar` só apaga o que tem a marca da semente: estabelecimentos cujo id
começa com `a0000000-0000-4000-8000-` (cadastro real nunca cai aí, o banco gera
uuid aleatório) e a lista fixa de contas abaixo. Sem `--confirmar`, apenas
lista. E ele **para** se encontrar um pedido de loja real feito por uma conta de
demonstração — apagar a conta apagaria o cliente de uma venda de verdade.

## Usuários de teste

Criados por `npm run db:semente`. Senha de todos: `tronvix123`.

**Nenhum deles deve existir num servidor onde há um restaurante de verdade.**
A senha está escrita aqui, o que é o mesmo que publicada, e uma das contas é
administradora da plataforma inteira. É `npm run demo:limpar -- --confirmar`
que resolve.

| E-mail | Perfil |
|---|---|
| `admin@tronvixfacil.com.br` | Super administrador |
| `dono@burgerhouse.com.br` | Proprietário de restaurante |
| `atendente@burgerhouse.com.br` | Funcionário (painel reduzido) |
| `dono@pizzariadochef.com.br` | Proprietário de outro restaurante |
| `entregador@tronvixfacil.com.br` | Entregador aprovado |
| `cliente@tronvixfacil.com.br` | Cliente |

Os dois donos existem de propósito: é com eles que se confere, na prática, que
um estabelecimento não enxerga os dados do outro.

**Administrador de verdade** não sai daqui nem do cadastro público: o gatilho
`app.handle_new_user` só aceita `customer` e `courier` vindos dos metadados —
metadado de cadastro é escrito pelo cliente, e aceitar `platform_admin` ali
deixava qualquer pessoa nascer dona da plataforma. A promoção é explícita:

```sh
npm run db:administrador -- pessoa@exemplo.com.br "Nome da Pessoa"
```

## Avisos de pedido

Duas camadas, porque resolvem coisas diferentes:

| | funciona quando | latência |
|---|---|---|
| som na fila | a aba está aberta | instantâneo |
| **push** | **o navegador está fechado** | segundos |

O push é Web Push de verdade: o navegador guarda a inscrição no serviço do
fabricante (FCM, APNs, Mozilla) e um service worker mostra o aviso fora da aba.
As peças:

```
pedido chega a "recebido"
  → gatilho app.avisar_pedido (pg_net, assíncrono)
  → Edge Function avisar-pedido (roda no Supabase)
  → serviço de push do fabricante
  → service worker → notificação
```

O gatilho é assíncrono de propósito: fechar um pedido **não** pode ficar mais
lento — nem falhar — porque o aviso demorou.

Para ligar num projeto:

```sh
node -e "console.log(require('web-push').generateVAPIDKeys())"   # gere o par
# preencha NEXT_PUBLIC_VAPID_CHAVE_PUBLICA e VAPID_CHAVE_PRIVADA no .env.local
supabase secrets set VAPID_CHAVE_PUBLICA=... VAPID_CHAVE_PRIVADA=... VAPID_CONTATO=...
supabase functions deploy avisar-pedido --no-verify-jwt
SUPABASE_DB_PASSWORD='...' npm run avisos:ligar
```

Sem o último passo o gatilho existe e não faz nada — de propósito: um banco de
desenvolvimento recém-criado não deve tentar mandar push.

## Comandos

| Comando | O que faz |
|---|---|
| `npm run dev` | Servidor de desenvolvimento |
| `npm run build` | Build de produção |
| `npm run test` | Testes de unidade (Vitest) |
| `npm run db:test` | Testes das regras do banco, num Postgres local |
| `npm run db:tipos` | Regenera `src/types/banco.ts` a partir do schema |
| `npm run db:aplicar` | Aplica as migrações no Supabase |
| `npm run db:semente` | Carrega dados e usuários de demonstração |
| `npm run verificar` | lint + testes + build |

### Testar o banco sem Docker

`supabase start` exige um runtime de container. Onde não há Docker,
`npm run db:test` usa um Postgres local comum: `supabase/tests/ambiente-local.sql`
recria o mínimo do Supabase (papéis, schema `auth`, `auth.uid()`) e as mesmas
migrações rodam por cima.

```bash
brew services start postgresql@17   # ou qualquer Postgres em localhost:5432
npm run db:test
```

## Estrutura

```
src/
  app/
    (cliente)/      aplicativo de quem pede
    (restaurante)/  painel de quem prepara
    (entregador)/   aplicativo de quem leva
    (admin)/        painel da plataforma
    (auth)/         entrar, criar conta, recuperar senha
  modules/          regra de negócio, por domínio (server-only)
  components/       interface compartilhada
  lib/              Supabase, dinheiro, ambiente
  types/            tipos gerados do banco
supabase/
  migrations/       schema, RLS e gatilhos
  tests/            testes das regras do banco
  seed.sql          dados de demonstração
```

Arquitetura e decisões: [`docs/arquitetura.md`](docs/arquitetura.md).

## Três regras que sustentam o resto

**Dinheiro é inteiro de centavos.** Nunca `float`, em nenhuma camada. A conta
do restaurante fecha no fim do dia.

**Isolamento é do banco.** Toda tabela tem RLS ligada, ancorada em
`restaurant_members`. Um `where` esquecido devolve zero linhas — não os dados
do estabelecimento vizinho.

**Preço é calculado no servidor.** O carrinho envia IDs e quantidades; o
backend busca preço, adicionais, promoção e cupom no banco. O valor que o
navegador manda é descartado.
