#!/usr/bin/env node
/**
 * Poe um restaurante de verdade no ar.
 *
 * Faz numa passada o que, sem ele, sao doze telas e uma hora: cria a conta do
 * dono, cadastra o estabelecimento ja aprovado, liga o vinculo, monta o
 * cardapio, liga as formas de pagamento e escreve os horarios.
 *
 * Por que script e nao tela: o cadastro publico cria o estabelecimento
 * PENDENTE, e quem aprova e a plataforma - esse fluxo esta certo e continua
 * valendo para quem chega sozinho. Aqui e o outro caso: alguem da plataforma
 * abrindo a loja de um cliente que ja fechou negocio, com a chave de servico
 * na mao.
 *
 * A senha do dono e sorteada e mostrada UMA vez. Nenhuma conta de verdade
 * nasce com senha conhecida - foi exatamente esse o defeito das contas de
 * demonstracao.
 *
 * Uso:
 *   node scripts/abrir-restaurante.mjs loja.json
 *
 * O formato do arquivo esta em docs/abrir-restaurante.exemplo.json.
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
    // Ausente e normal.
  }
}

const url = process.env.NEXT_PUBLIC_SUPABASE_URL
const chave = process.env.SUPABASE_SERVICE_ROLE_KEY

if (!url || !chave) {
  console.error("Faltam NEXT_PUBLIC_SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY.")
  process.exit(1)
}

const caminho = process.argv[2]
if (!caminho) {
  console.error("Uso: node scripts/abrir-restaurante.mjs loja.json")
  console.error("Modelo: docs/abrir-restaurante.exemplo.json")
  process.exit(1)
}

const dados = JSON.parse(readFileSync(caminho, "utf8"))
const supabase = createClient(url, chave, {
  auth: { autoRefreshToken: false, persistSession: false },
})

// ---------------------------------------------------------------------------
// Conferencia antes de escrever
// ---------------------------------------------------------------------------

/** "R$ 7,90", "7,90" e 7.9 viram 790. O banco so conhece centavos. */
function centavos(valor) {
  if (typeof valor === "number") return Math.round(valor * 100)
  if (!valor) return 0
  const limpo = String(valor).replace(/[R$\s]/g, "")
  const normalizado = limpo.includes(",")
    ? limpo.replace(/\./g, "").replace(",", ".")
    : limpo
  const n = Number(normalizado)
  if (!Number.isFinite(n)) throw new Error(`Valor não entendido: ${valor}`)
  return Math.round(n * 100)
}

/**
 * Telefone vira digitos.
 *
 * profiles tem `check (phone ~ '^[0-9]{10,13}$')`, e o gatilho que cria o
 * perfil roda DENTRO do createUser - entao "(62) 99000-0000" nao falha aqui,
 * falha la, e o Supabase devolve "Database error creating new user", que nao
 * diz nada. Melhor limpar antes e recusar com nome e sobrenome.
 */
function digitos(valor) {
  return String(valor ?? "").replace(/\D/g, "")
}

/** "Açaí & Cia" -> "acai-e-cia". O slug e o endereco publico da loja. */
function slugificar(nome) {
  return nome
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/&/g, " e ")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "")
}

const r0 = dados.restaurante ?? {}

const faltando = []
if (!dados.restaurante?.nome) faltando.push("restaurante.nome")
if (!dados.restaurante?.telefone) faltando.push("restaurante.telefone")
if (!dados.restaurante?.rua) faltando.push("restaurante.rua")
if (!dados.restaurante?.numero) faltando.push("restaurante.numero")
if (!dados.restaurante?.bairro) faltando.push("restaurante.bairro")
if (!dados.restaurante?.cidade) faltando.push("restaurante.cidade")
if (!dados.dono?.email) faltando.push("dono.email")
if (!dados.dono?.nome) faltando.push("dono.nome")

if (faltando.length) {
  console.error("Faltam campos obrigatórios:\n  " + faltando.join("\n  "))
  process.exit(1)
}

