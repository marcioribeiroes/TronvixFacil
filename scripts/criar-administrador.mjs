#!/usr/bin/env node
/**
 * Cria — ou promove — um administrador da plataforma.
 *
 * Existe porque nao ha outro caminho, e isso e de proposito. O cadastro publico
 * so produz cliente e entregador; `platform_role` = 'platform_admin' vem de uma
 * promocao explicita, feita por quem ja e administrador ou por este script, que
 * usa a chave de servico.
 *
 * Antes da correcao em 20260917100800, qualquer pessoa nascia administradora
 * mandando `platform_role` nos metadados do cadastro. Este arquivo e a porta
 * que ficou no lugar do buraco.
 *
 * Uso:
 *   node scripts/criar-administrador.mjs <e-mail> [nome]
 *
 * A senha e sorteada e impressa uma unica vez. Se a pessoa ja existir, ela e
 * promovida e a senha NAO e trocada.
 */

import { createClient } from "@supabase/supabase-js"
import { randomBytes } from "node:crypto"
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
  console.error("Faltam NEXT_PUBLIC_SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY no .env.local.")
  process.exit(1)
}

const email = process.argv[2]
const nome = process.argv[3] ?? email?.split("@")[0]

if (!email || !email.includes("@")) {
  console.error("Uso: node scripts/criar-administrador.mjs <e-mail> [nome]")
  process.exit(1)
}

const supabase = createClient(url, chave, { auth: { persistSession: false } })

/** Senha sorteada, legivel e longa. Trocavel na primeira entrada. */
function senhaNova() {
  return randomBytes(18).toString("base64url").slice(0, 20)
}

const senha = senhaNova()

const { data: criado, error } = await supabase.auth.admin.createUser({
  email,
  password: senha,
  email_confirm: true,
  user_metadata: { full_name: nome },
})

let id = criado?.user?.id
let novo = Boolean(id)

if (!id) {
  if (!/already/i.test(error?.message ?? "")) {
    console.error(`Nao consegui criar: ${error?.message}`)
    process.exit(1)
  }
  const { data } = await supabase.auth.admin.listUsers({ perPage: 1000 })
  id = data?.users.find((u) => u.email?.toLowerCase() === email.toLowerCase())?.id
  if (!id) {
    console.error("O Auth diz que ja existe, mas eu nao achei. Confira o e-mail.")
    process.exit(1)
  }
}

// A promocao. Passa porque a chave de servico e reconhecida por
// app.guard_platform_role; com a chave anonima, isto seria recusado.
const { error: erroPromocao } = await supabase
  .from("profiles")
  .update({ platform_role: "platform_admin", full_name: nome })
  .eq("id", id)

if (erroPromocao) {
  console.error(`Criei o acesso, mas nao consegui promover: ${erroPromocao.message}`)
  process.exit(1)
}

const { data: perfil } = await supabase
  .from("profiles")
  .select("email, full_name, platform_role")
  .eq("id", id)
  .single()

console.log()
console.log(`  ${perfil.full_name} <${perfil.email}>`)
console.log(`  papel: ${perfil.platform_role}`)
if (novo) {
  console.log(`  senha: ${senha}`)
  console.log()
  console.log("  Anote agora: esta senha nao volta a ser mostrada.")
  console.log("  Troque-a na primeira entrada.")
} else {
  console.log()
  console.log("  Ja existia: promovido, e a senha continua a mesma de antes.")
}
console.log()
console.log("  A administracao e a web, em /admin.")
console.log()
