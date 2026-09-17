#!/usr/bin/env node
/**
 * Cria os usuarios de demonstracao e os liga aos estabelecimentos do seed.
 *
 * Nao faz parte do seed.sql porque login vive em auth.users, tabela do
 * Supabase Auth: INSERT direto ali funciona hoje e quebra na proxima versao,
 * alem de nao gerar o hash da senha do jeito certo. A API de administracao e
 * o caminho suportado.
 *
 * Exige SUPABASE_SERVICE_ROLE_KEY - a chave que ignora RLS. Por isso este
 * script nunca roda em producao.
 *
 * Uso:  node scripts/criar-usuarios-de-teste.mjs
 */

import { createClient } from "@supabase/supabase-js"
import { readFileSync } from "node:fs"

// Carrega .env.local sem depender de pacote externo.
for (const arquivo of [".env.local", ".env"]) {
  try {
    for (const linha of readFileSync(new URL(`../${arquivo}`, import.meta.url), "utf8").split("\n")) {
      const par = linha.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/)
      if (par && !process.env[par[1]]) {
        process.env[par[1]] = par[2].replace(/^["']|["']$/g, "")
      }
    }
  } catch {
    // Arquivo ausente e normal: as variaveis podem vir do ambiente.
  }
}

const url = process.env.NEXT_PUBLIC_SUPABASE_URL
const chave = process.env.SUPABASE_SERVICE_ROLE_KEY

if (!url || !chave) {
  console.error(
    "Faltam NEXT_PUBLIC_SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY.\n" +
      "Preencha o .env.local antes de rodar este script.",
  )
  process.exit(1)
}

const supabase = createClient(url, chave, {
  auth: { autoRefreshToken: false, persistSession: false },
})

/**
 * Senha unica para todos os perfis de teste. Serve para demonstracao; em
 * producao nenhuma conta nasce com senha conhecida.
 */
const SENHA = "tronvix123"

const BURGER_HOUSE = "a0000000-0000-4000-8000-000000000001"
const PIZZARIA = "a0000000-0000-4000-8000-000000000002"

const USUARIOS = [
  {
    email: "admin@tronvixfacil.com.br",
    nome: "Administrador da Plataforma",
    telefone: "62990000001",
    papel: "platform_admin",
    descricao: "Painel administrativo (/admin)",
  },
  {
    email: "dono@burgerhouse.com.br",
    nome: "Ricardo Menezes",
    telefone: "62990000002",
    papel: "customer",
    vinculo: { restaurante: BURGER_HOUSE, cargo: "owner" },
    descricao: "Proprietario da Burger House (/painel)",
  },
  {
    email: "atendente@burgerhouse.com.br",
    nome: "Paula Ramos",
    telefone: "62990000003",
    papel: "customer",
    vinculo: { restaurante: BURGER_HOUSE, cargo: "staff" },
    descricao: "Atendente da Burger House (painel reduzido)",
  },
  {
    email: "dono@pizzariadochef.com.br",
    nome: "Chef Antonio",
    telefone: "62990000004",
    papel: "customer",
    vinculo: { restaurante: PIZZARIA, cargo: "owner" },
    descricao: "Proprietario da Pizzaria do Chef",
  },
  {
    email: "entregador@tronvixfacil.com.br",
    nome: "Carlos Silva",
    telefone: "62990000005",
    papel: "courier",
    entregador: true,
    descricao: "Entregador aprovado (/entregas)",
  },
  {
    email: "cliente@tronvixfacil.com.br",
    nome: "Joao Silva",
    telefone: "62990000006",
    papel: "customer",
    descricao: "Cliente (aplicativo)",
  },
]

async function garantirUsuario(dados) {
  const { data: criado, error } = await supabase.auth.admin.createUser({
    email: dados.email,
    password: SENHA,
    email_confirm: true,
    user_metadata: {
      full_name: dados.nome,
      phone: dados.telefone,
      platform_role: dados.papel,
    },
  })

  if (criado?.user) return criado.user.id

  // Ja existe: o script pode rodar de novo sem quebrar.
  if (error && /already/i.test(error.message)) {
    const { data } = await supabase.auth.admin.listUsers({ perPage: 1000 })
    const existente = data?.users.find((u) => u.email === dados.email)
    if (existente) {
      // Garante que a senha e o papel continuam os do roteiro de teste.
      await supabase.auth.admin.updateUserById(existente.id, {
        password: SENHA,
        user_metadata: {
          full_name: dados.nome,
          phone: dados.telefone,
          platform_role: dados.papel,
        },
      })
      await supabase
        .from("profiles")
        .update({ full_name: dados.nome, phone: dados.telefone, platform_role: dados.papel })
        .eq("id", existente.id)
      return existente.id
    }
  }

  throw new Error(`Falha ao criar ${dados.email}: ${error?.message}`)
}

console.log("Criando usuarios de demonstracao...\n")

for (const dados of USUARIOS) {
  const id = await garantirUsuario(dados)

  if (dados.vinculo) {
    const { error } = await supabase.from("restaurant_members").upsert(
      {
        restaurant_id: dados.vinculo.restaurante,
        user_id: id,
        role: dados.vinculo.cargo,
        is_active: true,
      },
      { onConflict: "restaurant_id,user_id" },
    )
    if (error) throw new Error(`Vinculo de ${dados.email}: ${error.message}`)
  }

  if (dados.entregador) {
    const { error } = await supabase.from("couriers").upsert(
      { user_id: id, status: "approved", availability: "offline", vehicle_type: "motorcycle" },
      { onConflict: "user_id" },
    )
    if (error) throw new Error(`Entregador ${dados.email}: ${error.message}`)
  }

  console.log(`  ${dados.email.padEnd(36)} ${dados.descricao}`)
}

console.log(`\nSenha de todos: ${SENHA}`)
console.log("Use apenas em desenvolvimento.")
