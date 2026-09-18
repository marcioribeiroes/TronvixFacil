# Publicar o Tronvix Fácil na Google Play

Tudo que o Play Console pede, na ordem em que ele pede, com o texto pronto para
copiar. O que este repositório já gera está marcado com o caminho do arquivo; o
que depende de você está marcado com **você**.

---

## 1. A conta (**você**)

<https://play.google.com/console> → criar conta de desenvolvedor.

- Tipo: **organização** (se a Tronvix tem CNPJ) ou pessoal.
- Taxa única de **US$ 25**, cartão de crédito internacional.
- A Google verifica identidade e endereço — costuma levar de 1 a 3 dias.
- Conta de organização precisa de um **número D-U-N-S** (gratuito, pela Dun &
  Bradstreet; a própria Google explica no formulário). Isso é o que mais atrasa
  quem começa hoje.

Depois disso: **Criar app** → nome `Tronvix Fácil`, idioma padrão
**português (Brasil)**, tipo **App**, **Gratuito**.

---

## 2. O arquivo que sobe

```sh
cd celular
flutter build appbundle --release \
  --dart-define=SUPABASE_URL=https://SEU-PROJETO.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=SUA-CHAVE-ANONIMA
```

Sai em `celular/build/app/outputs/bundle/release/app-release.aab`.

**O arquivo tem ~66 MB e isso não é problema.** Cerca de 53 MB são símbolos de
depuração e o mapa do R8, que a Play usa para ler relatórios de erro e **não**
envia para o celular de ninguém. O download real fica em torno de **28 MB**.

### A chave que assina — leia antes de subir

O bundle é assinado por `celular/android/app/upload.jks`, e a senha está em
`celular/android/key.properties`. Os dois estão fora do Git de propósito.

> **Perder essa chave significa nunca mais conseguir atualizar o aplicativo
> publicado.** Não existe recuperação: a Google não substitui chave de upload
> sem um processo demorado, e a de assinatura, nenhuma.
>
> Guarde hoje, em dois lugares que não sejam este computador: o arquivo
> `upload.jks` e a senha. Um gerenciador de senhas e um pendrive guardado
> resolvem.

Impressão digital desta chave, para conferir que é a mesma no futuro:

```
SHA-256: 31:EE:CE:57:9E:C3:98:EA:FF:B7:56:60:B5:2A:43:54:67:91:89:1A:9B:57:D6:69:DC:E7:9F:BB:5A:C2:F8:9A
Validade: até 2054
Titular:  CN=Tronvix Facil, OU=Tronvix, O=Tronvix, L=Goiania, ST=GO, C=BR
```

Ative o **Play App Signing** quando ele oferecer (vem ligado por padrão): a
Google passa a guardar a chave final e a sua vira só a de upload, que *pode* ser
trocada se um dia sumir.

---

## 3. As imagens

Geradas por código, a partir do mesmo desenho do ícone do aplicativo:

```sh
cd celular
flutter test tool/gerar_icones.dart    # ícone 512 e faixa 1024x500
flutter test tool/gerar_capturas.dart  # as capturas de tela
```

| Campo do Console | Arquivo |
| --- | --- |
| Ícone do app (512×512) | `celular/loja/play-icone-512.png` |
| Gráfico de destaque (1024×500) | `celular/loja/play-faixa-1024x500.png` |
| Capturas de telefone (mín. 2, máx. 8) | `celular/loja/play-captura-*.png` |

As capturas cruas vivem em `celular/loja/telas/` e saem do aparelho de verdade:

```sh
adb -s emulator-5554 exec-out screencap -p > celular/loja/telas/1-inicio.png
```

**Refaça as capturas quando a primeira loja de verdade estiver no ar.** As de
hoje mostram os restaurantes de demonstração, que não têm foto: o cardápio
aparece com quadrados cinzentos onde deveria ter comida. Funciona para publicar;
não é o que vende o aplicativo.

---

## 4. Ficha da loja (texto)

**Nome do app** (30 caracteres)

```
Tronvix Fácil
```

**Descrição breve** (80 caracteres)

```
Peça delivery ou direto da mesa pelo QR Code. O pedido cai na cozinha na hora.
```

**Descrição completa** (até 4000 caracteres)

```
O Tronvix Fácil junta as duas formas de pedir comida num aplicativo só: o
delivery que chega até você e o pedido feito na mesa do restaurante, pelo seu
próprio celular.

PEÇA DE ONDE VOCÊ ESTIVER
Escolha o restaurante, monte o pedido e acompanhe até a porta. Você vê o tempo
estimado, a taxa de entrega e o total antes de confirmar — sem surpresa no fim.

JÁ ESTÁ NO RESTAURANTE? LEIA O QR DA MESA
Aponte a câmera para o QR Code colado na mesa e o cardápio abre no seu celular.
Você pede sem esperar alguém anotar, e o pedido vai direto para a cozinha com o
número da mesa. Se preferir, digite o código impresso embaixo do QR: funciona
sem câmera.

PAGUE COMO O RESTAURANTE ACEITA
Pix na hora, cartão pelo aplicativo, ou cartão e dinheiro na entrega. Cada loja
mostra só o que ela realmente recebe. No Pix, o dinheiro vai direto para a conta
do restaurante.

ACOMPANHE O PEDIDO
Recebido, em preparo, pronto, saiu para entrega. Você vê onde o pedido está e,
durante a entrega, onde o entregador está no mapa.

DESISTIU? CANCELE
Enquanto o restaurante não começou a preparar, você cancela pelo aplicativo.

PARA QUEM TEM RESTAURANTE
O mesmo aplicativo abre o balcão: os pedidos chegam com som, entram num quadro
que vai de "chegou" a "saiu para entrega", e podem sair impressos na impressora
térmica automaticamente. O cadastro da loja é feito no site, sem mensalidade,
com seus próprios entregadores.

O Tronvix Fácil não exibe anúncios e não vende seus dados.
```