const telefoneDaLoja = digitos(r0.telefone)
const telefoneDoDono = digitos(dados.dono.telefone)

if (telefoneDaLoja.length < 10 || telefoneDaLoja.length > 13) {
  console.error(`Telefone da loja com ${telefoneDaLoja.length} dígitos: precisa de 10 a 13 (DDD + número).`)
  process.exit(1)
}
if (dados.dono.telefone && (telefoneDoDono.length < 10 || telefoneDoDono.length > 13)) {
  console.error(`Telefone do dono com ${telefoneDoDono.length} dígitos: precisa de 10 a 13 (DDD + número).`)
  process.exit(1)
}

const slug = dados.restaurante.slug || slugificar(dados.restaurante.nome)

const { data: jaExiste } = await supabase
  .from("restaurants")
  .select("id, name")
  .eq("slug", slug)
  .maybeSingle()

if (jaExiste) {
  console.error(`Já existe um estabelecimento com o endereço /${slug}: ${jaExiste.name}`)
  console.error('Escolha outro em "restaurante.slug".')
  process.exit(1)
}

// ---------------------------------------------------------------------------
// A conta do dono
// ---------------------------------------------------------------------------

/**
 * Senha sorteada, forte, mostrada uma vez. O dono troca na primeira entrada -
 * e enquanto nao trocar, ninguem consegue adivinhar.
 */
const senha = randomBytes(9).toString("base64url")

let donoId
const { data: criado, error: erroDeConta } = await supabase.auth.admin.createUser({
  email: dados.dono.email,
  password: senha,
  email_confirm: true,
  user_metadata: {
    full_name: dados.dono.nome,
    phone: telefoneDoDono || null,
    platform_role: "customer",
  },
})

let senhaNova = true
if (criado?.user) {
  donoId = criado.user.id
} else if (erroDeConta && /already/i.test(erroDeConta.message)) {
  // Conta existente nao tem a senha trocada: o dono ja usa a dele, e trocar
  // sem avisar o deixaria de fora do proprio sistema.
  const { data } = await supabase.auth.admin.listUsers({ perPage: 1000 })
  const existente = data?.users.find((u) => u.email === dados.dono.email)
  if (!existente) {
    console.error(`Conta ${dados.dono.email} existe mas não consegui encontrá-la.`)
    process.exit(1)
  }
  donoId = existente.id
  senhaNova = false
} else {
  console.error(`Não consegui criar a conta do dono: ${erroDeConta?.message}`)
  process.exit(1)
}

// ---------------------------------------------------------------------------
// O estabelecimento
// ---------------------------------------------------------------------------

const r = dados.restaurante

const { data: loja, error: erroDaLoja } = await supabase
  .from("restaurants")
  .insert({
    slug,
    name: r.nome,
    legal_name: r.razaoSocial ?? null,
    document: r.documento ? digitos(r.documento) : null,
    description: r.descricao ?? null,
    phone: telefoneDaLoja,
    email: r.email ?? dados.dono.email,
    // Aprovado direto: quem roda este script e a plataforma, e a decisao de
    // aceitar a loja ja foi tomada fora do sistema.
    status: "approved",
    approved_at: new Date().toISOString(),
    // Fechada ate o dono abrir. Loja que nasce aberta com cardapio pela metade
    // recebe pedido que nao consegue atender.
    is_open: false,
    street: r.rua,
    number: String(r.numero),
    complement: r.complemento ?? null,
    district: r.bairro,
    city: r.cidade,
    state: r.estado ?? "GO",
    postal_code: r.cep ? digitos(r.cep) : null,
    latitude: r.latitude ?? null,
    longitude: r.longitude ?? null,
    delivery_fee_cents: centavos(r.taxaDeEntrega ?? 0),
    free_delivery_above_cents: r.entregaGratisAcimaDe ? centavos(r.entregaGratisAcimaDe) : null,
    min_order_cents: centavos(r.pedidoMinimo ?? 0),
    delivery_radius_km: r.raioDeEntregaKm ?? 5,
    avg_prep_minutes: r.minutosDePreparo ?? 30,
    avg_delivery_minutes: r.minutosDeEntrega ?? 20,
    commission_bps: Math.round((r.comissaoPercentual ?? 10) * 100),
    accepts_platform_couriers: r.aceitaEntregadorDaPlataforma ?? false,
  })
  .select("id, slug, name")
  .single()

