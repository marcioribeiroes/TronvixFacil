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

## Usuários de teste

Criados por `npm run db:semente`. Senha de todos: `tronvix123`.

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
