# Aplicativo de celular — Flutter

O Tronvix Fácil no celular. **Nativo**, compilado para Android e iOS. Não é a
web dentro de uma caixa: é outro aplicativo, sobre o mesmo banco.

Um projeto, três frentes. Quem entra não escolhe — o banco é que diz quem a
pessoa é:

| Se no banco a pessoa… | abre em |
|---|---|
| tem vínculo ativo em `restaurant_members` | **balcão** — a fila de pedidos |
| tem cadastro em `couriers` | **entregas** — a fila de corridas |
| qualquer outra pessoa autenticada | **cliente** — a vitrine |

A ordem é essa de propósito: um dono de restaurante que também pede comida abre
no balcão, porque é lá que ele perde dinheiro se demorar a ver um pedido. Quem
tem mais de um papel troca pela conta.

## Modos

| Modo | O que o cliente vê | Para quem |
|---|---|---|
| `multi` (padrão) | vitrine com todos os estabelecimentos do servidor | praça de alimentação, marketplace |
| `unique` | o cardápio de **uma** loja, sem vitrine | o restaurante que quer o próprio aplicativo |

O modo, o estabelecimento e as cores entram por configuração — nenhuma tela
muda:

```
CELULAR_MODO=unique
CELULAR_ESTABELECIMENTO=burger-house
CELULAR_COR_DA_MARCA=0xFF1D4ED8
CELULAR_COR_DA_MARCA_ESCURA=0xFF1E3A8A
CELULAR_COR_DE_REALCE=0xFFEFF6FF
NEXT_PUBLIC_NOME_DA_MARCA=Burger House
```

As cores são `int.fromEnvironment`, de propósito: continuam constantes de
compilação, então as centenas de `const TextStyle(color: Cores.marca)` do
aplicativo seguem válidas. Fosse leitura em tempo de execução, trocar a marca
custaria um refactor inteiro.

A tela de entrar leva esse tratamento adiante: faixa escura com gradiente em
camadas, malha de pontos e os dois riscos diagonais — o mesmo gesto do login do
TronvixERP, desenhado em `comum/fundo_da_marca.dart`. Tudo derivado de
`Cores.marca`, então a faixa sai azul no aplicativo de um cliente cuja marca é
azul. Copiar o vermelho do ERP ali teria desfeito a configuração inteira.

`integration_test/marca_test.dart` verifica isso num aparelho: sobe o mesmo
código com outra marca e confere que não há vitrine, que a aba virou "Cardápio"
e que a cor é a que entrou pela linha de comando.

## Quem entrega

O sistema **não gerencia a entrega**. O entregador é do estabelecimento: se
cadastra escolhendo para quem quer levar, e é esse estabelecimento que aprova —
não a plataforma. A corrida só aparece para a equipe dele.

Quem quiser operar como marketplace liga a chave *Aceitar entregador de fora*,
na tela de Entregadores do balcão. Ela nasce desligada.

## O ícone

```sh
flutter test tool/gerar_icones.dart
flutter test tool/gerar_icones.dart --dart-define=COR_DA_MARCA=0xFF1D4ED8
```

Gera os 15 tamanhos do iOS e as 5 densidades do Android a partir de um desenho
só, em `tool/gerar_icones.dart`. Roda como teste porque é o jeito de ter um
`Canvas` de verdade sem dependência nova — e a cor sai da mesma configuração
que veste o resto do aplicativo.

**Por que o ícone não copia o painel da marca.** O painel é largo: nome escrito
por extenso, riscos de um pixel, malha de pontos. Num ladrilho de 60pt a palavra
vira borrão, o risco some e a malha vira ruído. O ícone leva os ingredientes —
carvão em gradiente, um risco vermelho, o alfinete com a cúpula — numa
composição que aguenta o tamanho em que vive.

## Rodar

```sh
./rodar.sh                    # escolhe o dispositivo conectado
./rodar.sh -d "iPhone 17"     # simulador de iOS
./rodar.sh -d emulator-5554   # emulador de Android
```

`rodar.sh` lê `../.env.local` — o mesmo arquivo da web — e converte as chaves em
`--dart-define`. Não há `.env` num aplicativo instalado: o que ele sabe do mundo
entra na compilação.

Sem `.env.local`, o aplicativo sobe e abre numa tela dizendo o que falta, em vez
de quebrar com "Invalid API key" no meio da vitrine.