if (erroDaLoja) {
  console.error(`Não consegui cadastrar o estabelecimento: ${erroDaLoja.message}`)
  process.exit(1)
}

const { error: erroDoVinculo } = await supabase.from("restaurant_members").insert({
  restaurant_id: loja.id,
  user_id: donoId,
  role: "owner",
  is_active: true,
})

if (erroDoVinculo) {
  console.error(`Estabelecimento criado, mas o vínculo falhou: ${erroDoVinculo.message}`)
  process.exit(1)
}

// ---------------------------------------------------------------------------
// Formas de pagamento, horarios e cardapio
// ---------------------------------------------------------------------------

/**
 * So o que fecha o ciclo hoje. Pix e credito pelo site precisam de provedor de
 * pagamento; ligados sem ele, o pedido nasce em "aguardando pagamento" e nunca
 * chega ao balcao. O dono liga quando houver provedor.
 */
const FORMAS = dados.formasDePagamento ?? ["cash", "debit_card", "credit_card"]
await supabase.from("restaurant_payment_methods").upsert(
  FORMAS.map((metodo) => ({
    restaurant_id: loja.id,
    method: metodo,
    timing: "on_delivery",
    is_active: true,
  })),
  { onConflict: "restaurant_id,method" },
)

if (Array.isArray(dados.horarios) && dados.horarios.length) {
  const { error } = await supabase.from("restaurant_hours").insert(
    dados.horarios.map((h) => ({
      restaurant_id: loja.id,
      weekday: h.dia,
      opens_at: h.abre,
      closes_at: h.fecha,
    })),
  )
  if (error) console.warn(`  aviso: horários não entraram (${error.message})`)
}

let produtosCriados = 0
for (const [i, secao] of (dados.cardapio ?? []).entries()) {
  const { data: categoria, error } = await supabase
    .from("categories")
    .insert({
      restaurant_id: loja.id,
      name: secao.categoria,
      description: secao.descricao ?? null,
      position: i + 1,
      is_active: true,
    })
    .select("id")
    .single()

  if (error) {
    console.error(`Categoria "${secao.categoria}": ${error.message}`)
    continue
  }

  const itens = (secao.itens ?? []).map((p, j) => ({
    restaurant_id: loja.id,
    category_id: categoria.id,
    name: p.nome,
    description: p.descricao ?? null,
    price_cents: centavos(p.preco),
    is_available: p.disponivel ?? true,
    position: j + 1,
    serves_people: p.serve ?? null,
    prep_minutes: p.minutosDePreparo ?? null,
  }))

  if (itens.length) {
    const { error: erroDeProdutos } = await supabase.from("products").insert(itens)
    if (erroDeProdutos) console.error(`Produtos de "${secao.categoria}": ${erroDeProdutos.message}`)
    else produtosCriados += itens.length
  }
}

// ---------------------------------------------------------------------------

const site = process.env.NEXT_PUBLIC_URL_DO_SITE ?? "http://localhost:3000"

console.log(`\n${loja.name} está cadastrado.\n`)
console.log(`  endereço público   ${site}/restaurante/${loja.slug}`)
console.log(`  painel             ${site}/painel`)
console.log(`  cardápio           ${produtosCriados} produtos em ${(dados.cardapio ?? []).length} categorias`)
console.log(`\n  dono               ${dados.dono.email}`)
if (senhaNova) {
  console.log(`  senha              ${senha}`)
  console.log("\n  Esta senha não aparece de novo. Mande ao dono por um canal seguro e")
  console.log("  peça que ele troque na primeira entrada.")
} else {
  console.log("  senha              a que ele já usava (a conta existia)")
}
console.log("\nA loja está FECHADA. O dono abre no painel quando o cardápio estiver pronto.")