**Categoria**: Alimentos e bebidas
**Tags**: delivery, restaurante, comida, pedido
**E-mail de contato** (**você**): o endereço que vai aparecer na loja
**Site** (**você**): o endereço da web depois do deploy

---

## 5. Política de privacidade — bloqueia a publicação

O Console exige uma **URL pública**. A página já existe no site:

```
https://SEU-DOMINIO/privacidade
```

Ou seja: **a web precisa estar no ar antes de publicar na Play.** Não há como
adiar essa parte; um PDF no Drive não passa.

Antes de publicar, troque a constante `CONTATO` em
`src/app/privacidade/page.tsx` por um e-mail que alguém lê de verdade. Hoje ela
diz `privacidade@tronvix.com.br`, que é um chute meu — se esse endereço não
existe, a política promete uma resposta que não chega.

---

## 6. Exclusão de conta — também obrigatório

Aplicativo que deixa criar conta precisa deixar apagar, por dentro e por fora.
As duas coisas existem:

- No aplicativo: **Conta → Apagar minha conta**.
- No site: `https://SEU-DOMINIO/excluir-conta` — é esta URL que vai no campo
  "URL de exclusão de conta", na seção Segurança dos dados.

O que acontece está escrito na própria página: some a pessoa, fica a venda do
restaurante sem nome, telefone nem endereço.

---

## 7. Segurança dos dados (formulário)

O que responder, e por quê. Cada linha corresponde a algo que o código faz — se
o aplicativo mudar, este formulário muda junto.

| Pergunta | Resposta |
| --- | --- |
| Coleta dados? | Sim |
| Criptografa em trânsito? | Sim (HTTPS) |
| O usuário pode pedir exclusão? | Sim — e informe a URL do item 6 |
| Compartilha com terceiros? | Não (o restaurante do pedido não é "terceiro": é o serviço) |

Tipos coletados:

| Tipo | Coletado | Compartilhado | Obrigatório | Para quê |
| --- | --- | --- | --- | --- |
| Nome | Sim | Não | Sim | Funcionalidade do app |
| E-mail | Sim | Não | Sim | Funcionalidade, gerenciamento da conta |
| Telefone | Sim | Não | Não | Funcionalidade (o restaurante ligar) |
| Endereço | Sim | Não | Não | Funcionalidade (entregar) |
| Localização aproximada/precisa | Sim | Não | **Não** | Funcionalidade (mapa da entrega) |
| Histórico de compras | Sim | Não | Sim | Funcionalidade |
| Fotos | **Não** | — | — | a câmera só lê o QR; nada é enviado |

Não marque nada em: anúncios, analytics, personalização, mensagens, contatos,
arquivos, áudio, saúde, informações financeiras (não guardamos cartão — o Pix é
gerado para a chave do restaurante).

---

## 8. Classificação de conteúdo

Questionário, categoria **Todos os outros tipos de app**. Responda **não** a
tudo (violência, sexo, drogas, jogos de azar, compras dentro do app). O
resultado esperado é **Livre / PEGI 3**.

Quando perguntar se o app permite compra de bebida alcoólica: se algum
restaurante vender bebida no cardápio, responda **sim** — e a classificação
sobe para 18 anos. Hoje a semente não tem bebida alcoólica; a primeira
churrascaria que cadastrar cerveja muda isso, e a classificação precisa ser
refeita.

---

## 9. Público-alvo e outras declarações

- Faixa etária: **18 anos ou mais** (é quem compra).
- App para crianças: **não**.
- Anúncios: **não contém**.
- Acesso restrito: **não** (qualquer pessoa pode usar sem conta especial).
- COVID/finanças/saúde: **não se aplica**.

---

## 10. Testes fechados antes de publicar

Desde 2023 a Google exige, para **contas pessoais criadas depois daquela data**,
um teste fechado com **12 testadores por 14 dias seguidos** antes de liberar a
produção. Conta de organização não precisa.

Se cair nessa regra: crie a faixa **Teste fechado**, suba o mesmo `.aab`, e
convide 12 e-mails de Google (grupo do Google ou lista). Os 14 dias contam com
os testadores tendo o app instalado.

---

## 11. A ordem que funciona

1. Deploy da web (Vercel) — sem isso não há URL de privacidade.
2. Trocar o e-mail de contato na política.
3. Criar a conta no Play Console e esperar a verificação.
4. Subir o `.aab` numa faixa de **teste interno** primeiro: é instantâneo e
   mostra a ficha funcionando antes de gastar a revisão de produção.
5. Preencher ficha, segurança dos dados e classificação.
6. Enviar para revisão. A primeira costuma levar de alguns dias a duas semanas.

---

## 12. O que refazer depois da primeira loja real

- As capturas de tela, com cardápio que tem foto de comida.
- A descrição, se a loja real mudar o discurso ("a churrascaria X vende por
  aqui" é mais forte que qualquer texto genérico).
- A classificação de conteúdo, se entrar bebida alcoólica no cardápio.
