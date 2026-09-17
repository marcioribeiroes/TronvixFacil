# Arquitetura — Tronvix Fácil

Documento de decisões. Diz o que foi escolhido, e principalmente **por quê** e
**o que foi descartado**. Quem chegar daqui a seis meses precisa entender o
raciocínio sem ter de reconstruí-lo.

---

## 1. Quatro aplicativos, um deploy

Cliente, restaurante, entregador e administração vivem no mesmo projeto
Next.js, separados por *route groups*: `(cliente)`, `(restaurante)`,
`(entregador)`, `(admin)`.

**Por quê.** Os quatro compartilham sessão, tipos, componentes e banco.
Separar em quatro deploys custaria quatro pipelines, quatro configurações de
ambiente e um contrato de API entre eles — sem entregar nada a mais nesta
fase.

**Custo aceito.** Um deploy único significa que um erro de build em qualquer
app derruba todos. Em troca, a separação por rota permite extrair qualquer um
deles depois sem reescrever o núcleo: a regra de negócio está em `modules/`,
não nas telas.

## 2. Camadas

| Camada | Papel | Regra |
|---|---|---|
| `app/**` | Rotas, Server Components, layout | Só orquestra. Nenhuma regra de negócio. |
| `modules/<domínio>` | Regra + acesso a dados | `server-only`. Não importa React. |
| `app/api/**` | Superfície HTTP | Só o que precisa ser HTTP: webhooks, app do entregador, integrações. |
| Server Actions | Mutações do próprio front | Entrada validada com Zod, sempre. |

Cada módulo segue o mesmo formato: `schema.ts` (Zod), `repositorio.ts` (banco),
`servico.ts` (regra), `acoes.ts` (Server Actions), `*.test.ts`.

## 3. Multi-tenant: o isolamento é do banco

Toda tabela de estabelecimento tem `restaurant_id` e RLS ligada. As políticas
se apoiam em quatro funções `SECURITY DEFINER` no schema `app`:

| Função | Pergunta que responde |
|---|---|
| `app.is_member(restaurante)` | Trabalha aqui? |
| `app.can_manage(restaurante)` | É proprietário ou gerente? |
| `app.is_platform_admin()` | Administra a plataforma? |
| `app.my_courier_id()` | Qual é o cadastro de entregador desta pessoa? |

**Por que no banco, e não no código.** Filtro em código é uma promessa que
alguém precisa lembrar de cumprir em toda consulta nova. Um `where` esquecido
vaza dados do estabelecimento vizinho, e o bug é silencioso: a tela funciona,
só mostra demais. Com RLS, o mesmo esquecimento devolve **zero linhas** — um
erro visível, do lado seguro.

As funções são `SECURITY DEFINER` porque precisam ler `restaurant_members`
sem disparar a RLS dessa própria tabela, o que causaria recursão infinita. E
são `STABLE` para que o planejador as avalie uma vez por consulta, não uma vez
por linha — a diferença aparece na listagem de pedidos.

## 4. Dinheiro é inteiro de centavos

`BIGINT` no banco, `number` de centavos em TypeScript, decimal só na borda de
exibição (`src/lib/dinheiro.ts`).

`0.1 + 0.2 === 0.30000000000000004`. Numa plataforma de delivery esse erro não
fica escondido: aparece na conferência de caixa do restaurante e na comissão
retida pela plataforma.

Percentuais seguem a mesma lógica, em **pontos base**: `1500` = 15,00%.
Comissão e desconto são inteiros do começo ao fim.

## 5. Máquina de estados, declarada duas vezes de propósito

O fluxo de status existe em dois lugares:

- `app.order_transition_allowed()` no Postgres — **inviolável**. Nenhum
  caminho leva um pedido de `delivered` de volta para `preparing`.
- `src/modules/pedidos/maquina-de-estados.ts` — para a **interface saber o que
  oferecer antes de tentar**. O painel desenha os botões possíveis de cada
  pedido; sem o espelho, a única forma de descobrir seria mandar e ver
  recusar.