## Verificar

```sh
flutter analyze
flutter test                                   # unidade, sem rede
./testar-no-aparelho.sh -d "iPhone 17"         # ponta a ponta, contra o Supabase
./passear.sh -d "iPhone 17"                    # passeia pelas telas e fotografa
```

Os dois scripts de aparelho **reinstalam o aplicativo ao terminar**, passando ou
falhando. Sem isso o atalho sumia da tela inicial a cada rodada, porque
`flutter drive` e `flutter test integration_test` instalam uma versão
instrumentada, rodam e desinstalam — parece defeito do simulador e é só o ciclo
do teste.

Quem faz isso é `instalar.sh`, chamado por um `trap`:

```sh
./instalar.sh -d "iPhone 17"    # também serve sozinho, quando precisar
```

Ele **recompila** em vez de reinstalar o que sobrou em `build/`: o que está lá
depois de um passeio é o aplicativo de teste, cujo ponto de entrada é o arquivo
de teste. Aberto pelo atalho, ele rodaria o teste em vez do aplicativo.

`flutter test` cobre o que o aplicativo tem de acertar sozinho: dinheiro em
centavos, janela de promoção, frete grátis, e a **fidelidade** do espelho da
máquina de estados. Não testa as regras em si — essas vivem no banco e são
verificadas por `npm run db:test`, na raiz do projeto.

`testar-no-aparelho.sh` é outro bicho: sobe o aplicativo num aparelho e fecha um
pedido de verdade, conferindo que o **banco** devolveu os valores certos. É o
único teste que prova, no caminho real, a frase que sustenta o projeto — o preço
não vem do aplicativo.

`passear.sh` navega tocando nos widgets e grava as telas em `capturas/`. Serve
para conferir a navegação e para ilustrar manual sem precisar instalar nada.

## O sino

Um sino de recepção — o sininho de balcão — ao abrir o aplicativo e a cada
passo do pedido: aceito, em preparo, pronto, saiu para entrega, entregue. O
passo final leva o sino inteiro; os do meio, uma versão curta, porque um toque
longo repetido cinco vezes cansa antes de a comida chegar.

O som é **sintetizado**, não baixado:

```sh
flutter test tool/gerar_sons.dart
```

`tool/gerar_sons.dart` monta a onda do zero — parciais inarmônicas nas razões
de um corpo metálico circular (2,76 · 5,40 · 8,93), decaimento mais rápido a
cada parcial, um estalo de martelo de 6 ms na frente e um leve batimento entre
parciais quase iguais, que é o tremor sem o qual um sino sintetizado soa morto.

O timbre é **paramétrico** — fundamental, duração e número de batidas ficam numa
lista no topo do arquivo. Para ouvir as variações lado a lado antes de decidir:

```sh
AMOSTRAS=/tmp/sons flutter test tool/gerar_sons.dart
afplay /tmp/sons/sino-grave.wav
TIMBRE=grave flutter test tool/gerar_sons.dart   # adota outro
```

A razão de sintetizar em vez de baixar não é técnica: efeito sonoro publicado
na internet tem dono, e embutir um num produto que se vende é problema de
licença que aparece tarde. Um sino é física, e física não tem licença. Trocar
por um arquivo próprio é substituir `assets/sons/sino.wav`.

Nada disso derruba a tela: aparelho no silencioso, áudio ocupado, permissão
negada — tudo vira silêncio, não exceção.

## Rastreio do entregador

Durante a corrida, o entregador publica a posição e o cliente vê a moto andando
no mapa da tela de acompanhar. Fora da corrida, ninguém publica nada — emitir a
posição de quem está livre é vigiar, não rastrear um pedido.

A parte difícil disso não é técnica, é decidir **quem pode ver onde uma pessoa
está**. A escolha:

- **Não** existe política de RLS nova em `couriers`. Abrir a tabela ao cliente,
  mesmo durante a entrega, entregaria a linha inteira — documento, reputação,
  cadastro — para quem precisa de dois números. E, com política, o Realtime
  passaria a transmitir essa linha inteira.
- No lugar, `public.onde_esta_o_entregador(pedido)` devolve três campos:
  latitude, longitude e quando a medida foi feita.
- Só enquanto a corrida acontece. Entregue ou cancelada, a função não responde
  mais.

