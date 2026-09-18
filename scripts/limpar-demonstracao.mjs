#!/usr/bin/env node
/**
 * Tira a demonstracao do ar.
 *
 * O projeto nasceu com cinco restaurantes inventados e seis contas de senha
 * `tronvix123` - documentadas no README, o que e o mesmo que publicadas. Isso
 * serve para desenvolver e e um buraco assim que alguem de verdade entra: um
 * dos logins e administrador da plataforma inteira.
 *
 * O que apaga, e o que nunca apaga:
 *
 *   - restaurantes da semente: id que comeca com a0000000-0000-4000-8000-.
 *     Nenhum cadastro real tem esse prefixo - o banco gera uuid aleatorio.
 *   - as seis contas de demonstracao, pela lista fixa de e-mails.
 *
 * Qualquer outra coisa fica. E se a conferencia encontrar um pedido de loja
 * real ligado a um cliente da demonstracao, o script para: e sinal de que a
 * demonstracao virou producao em algum ponto, e apagar seria destruir venda.
 *
 * Uso:
 *   node scripts/limpar-demonstracao.mjs              # so mostra o que iria
 *   node scripts/limpar-demonstracao.mjs --confirmar  # apaga
 */

import { createClient } from "@supabase/supabase-js"
import { readFileSync } from "node:fs"

