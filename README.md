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
Android e iOS, mesmo banco, três frentes — cliente, balcão e entregador.
As duas plataformas são compiladas e testadas no aparelho:

```sh
./rodar.sh -d "iPhone 17"        # simulador de iOS
./rodar.sh -d emulator-5554      # emulador de Android
./rodar.sh --build apk --debug   # gera o APK
``` Quem
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

No aplicativo, o convite **"Está num restaurante?"** fica no topo da vitrine e
abre a câmera. Quando ela falha — luz
baixa, etiqueta riscada, celular velho — a mesma tela aceita o código impresso
embaixo do QR, escolhido sem `i`, `l`, `o`, `0` e `1` justamente para ser ditado
sem confusão.

## Promoções na vitrine

Ao lado de **Tudo**, um filtro **Promoções** — no aplicativo e na web. Quem
responde "esta loja tem promoção agora?" é o banco, na coluna calculada
`tem_promocao`: cruzar no celular exigiria baixar o cardápio de trinta lojas
para descobrir que duas têm.

A janela manda. Promoção que terminou ontem é preço cheio de novo, e a que
começa amanhã ainda não vale — anunciar o contrário é o cliente chegando na
tela e vendo outro valor. Produto indisponível também não conta: ninguém
consegue comprar.

As lojas com promoção aparecem marcadas na lista, mesmo sem o filtro ligado.

## Cancelar

O cliente desiste **até a loja aceitar**. Depois disso a comida está sendo
feita, e quem paga a conta do cancelamento é o restaurante — a partir daí o
cliente pede ao balcão, que decide.

Quem cancelou fica registrado, e a diferença importa:

| | o que significa | motivo |
|---|---|---|
| `cliente` | desistiu | opcional — ele não deve explicação |
| `estabelecimento` | recusou | **obrigatório** — o cliente lê |
| `plataforma` | suporte resolvendo | opcional |

O autor é decidido pelo **banco**, a partir de quem chamou. A alternativa seria
o cliente cancelar dizendo que foi o restaurante.

E o cancelamento **aparece no balcão**: uma faixa vermelha acima do quadro, por
vinte minutos, com o sino tocando. Sem isso o pedido sumiria da fila em silêncio
e a cozinha continuaria fazendo comida que ninguém ia buscar.

## Pagamento: Pix direto da loja

O cliente paga pelo celular e **o dinheiro cai direto na conta do restaurante** —
a plataforma não passa no meio, não retém nada e não cobra taxa por transação.
Não há gateway, não há contrato, funciona no dia em que a loja cadastra a chave
(Configurações → *Receber por Pix*).

A contrapartida está escrita na tela: **a confirmação é manual.** O pedido fica
na coluna *Chegou* marcado como "aguardando Pix", e alguém do balcão confirma
quando o dinheiro entra. Enquanto não confirmar, a cozinha não começa — é a
proteção contra o pedido que ninguém pagou.

O "copia e cola" é montado **pelo banco de dados**, dentro de `fechar_pedido`,
com a chave da loja e o total que a própria função calculou. Nem o aplicativo
nem o navegador têm como trocar a chave de quem recebe. É a mesma regra que
sustenta o projeto — *o preço não vem do aplicativo* — aplicada ao dinheiro que
vai entrar numa conta.

Sem chave cadastrada, a loja simplesmente **não oferece** Pix. Antes disso,
escolher "Pix pelo site" criava um pedido em `awaiting_payment` que nunca
chegava à cozinha: o cliente achava que pediu, e o restaurante nunca soube.

O formato é o EMV® QRCPS do Banco Central, com CRC16/CCITT-FALSE. A conta do
CRC é conferida contra o valor de checagem publicado do algoritmo (`29B1` para
`123456789`), e a versão SQL é comparada byte a byte com a de TypeScript.

## Fotos

Um balde público no Storage (`imagens`), com a pasta nomeada pelo id do
estabelecimento:

```
imagens/<restaurante>/logo-<momento>.jpg
imagens/<restaurante>/capa-<momento>.jpg
imagens/<restaurante>/produtos/foto-<momento>.jpg
```

Público porque foto de cardápio **é** pública — ela aparece para quem nem tem
conta. O que não é público é a escrita: a política exige que quem envia gerencie
o estabelecimento **da pasta**. Sem isso, qualquer pessoa autenticada trocaria a
logo de qualquer loja.

O arquivo vai do navegador direto para o balde, com a sessão da pessoa — não
passa pelo servidor do Next, que dobraria a banda e poria um limite de corpo de
requisição no caminho de uma foto de celular. Antes de subir, a imagem é
reduzida no próprio navegador (logo 512px, produto 1200px, capa 1600px).