O preço é que o cliente **consulta** a cada oito segundos em vez de receber por
Realtime. Para uma bolinha andando no mapa isso basta, e nenhum dado a mais
viaja no caminho.

A idade da medida anda junto com ela: posição de mais de dois minutos aparece
apagada, com "o sinal dele pode ter caído". Alfinete parado sem explicação faz o
cliente concluir que o entregador sumiu.

`integration_test/rastreio_test.dart` simula os dois aparelhos numa máquina só:
o aplicativo fica logado como cliente enquanto um segundo cliente Supabase,
autenticado como entregador, publica posições ao longo do caminho.

## Endereço por CEP

Digitou os oito dígitos, a rua, o bairro, a cidade e a UF se preenchem sozinhos
e o cursor vai para o número — o único campo que a busca não tem como saber.

Duas fontes, na ordem: **ViaCEP** e, se ela não responder, **BrasilAPI**. Não é
exagero: o cadastro de endereço acontece com o cliente com fome, e ficar refém
de um serviço fora do ar é perder o pedido.

Nada disso trava o formulário. CEP inexistente, serviço fora, celular sem rede:
a tela avisa e a pessoa digita como sempre pôde. O preenchimento é um atalho,
não um requisito — e é por isso que `Cep.buscar` devolve nulo em vez de lançar.

Os testes de `test/cep_test.dart` cobrem a leitura das duas respostas sem rede;
`integration_test/cep_test.dart` digita um CEP de verdade num aparelho, contra o
serviço real — porque o que pode quebrar ali é o contrato do ViaCEP mudar, e uma
resposta fingida nunca perceberia isso.

## Onde a autorização mora

No banco, como no resto do projeto. O aplicativo abre uma sessão e consulta; a
RLS decide o que ele enxerga. Não existe nenhum `if (souDono)` decidindo acesso
neste código — onde aparece um papel, é para escolher o que **desenhar**, nunca
para liberar dado.

O preço segue a mesma ideia. O celular manda o que a pessoa quer comprar;
`public.fechar_pedido` recalcula tudo a partir do cardápio daquele instante e
grava. Se a tela e o banco discordarem do total, quem está certo é o banco.

## Estrutura

```
lib/
  ambiente.dart      chaves, via --dart-define
  sessao.dart        quem entrou, e qual fluxo abrir
  tema.dart          as cores da marca, as mesmas da web
  formato.dart       centavos -> reais, datas, telefone
  modelos/           os registros do banco, em Dart
  dados/             o que fala com o Supabase
  comum/             peças repetidas nas três frentes
  cliente/           vitrine, cardápio, carrinho, checkout, acompanhar
  restaurante/       fila do balcão, pedido, cardápio
  entregador/        corridas, corrida
```

## O que ainda não existe

- **Pagamento pelo aplicativo.** O `.env.example` do projeto prevê
  `PAGAMENTO_PROVEDOR=simulado`; enquanto não houver provedor real, a tela de
  acompanhamento diz isso em vez de mostrar um QR Code que ninguém paga.

  Tem uma consequência prática: um pedido "pago pelo aplicativo" nasce em
  `awaiting_payment`, e o balcão só enxerga a fila a partir de `received` — ou
  seja, ele ficaria parado esperando um gateway que não existe. Por isso o
  checkout escolhe, por omissão, uma forma que se paga na entrega, mesmo quando
  a loja também aceita Pix. Quando o provedor real entrar, essa preferência sai
  de `cliente/checkout.dart` e o padrão volta a ser a primeira forma cadastrada
  pelo estabelecimento.
- **Notificação empurrada.** Hoje a tela aberta se atualiza sozinha por
  Realtime, o que resolve com o aplicativo em uso. Avisar o cliente com o
  aplicativo fechado precisa de push.
- **Rota no mapa.** O mapa mostra onde estão a loja, o cliente e o entregador;
  não traça o caminho entre eles. Traçar exige um serviço de rotas, que é a
  próxima coisa a custar dinheiro por chamada.
- **Coordenada do endereço do cliente.** Vem do GPS, quando a pessoa toca em
  "marcar no mapa" ao cadastrar. Endereço antigo, ou de quem recusou, fica sem
  alfinete — o endereço escrito continua valendo, e a tela não finge que tem
  ponto.