for (const arquivo of [".env.local", ".env"]) {
  try {
    for (const linha of readFileSync(new URL(`../${arquivo}`, import.meta.url), "utf8").split("\n")) {
      const par = linha.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/)
      if (par && !process.env[par[1]]) process.env[par[1]] = par[2].replace(/^["']|["']$/g, "")
    }
  } catch {
    // Ausente e normal: as variaveis podem vir do ambiente.
  }
}

const url = process.env.NEXT_PUBLIC_SUPABASE_URL
const chave = process.env.SUPABASE_SERVICE_ROLE_KEY

if (!url || !chave) {
  console.error("Faltam NEXT_PUBLIC_SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY.")
  process.exit(1)
}

const supabase = createClient(url, chave, {
  auth: { autoRefreshToken: false, persistSession: false },
})

/** O prefixo dos ids da semente. Cadastro real nunca cai aqui. */
const PREFIXO_DA_SEMENTE = "a0000000-0000-4000-8000-"

const CONTAS = [
  "admin@tronvixfacil.com.br",
  "dono@burgerhouse.com.br",
  "atendente@burgerhouse.com.br",
  "dono@pizzariadochef.com.br",
  "entregador@tronvixfacil.com.br",
  "cliente@tronvixfacil.com.br",
]

const valendo = process.argv.includes("--confirmar")

// ---------------------------------------------------------------------------
// Levantamento
// ---------------------------------------------------------------------------

const { data: lojas, error: erroDeLojas } = await supabase
  .from("restaurants")
  .select("id, name, slug")

if (erroDeLojas) {
  console.error("Não consegui ler os estabelecimentos:", erroDeLojas.message)
  process.exit(1)
}

const daSemente = (lojas ?? []).filter((r) => r.id.startsWith(PREFIXO_DA_SEMENTE))
const reais = (lojas ?? []).filter((r) => !r.id.startsWith(PREFIXO_DA_SEMENTE))

const { data: usuarios } = await supabase.auth.admin.listUsers({ perPage: 1000 })
const contasDaDemo = (usuarios?.users ?? []).filter((u) => CONTAS.includes(u.email ?? ""))

const idsDaSemente = daSemente.map((r) => r.id)
const idsDaDemo = contasDaDemo.map((u) => u.id)

const { count: pedidosDaSemente } = idsDaSemente.length
  ? await supabase
      .from("orders")
      .select("id", { count: "exact", head: true })
      .in("restaurant_id", idsDaSemente)
  : { count: 0 }

// A trava: cliente de demonstracao que comprou numa loja de verdade.
let pedidosCruzados = 0
if (idsDaDemo.length && reais.length) {
  const { count } = await supabase
    .from("orders")
    .select("id", { count: "exact", head: true })
    .in("customer_id", idsDaDemo)
    .in("restaurant_id", reais.map((r) => r.id))
  pedidosCruzados = count ?? 0
}

console.log("Estabelecimentos de demonstração:")
for (const r of daSemente) console.log(`  ${r.slug.padEnd(20)} ${r.name}`)
if (daSemente.length === 0) console.log("  nenhum")

console.log(`\nPedidos ligados a eles: ${pedidosDaSemente ?? 0}`)

console.log("\nContas de demonstração:")
for (const u of contasDaDemo) console.log(`  ${u.email}`)
if (contasDaDemo.length === 0) console.log("  nenhuma")

console.log("\nFica no ar:")
for (const r of reais) console.log(`  ${r.slug.padEnd(20)} ${r.name}`)
if (reais.length === 0) console.log("  nenhum estabelecimento real ainda")

if (pedidosCruzados > 0) {
  console.error(
    `\nPAREI. ${pedidosCruzados} pedido(s) de loja real foram feitos por uma conta de\n` +
      "demonstração. Apagar a conta apagaria o cliente de uma venda de verdade.\n" +
      "Renomeie essas contas antes, ou apague só os restaurantes da semente.",
  )
  process.exit(1)
}

if (!valendo) {
  console.log("\nIsto foi só o levantamento. Para apagar de verdade:")
  console.log("  node scripts/limpar-demonstracao.mjs --confirmar")
  process.exit(0)
}

// ---------------------------------------------------------------------------
// Limpeza
// ---------------------------------------------------------------------------

/** Para e explica: numa limpeza, seguir depois de um erro e o pior caminho. */
function conferir(rotulo, error) {
  if (error) {
    console.error(`\nFalhou em ${rotulo}: ${error.message}`)
    process.exit(1)
  }
}

if (idsDaSemente.length) {
  // orders referencia restaurants com `on delete restrict` - de proposito, para
  // que ninguem apague uma loja e leve o historico de vendas junto por
  // distracao. Aqui a intencao e essa, entao os pedidos saem primeiro; os
  // filhos deles (itens, pagamentos, entregas, historico) saem em cascata.
  conferir(
    "pedidos da semente",
    (await supabase.from("orders").delete().in("restaurant_id", idsDaSemente)).error,
  )
  conferir(
    "carrinhos da semente",
    (await supabase.from("carts").delete().in("restaurant_id", idsDaSemente)).error,
  )
  conferir(
    "estabelecimentos da semente",
    (await supabase.from("restaurants").delete().in("id", idsDaSemente)).error,
  )
  console.log(`\n${idsDaSemente.length} estabelecimento(s) de demonstração apagado(s).`)
}

for (const u of contasDaDemo) {
  // Carrinho e endereco do cliente nao caem junto com o restaurante; saem aqui.
  await supabase.from("carts").delete().eq("customer_id", u.id)
  await supabase.from("addresses").delete().eq("user_id", u.id)
  const { error } = await supabase.auth.admin.deleteUser(u.id)
  conferir(`conta ${u.email}`, error)
  console.log(`  conta apagada: ${u.email}`)
}

// Conferencia final: o que sobrou e o que deveria sobrar?
const { data: depois } = await supabase.from("restaurants").select("id, name, slug")
const restou = (depois ?? []).filter((r) => r.id.startsWith(PREFIXO_DA_SEMENTE))

if (restou.length) {
  console.error(`\nSobraram ${restou.length} estabelecimento(s) da semente. Rode de novo.`)
  process.exit(1)
}

console.log("\nDemonstração fora do ar.")
console.log(`${(depois ?? []).length} estabelecimento(s) no banco, todos de verdade.`)
console.log("\nAgora tire as senhas do README — elas não abrem mais nada, mas continuam")
console.log("dizendo que abrem.")
