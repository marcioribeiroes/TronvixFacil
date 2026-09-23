#!/usr/bin/env node
/**
 * Preenche a coordenada das lojas que estao sem, a partir do CEP delas.
 *
 * Existe por causa de um buraco: `restaurants.latitude` e `longitude` estao no
 * schema desde a fundacao e nenhuma tela jamais as escreveu — so o
 * `seed.sql`. As lojas de demonstracao tinham coordenada; toda loja cadastrada
 * de verdade nascia sem. E sem coordenada a corrida nao tem distancia, o mapa
 * de coleta do entregador fica vazio e o raio de entrega nao tem centro.
 *
 * O cadastro novo ja resolve sozinho (src/modules/parceiro/cadastro.ts). Este
 * script e para quem ja estava cadastrado antes disso.
 *
 * E o centro do CEP, nao a porta da loja: erra por quarteiroes numa rua longa.
 * Serve para medir corrida e desenhar mapa, e o endereco escrito continua
 * sendo o que leva o entregador ate la.
 *
 * Uso:
 *   node scripts/preencher-coordenadas.mjs            mostra o que faria
 *   node scripts/preencher-coordenadas.mjs --gravar   grava
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
    // Ausente e normal.
  }
}

const url = process.env.NEXT_PUBLIC_SUPABASE_URL
const chave = process.env.SUPABASE_SERVICE_ROLE_KEY

if (!url || !chave) {
  console.error("Faltam NEXT_PUBLIC_SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY no .env.local.")
  process.exit(1)
}

const gravar = process.argv.includes("--gravar")
const supabase = createClient(url, chave, { auth: { persistSession: false } })

/** O mesmo cuidado de src/lib/geocodificar.ts: texto, nulo e lixo viram nulo. */
function coordenadasDaResposta(corpo) {
  const par = corpo?.location?.coordinates
  if (!par) return null

  const { latitude, longitude } = par
  if (latitude === undefined || latitude === null || latitude === "") return null
  if (longitude === undefined || longitude === null || longitude === "") return null

  const lat = Number(latitude)
  const lon = Number(longitude)
  if (!Number.isFinite(lat) || !Number.isFinite(lon)) return null
  if (lat < -90 || lat > 90 || lon < -180 || lon > 180) return null

  return { latitude: lat, longitude: lon }
}

async function coordenadasDoCep(cep) {
  const digitos = String(cep ?? "").replace(/\D/g, "")
  if (digitos.length !== 8) return null

  try {
    const resposta = await fetch(`https://brasilapi.com.br/api/cep/v2/${digitos}`, {
      signal: AbortSignal.timeout(8000),
    })
    if (!resposta.ok) return null
    return coordenadasDaResposta(await resposta.json())
  } catch {
    return null
  }
}

const { data: lojas, error } = await supabase
  .from("restaurants")
  .select("id, slug, name, postal_code, street, city, state")
  .is("latitude", null)
  .order("name")

if (error) {
  console.error(`Nao consegui ler as lojas: ${error.message}`)
  process.exit(1)
}

if (!lojas || lojas.length === 0) {
  console.log("\n  Nenhuma loja sem coordenada.\n")
  process.exit(0)
}

console.log()
console.log(`  ${lojas.length} loja(s) sem coordenada.`)
console.log(gravar ? "  Gravando." : "  Simulando — use --gravar para valer.")
console.log()

let achadas = 0
let semCep = 0
let semResposta = 0

for (const loja of lojas) {
  if (!loja.postal_code) {
    semCep++
    console.log(`  ${loja.name} — sem CEP no cadastro, nao da para localizar`)
    continue
  }

  const onde = await coordenadasDoCep(loja.postal_code)

  if (!onde) {
    semResposta++
    console.log(`  ${loja.name} — CEP ${loja.postal_code} nao devolveu coordenada`)
    continue
  }

  achadas++
  console.log(`  ${loja.name} — ${onde.latitude}, ${onde.longitude}  (CEP ${loja.postal_code})`)

  if (gravar) {
    const { error: erroDaEscrita } = await supabase
      .from("restaurants")
      .update({ latitude: onde.latitude, longitude: onde.longitude })
      .eq("id", loja.id)

    if (erroDaEscrita) console.log(`      NAO GRAVOU: ${erroDaEscrita.message}`)
  }
}

console.log()
console.log(`  localizadas: ${achadas}   sem CEP: ${semCep}   CEP sem coordenada: ${semResposta}`)

if (!gravar && achadas > 0) {
  console.log()
  console.log("  Nada foi gravado. Rode com --gravar para aplicar.")
}

// A distancia das corridas ja existentes e congelada no nascimento da corrida,
// entao preencher a loja agora NAO volta atras e preenche o que ja passou. As
// corridas novas e que nascerao sabendo.
if (gravar && achadas > 0) {
  console.log()
  console.log("  As corridas que ja existem seguem sem distancia: ela e congelada")
  console.log("  quando a corrida nasce. Vale das proximas em diante.")
}

console.log()