O nome carrega o momento de propósito: sobrescrever o mesmo caminho deixa a foto
velha em cache de CDN e de navegador, e o dono trocaria a logo sem ver diferença.

## O quadro de pedidos

`/painel/pedidos` é um Kanban, na ordem do trabalho:

**Chegou** → **Aceito** → **Em preparo** → **Pronto** → **Saiu**

Cada cartão diz quem pediu, para onde vai (endereço e bairro, mesa, ou balcão),
o que tem dentro, como se paga, e há quantos minutos está esperando. Um pedido
anda uma coluna por vez, e a coluna em que ele está diz o que falta fazer com
ele.

As colunas rolam na horizontal em vez de encolher: cinco colunas espremidas num
monitor de balcão viram cinco tiras ilegíveis.

## Comanda na impressora térmica

Quando o pedido entra em **Chegou**, a comanda pode sair sozinha. O botão fica
no topo da tela de Pedidos: *Imprimir sozinho*. A escolha fica guardada, e cada
cartão tem um botão de reimprimir — comanda cai atrás do balcão, papel acaba no
meio, o garçom leva a errada.

O caminho é o **driver do sistema**, não ESC/POS pela USB. Falar ESC/POS
funcionaria sem diálogo, mas exigiria conhecer o modelo de cada cliente —
Epson, Elgin e Bematech respondem a comandos diferentes, com peculiaridades de
corte e de gaveta. Pelo driver, funciona com qualquer impressora que o
computador já imprime.

A comanda é uma página própria (`/painel/comanda/<id>`), impressa de um iframe.
Imprimir a própria tela exigiria esconder o quadro inteiro no CSS e torcer para
não ter esquecido nada.

Medidas: **72mm** de largura (o papel de 80mm imprime 72; os 8mm restantes são
a margem do mecanismo), fonte monoespaçada, **sem cinza** — impressora térmica
queima o papel em vez de usar tinta, e cinza claro simplesmente não aparece.

### Para sair sem o diálogo de impressão

O navegador sempre mostra a janela de impressão, e isso não se contorna por
código. O que resolve é abrir o Chrome do balcão com a impressora térmica como
padrão e a opção de impressão silenciosa:

```
chrome.exe --kiosk-printing
```

No atalho da área de trabalho: botão direito → Propriedades → acrescente
` --kiosk-printing` no fim do campo *Destino*. A partir daí a comanda sai
direto, sem ninguém tocar em nada.

## Aberto agora

Duas coisas fecham a loja, e qualquer uma basta:

| | o que é | quem mexe |
|---|---|---|
| `is_open` | a chave da mão | o balcão, quando acaba o gás |
| `restaurant_hours` | a rotina | cadastrada uma vez, reabre sozinha |

O banco responde a pergunta pronta, em duas colunas calculadas: **`aberto_agora`**
("vende agora?", que é o que a vitrine pergunta) e **`no_horario`** (só o
relógio, que é o que o painel precisa para dizer *por que* não vende). Coluna
calculada não vem no `select *` — tem de ser pedida pelo nome.

O fuso é de cada loja (`restaurants.timezone`, padrão `America/Sao_Paulo`). O
Postgres do Supabase roda em UTC, e "abre às 18h" em Goiânia comparado direto
abriria a loja três horas cedo.

Faixa que atravessa a meia-noite conta: 18:00–02:00 vale até as duas da manhã do
dia seguinte, que é quando a pizzaria mais vende.

Loja **sem horário cadastrado** vale só pela chave. Fechar quem nunca preencheu
a tela seria tirar do ar lojas que estão vendendo hoje.

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

O som é um sino de recepção sintetizado na hora — parciais inarmônicas, ataque
instantâneo, queda exponencial. Não é arquivo baixado: som de terceiro tem
licença, e licença esquecida num produto revendido a restaurantes aparece
tarde. Dois bipes de oscilador se perdiam no barulho da cozinha e soavam como
notificação de celular, que o cérebro já aprendeu a ignorar.

O sino toca quando um pedido **novo** chega — identificado pelo id, não pela
contagem. Contando, aceitar um e receber outro no mesmo instante deixava o
número igual e o sino calado; e confirmar um Pix fazia a contagem subir e o
sino tocar para uma ação da própria loja. Enquanto alguém não atende, ele
repete a cada 45 segundos, e para sozinho quando a fila esvazia.

A escolha de ligar o som fica guardada. O navegador exige uma interação antes
de deixar tocar e isso não tem como contornar — o que dá para evitar é a pessoa
procurar o botão a cada carregamento.

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