A duplicação é deliberada e protegida: as duas cópias são verificadas pela
mesma tabela de casos, em `maquina-de-estados.test.ts` e em
`supabase/tests/regras_do_pedido.sql`. Mudar uma sem a outra deixa os testes
vermelhos.

## 6. O pedido guarda snapshot

`order_items` copia nome e preço do produto no instante da compra;
`orders` copia o endereço e o contato do cliente.

**Por quê.** O restaurante reajusta o cardápio amanhã, o cliente apaga o
endereço antigo — e o pedido de ontem continua contando a história certa. Sem
snapshot, um relatório de faturamento do mês passado mudaria sozinho a cada
alteração de preço.

Efeito colateral bom: o restaurante vê o nome e o telefone do cliente **do
pedido**, sem precisar de permissão de leitura sobre a tabela de perfis da
plataforma inteira.

## 7. Preço é calculado no servidor

O carrinho envia IDs e quantidades. O backend busca preço, adicionais,
promoção vigente, taxa de entrega e cupom no banco, e monta o total. O valor
enviado pelo navegador é descartado.

Três camadas garantem isso:

1. A restrição `orders_total_matches` no banco recusa um total que não fecha
   com as partes.
2. O gatilho `app.guard_order_money` impede alterar valores de um pedido já
   fechado pela API.
3. O fechamento roda em função do Postgres, de forma atômica — não há janela
   entre calcular e gravar.

## 8. Numeração por estabelecimento

Cada loja tem o seu pedido **#1**. Uma tabela de contadores com trava de linha
(`UPDATE ... RETURNING`) garante que dois pedidos simultâneos nunca recebam o
mesmo número — o que `max(number) + 1` não garante.

Ninguém quer explicar ao cliente por que o primeiro pedido do dia foi o número
48.317.

## 9. Pagamento por adaptador

`modules/pagamentos` expõe uma porta; os adaptadores implementam. Enquanto o
gateway real não entra, o adaptador simulado preenche **os mesmos campos** de
`payments` (`provider`, `provider_ref`, `pix_qr_code`). Trocar de provedor não
toca no schema nem na regra de negócio.

O índice único em `(provider, provider_ref)` dá idempotência de webhook: o
mesmo evento chegando duas vezes não cria dois pagamentos.

## 10. Integração com o TronvixERP

Esta versão opera sozinha. `modules/integracoes/erp` guarda a porta desenhada
para quando o cardápio e o estoque passarem a vir do ERP e o pedido do
delivery virar venda lá dentro. Amarrar as duas agendas desde o primeiro dia
travaria o delivery na API do ERP.

## 11. Decisões de ambiente

**Supabase em vez de Prisma + Docker.** O briefing pedia Prisma; a escolha foi
Supabase porque o isolamento multi-tenant passa a ser garantido pelo banco
(RLS), e Auth, Storage (fotos de produto) e Realtime (Kanban ao vivo) já vêm
juntos. Com Prisma, cada uma dessas quatro coisas seria código próprio para
escrever e manter.

**Sem Docker na máquina de desenvolvimento.** `supabase start` exige um
runtime de container. Para não deixar o schema sem teste,
`scripts/testar-banco.sh` roda as migrações e as 33 verificações de regra num
Postgres local comum, com `supabase/tests/ambiente-local.sql` recriando o
mínimo do Supabase.

**Tipos gerados, não escritos.** `supabase gen types` também exige Docker, por
isso `scripts/gerar-tipos.mjs` lê o schema real por `psql` e emite
`src/types/banco.ts` — inclusive as `Relationships`, que dão tipo às consultas
aninhadas. O tipo é consequência do schema; nunca uma cópia mantida à mão, que
envelhece em silêncio.

## 12. O que ainda não existe

| Etapa | Entrega |
|---|---|
| 2 | Catálogo, produto com adicionais, carrinho, checkout, acompanhamento |
| 3 | Kanban em tempo real, cardápio, produtos, adicionais, dashboard |
| 4 | Entregador: disponibilidade, aceite, rastreio, ganhos |
| 5 | Administração: restaurantes, usuários, financeiro, comissões |
| 6 | Testes de RLS por papel, endurecimento, UX, produção |

O que já está pronto por baixo de cada uma está listado nas próprias telas.
