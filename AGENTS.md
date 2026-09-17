<!-- BEGIN:nextjs-agent-rules -->

# This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` (resolved from this file's directory; in monorepos the `next` package may not be visible from the repo root) before writing any code. Heed deprecation notices.

This block is written and re-added by `next dev` — verify at `node_modules/next/dist/server/lib/generate-agent-files.js`. Removing it from a diff only re-creates the uncommitted change; committing it with your work keeps the tree clean.

<!-- END:nextjs-agent-rules -->

## Tronvix Fácil — convenções do projeto

### Nomes
Identificadores do banco (tabelas, colunas, tipos) em **inglês**. Código,
comentários, rotas e interface em **português**. A tradução dos rótulos mora
em um lugar só por domínio — nunca espalhada pelas telas.

### Dinheiro
Sempre `BIGINT` de centavos no banco e `number` de centavos em TypeScript,
com sufixo `_cents`. Nunca `float`, em nenhuma camada. Formatação só na borda
de exibição, por `src/lib/dinheiro.ts`. Percentuais em pontos base
(`1500` = 15,00%).

### Segurança de dados
RLS ligada em toda tabela nova, sem exceção. As políticas se apoiam em
`app.is_member`, `app.can_manage`, `app.is_platform_admin` e
`app.my_courier_id`. Nenhuma tela é a última linha de defesa.

Escrita de regra de negócio vai por Server Action, com Zod validando a
entrada no servidor. `criarClienteDeServico()` ignora RLS por completo: só
para webhook, criação de login e rotina administrativa.

### Máquina de estados
O fluxo de status existe no banco (`app.order_transition_allowed`) e em
`src/modules/pedidos/maquina-de-estados.ts`. Mudar um lado exige mudar o
outro; os testes das duas pontas verificam a mesma tabela de casos.

### Componentes de interface
Esta instalação do shadcn/ui é a versão **Base UI**, não Radix. Para renderizar
um componente como outro elemento use a prop `render`, não `asChild`:

```tsx
<Button render={<Link href="/entrar" />}>Entrar</Button>
```

### Depois de mudar o schema
```bash
npm run db:test     # as regras continuam valendo?
npm run db:tipos    # regenera src/types/banco.ts
```

### Antes de entregar
```bash
npm run verificar   # lint + testes + build
```
