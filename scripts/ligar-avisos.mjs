#!/usr/bin/env node
/**
 * Liga o aviso de pedido por push neste banco.
 *
 * O gatilho `app.avisar_pedido` chama a Edge Function, e precisa saber DOIS
 * dados que sao do ambiente, nao do schema: o endereco da funcao e a chave
 * para falar com ela. Por isso nao estao numa migracao - uma migracao com a
 * URL de um projeto dentro quebraria em qualquer outro.
 *
 * Ficam como configuracao do banco (ALTER DATABASE ... SET), que sobrevive a
 * reinicio e vale para toda sessao.
 *
 * Uso:  npm run avisos:ligar
 *
 * Sem rodar isto, o gatilho existe e nao faz nada - de proposito: um banco de
 * desenvolvimento recem-criado nao deve tentar mandar push.
 */

import { execFileSync } from "node:child_process"
import { readFileSync } from "node:fs"

for (const arquivo of [".env.local", ".env"]) {
  try {
    for (const linha of readFileSync(new URL(`../${arquivo}`, import.meta.url), "utf8").split("\n")) {
      const par = linha.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/)
      if (par && !process.env[par[1]]) process.env[par[1]] = par[2].replace(/^["']|["']$/g, "")
    }
  } catch {
    // Ausente e normal.
  }
}

const url = process.env.NEXT_PUBLIC_SUPABASE_URL
const chave = process.env.SUPABASE_SERVICE_ROLE_KEY
const senha = process.env.SUPABASE_DB_PASSWORD

if (!url || !chave) {
  console.error("Faltam NEXT_PUBLIC_SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY no .env.local.")
  process.exit(1)
}
if (!senha) {
  console.error(
    "Falta a senha do banco. Rode com:\n" +
      "  SUPABASE_DB_PASSWORD='...' npm run avisos:ligar\n\n" +
      "Ela e a senha definida na criacao do projeto Supabase — nao a chave de servico.",
  )
  process.exit(1)
}

const ref = new URL(url).hostname.split(".")[0]
const funcao = `${url}/functions/v1/avisar-pedido`
const conexao = `postgresql://postgres:${encodeURIComponent(senha)}@db.${ref}.supabase.co:5432/postgres`

// Duas linhas numa tabela do schema `app`. `alter database ... set` seria o
// lugar natural, mas no Supabase a role `postgres` nao e superusuaria e a
// operacao e negada.
const sql = `
insert into app.configuracao (chave, valor) values
  ('url_da_funcao_de_aviso', '${funcao}'),
  ('chave_de_servico', '${chave}')
on conflict (chave) do update set valor = excluded.valor, atualizado_em = now();
select 'configurado' as resultado;
`

try {
  const saida = execFileSync("psql", [conexao, "-v", "ON_ERROR_STOP=1", "-tA", "-c", sql], {
    encoding: "utf8",
    env: { ...process.env, PGCONNECT_TIMEOUT: "15" },
  })
  if (!saida.includes("configurado")) throw new Error(saida)

  console.log(`Avisos ligados neste banco.`)
  console.log(`  função: ${funcao}`)
  console.log()
  console.log("Vale imediatamente: o gatilho lê a configuração a cada pedido.")
} catch (e) {
  console.error(`Não consegui configurar: ${e instanceof Error ? e.message : e}`)
  process.exit(1)
}
