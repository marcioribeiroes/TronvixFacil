#!/usr/bin/env node
/**
 * Gera src/types/banco.ts a partir do schema real do Postgres.
 *
 * O `supabase gen types` oficial sobe um container para fazer isso, e nem toda
 * maquina de desenvolvimento tem Docker. Este gerador fala com o banco por
 * psql e produz o mesmo formato que o cliente do Supabase espera, entao o
 * tipo continua sendo consequencia do schema - nunca uma copia mantida a mao,
 * que envelhece em silencio a cada migracao.
 *
 * Uso:  npm run db:tipos
 */

import { execFileSync } from "node:child_process"
import { writeFileSync } from "node:fs"

const BANCO = process.env.BANCO_DE_TESTE ?? "tronvix_facil_teste"
const DESTINO = new URL("../src/types/banco.ts", import.meta.url)

const CONSULTA = `
select json_build_object(
  'enums', coalesce((
    select json_agg(json_build_object('nome', t.typname, 'valores', v.valores) order by t.typname)
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    join lateral (
      select json_agg(e.enumlabel order by e.enumsortorder) as valores
      from pg_enum e where e.enumtypid = t.oid
    ) v on true
    where n.nspname = 'public' and t.typtype = 'e'
  ), '[]'::json),
  'relacoes', coalesce((
    select json_agg(json_build_object(
      'tabela', tc.table_name,
      'nome', tc.constraint_name,
      'colunas', kc.colunas,
      'referencia', ref.tabela,
      'colunasReferenciadas', ref.colunas,
      'umParaUm', exists (
        select 1 from pg_index i
        where i.indrelid = (quote_ident(tc.table_schema) || '.' || quote_ident(tc.table_name))::regclass
          and i.indisunique
          and i.indnatts = array_length(kc.colunas, 1)
          and (
            select array_agg(a.attname::text order by a.attname)
            from unnest(i.indkey) as k(attnum)
            join pg_attribute a on a.attrelid = i.indrelid and a.attnum = k.attnum
          ) = (select array_agg(c order by c) from unnest(kc.colunas) as c)
      )
    ) order by tc.table_name, tc.constraint_name)
    from information_schema.table_constraints tc
    join lateral (
      select array_agg(k.column_name::text order by k.ordinal_position) as colunas
      from information_schema.key_column_usage k
      where k.constraint_name = tc.constraint_name and k.constraint_schema = tc.constraint_schema
    ) kc on true
    join lateral (
      select ccu.table_name::text as tabela,
             array_agg(ccu.column_name::text) as colunas
      from information_schema.constraint_column_usage ccu
      where ccu.constraint_name = tc.constraint_name and ccu.constraint_schema = tc.constraint_schema
      group by ccu.table_name
    ) ref on true
    where tc.constraint_type = 'FOREIGN KEY' and tc.table_schema = 'public'
  ), '[]'::json),
  'funcoes', coalesce((
    -- So as funcoes que o cliente chama por rpc(): as do schema public, que o
    -- PostgREST expoe. As do schema app sao infraestrutura da RLS e nunca sao
    -- chamadas de fora. Sem este bloco, rpc('fechar_pedido', ...) tipa os
    -- parametros como undefined e o TypeScript recusa a chamada inteira.
    select json_agg(json_build_object(
      'nome', p.proname,
      -- proargnames indexa TODOS os argumentos (entrada e saida), enquanto
      -- proargtypes so tem os de entrada. Numa funcao "returns table", os dois
      -- desalinham e unnest preenche o resto com nulo - foi assim que o
      -- gerador morreu em "Cannot read properties of null". proallargtypes e
      -- proargmodes sao a leitura correta; para funcoes sem saida nomeada eles
      -- vem nulos, e o coalesce devolve o caso simples.
      'argumentos', coalesce((
        select json_agg(json_build_object(
          'nome', x.nome,
          'tipo', format_type(x.oid, null),
          'temPadrao', x.ordem > (p.pronargs - p.pronargdefaults)
        ) order by x.ordem)
        from (
          select a.nome, a.oid, row_number() over (order by a.posicao) as ordem
          from unnest(
                 p.proargnames,
                 coalesce(p.proallargtypes, p.proargtypes::oid[]),
                 coalesce(p.proargmodes,
                          array_fill('i'::"char",
                                     array[coalesce(array_length(p.proargnames, 1), 0)]))
               ) with ordinality as a(nome, oid, modo, posicao)
          where a.modo in ('i', 'b')
        ) x
      ), '[]'::json),
      -- As colunas de um "returns table". Sem elas o retorno seria "record",
      -- que o mapa traduz para Json - e quem chama perde os nomes dos campos.
      'saidas', coalesce((
        select json_agg(json_build_object(
          'nome', a.nome,
          'tipo', format_type(a.oid, null)
        ) order by a.posicao)
        from unnest(
               p.proargnames,
               coalesce(p.proallargtypes, p.proargtypes::oid[]),
               coalesce(p.proargmodes,
                        array_fill('i'::"char",
                                   array[coalesce(array_length(p.proargnames, 1), 0)]))
             ) with ordinality as a(nome, oid, modo, posicao)
        where a.modo in ('o', 't', 'b')
      ), '[]'::json),
      -- Os tipos de entrada, na ordem, independentes de nome. Uma coluna
      -- calculada do PostgREST se declara "f(tabela)" — sem nome de parametro
      -- —, e entao proargnames vem nulo e a lista de argumentos sai vazia.
      'tiposDeEntrada', coalesce((
        select json_agg(format_type(x.t, null) order by x.o)
        from unnest(coalesce(p.proallargtypes, p.proargtypes::oid[]))
             with ordinality as x(t, o)
      ), '[]'::json),
      'retorno', format_type(p.prorettype, null),
      'retornaConjunto', p.proretset
    ) order by p.proname)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prokind = 'f'
      -- Funcoes de gatilho e as do proprio Postgres nao entram.
      and format_type(p.prorettype, null) <> 'trigger'
      and has_function_privilege('authenticated', p.oid, 'execute')
      -- Fora as que vieram de extensao. pgcrypto e citext instalam dezenas de
      -- funcoes no schema public (crypt, digest, citextin...) que nao sao do
      -- projeto, nunca sao chamadas por rpc() e nem sequer tem nome de
      -- argumento - foi por elas que o gerador quebrou da primeira vez.
      and not exists (
        select 1 from pg_depend d
        where d.objid = p.oid and d.deptype = 'e'
      )
  ), '[]'::json),
  'tabelas', coalesce((
    select json_agg(json_build_object('nome', tabela, 'colunas', colunas) order by tabela)
    from (
      select c.table_name as tabela,
             json_agg(json_build_object(
               'nome', c.column_name,
               'tipo', c.udt_name,
               'nulo', c.is_nullable = 'YES',
               'temPadrao', c.column_default is not null or c.is_identity = 'YES'
             ) order by c.ordinal_position) as colunas
      from information_schema.columns c
      join information_schema.tables t
        on t.table_schema = c.table_schema and t.table_name = c.table_name
      where c.table_schema = 'public' and t.table_type = 'BASE TABLE'
      group by c.table_name
    ) agrupado
  ), '[]'::json)
) as resultado;
`

/**
 * Mapa de tipo do Postgres para tipo do TypeScript.
 *
 * Nota sobre int8/bigint: o PostgREST devolve numero JSON, e todo bigint deste
 * projeto guarda centavos. O limite seguro do JavaScript (9.007.199.254.740.991)
 * equivale a noventa trilhoes de reais, entao nao ha risco pratico de perda.
 */
const TIPOS = {
  uuid: "string", text: "string", citext: "string", varchar: "string", bpchar: "string",
  timestamptz: "string", timestamp: "string", date: "string", time: "string", timetz: "string",
  int2: "number", int4: "number", int8: "number", numeric: "number", float4: "number", float8: "number",
  bool: "boolean",
  json: "Json", jsonb: "Json",
}

function tipoTs(coluna, enums) {
  if (enums.has(coluna.tipo)) return `Database["public"]["Enums"]["${coluna.tipo}"]`
  return TIPOS[coluna.tipo] ?? "unknown"
}

/**
 * O tipo de um argumento ou retorno de funcao.
 *
 * Vem de `format_type`, que escreve por extenso - "timestamp with time zone",
 * "character varying" - enquanto as colunas vem de `udt_name`, que abrevia
 * ("timestamptz", "varchar"). Sao duas grafias do mesmo Postgres, e por isso
 * a tabela abaixo em vez de reaproveitar TIPOS direto.
 */
const TIPOS_DE_FUNCAO = {
  "timestamp with time zone": "string",
  "timestamp without time zone": "string",
  "character varying": "string",
  "double precision": "number",
  text: "string",
  uuid: "string",
  date: "string",
  citext: "string",
  numeric: "number",
  integer: "number",
  bigint: "number",
  smallint: "number",
  real: "number",
  boolean: "boolean",
  json: "Json",
  jsonb: "Json",
  void: "undefined",
  record: "Json",
}

function tipoDeFuncao(nome, enums) {
  // Falhar com nome e sobrenome. Um tipo nulo aqui significa que a consulta de
  // introspeccao leu a funcao errado, e um `unknown` silencioso esconderia isso
  // ate alguem tropecar no TypeScript semanas depois.
  if (!nome) throw new Error("Tipo sem nome vindo do catalogo - a consulta de funcoes esta errada.")
  if (enums.has(nome)) return `Database["public"]["Enums"]["${nome}"]`
  if (nome.endsWith("[]")) {
    const base = nome.slice(0, -2).trim()
    return `${tipoDeFuncao(base, enums)}[]`
  }
  return TIPOS_DE_FUNCAO[nome] ?? "unknown"
}

function consultar() {
  const bruto = execFileSync("psql", ["-d", BANCO, "-t", "-A", "-c", CONSULTA], {
    encoding: "utf8",
    maxBuffer: 32 * 1024 * 1024,
  })
  return JSON.parse(bruto.trim())
}

function gerar({ enums, tabelas, relacoes, funcoes }) {
  const nomesDeEnum = new Set(enums.map((e) => e.nome))
  const nomesDeTabela = new Set(tabelas.map((t) => t.nome))

  /**
   * Colunas calculadas do PostgREST.
   *
   * Uma funcao `f(nome_da_tabela) returns escalar` vira, para o PostgREST, uma
   * coluna virtual daquela tabela: `select=*,f`. O cliente tipado nao adivinha
   * isso sozinho — sem esta parte, pedir a coluna faz o TypeScript responder
   * "column 'f' does not exist" e perder o tipo da consulta inteira.
   *
   * Entram so no Row: nao se escreve numa coluna que o banco calcula.
   */
  const ehColunaCalculada = (f) =>
    (f.tiposDeEntrada ?? []).length === 1 &&
    (f.saidas ?? []).length === 0 &&
    nomesDeTabela.has(f.tiposDeEntrada[0])

  const calculadas = new Map()
  for (const f of funcoes ?? []) {
    if (!ehColunaCalculada(f)) continue

    const tabela = f.tiposDeEntrada[0]
    if (!calculadas.has(tabela)) calculadas.set(tabela, [])
    calculadas.get(tabela).push({ nome: f.nome, tipo: f.retorno })
  }

  const blocosDeTabela = tabelas.map(({ nome, colunas }) => {
    const virtuais = (calculadas.get(nome) ?? []).map(
      // Sempre anulavel: a coluna so vem quando o select a pede, e uma funcao
      // pode devolver null.
      (c) => `          ${c.nome}: ${tipoDeFuncao(c.tipo, nomesDeEnum)} | null`,
    )

    const linha = [
      ...colunas.map(
        (c) => `          ${c.nome}: ${tipoTs(c, nomesDeEnum)}${c.nulo ? " | null" : ""}`,
      ),
      ...virtuais,
    ].join("\n")

    // Insert: opcional quando a coluna tem padrao no banco ou aceita nulo.
    const insert = colunas
      .map((c) => {
        const opcional = c.temPadrao || c.nulo ? "?" : ""
        return `          ${c.nome}${opcional}: ${tipoTs(c, nomesDeEnum)}${c.nulo ? " | null" : ""}`
      })
      .join("\n")

    const update = colunas
      .map((c) => `          ${c.nome}?: ${tipoTs(c, nomesDeEnum)}${c.nulo ? " | null" : ""}`)
      .join("\n")

    // Relationships alimenta o tipo das consultas aninhadas
    // (`select("*, restaurants(name)")`). Sem ele, o postgrest-js nao consegue
    // inferir o formato do resultado e devolve `never`.
    const vinculos = relacoes
      .filter((r) => r.tabela === nome)
      .map(
        (r) =>
          `          {\n            foreignKeyName: "${r.nome}"\n            columns: [${r.colunas
            .map((c) => `"${c}"`)
            .join(", ")}]\n            isOneToOne: ${r.umParaUm === true}\n            referencedRelation: "${r.referencia}"\n            referencedColumns: [${r.colunasReferenciadas
            .map((c) => `"${c}"`)
            .join(", ")}]\n          }`,
      )

    const relationships = vinculos.length > 0 ? `[\n${vinculos.join(",\n")}\n        ]` : "[]"

    return `      ${nome}: {\n        Row: {\n${linha}\n        }\n        Insert: {\n${insert}\n        }\n        Update: {\n${update}\n        }\n        Relationships: ${relationships}\n      }`
  })

  const blocosDeFuncao = (funcoes ?? [])
    .filter((f) => !ehColunaCalculada(f))
    .map((f) => {
      const argumentos = f.argumentos.length
        ? f.argumentos
            .map(
              (a) =>
                `          ${a.nome}${a.temPadrao ? "?" : ""}: ${tipoDeFuncao(a.tipo, nomesDeEnum)}`,
            )
            .join("\n")
        : "          [chave: string]: never"
      // `returns table (a int, b text)` vira { a: number; b: string }. O
      // prorettype dessas funcoes e `record`, que sozinho nao diz nada.
      const base =
        (f.saidas ?? []).length > 0
          ? `{ ${f.saidas
              .map((s) => `${s.nome}: ${tipoDeFuncao(s.tipo, nomesDeEnum)}`)
              .join("; ")} }`
          : tipoDeFuncao(f.retorno, nomesDeEnum)
      const retorno = f.retornaConjunto ? `${base}[]` : base
      return `      ${f.nome}: {\n        Args: {\n${argumentos}\n        }\n        Returns: ${retorno}\n      }`
    })
    .join("\n")

  const blocosDeEnum = enums
    .map((e) => `      ${e.nome}: ${e.valores.map((v) => `"${v}"`).join(" | ")}`)
    .join("\n")

  return `// GERADO AUTOMATICAMENTE - nao edite a mao.
//
// Origem: o schema real do Postgres, lido por scripts/gerar-tipos.mjs.
// Para atualizar depois de uma migracao:  npm run db:tipos
//
// Tabelas: ${tabelas.length}   Enums: ${enums.length}   Funcoes: ${(funcoes ?? []).length}

export type Json = string | number | boolean | null | { [chave: string]: Json | undefined } | Json[]

export interface Database {
  public: {
    Tables: {
${blocosDeTabela.join("\n")}
    }
    Views: Record<string, never>
    Functions: {
${blocosDeFuncao}
    }
    Enums: {
${blocosDeEnum}
    }
    CompositeTypes: Record<string, never>
  }
}

/** Apelido curto, usado pelos clientes em src/lib/supabase. */
export type Banco = Database

type Publico = Database["public"]

export type Tabelas<T extends keyof Publico["Tables"]> = Publico["Tables"][T]["Row"]
export type NovoEm<T extends keyof Publico["Tables"]> = Publico["Tables"][T]["Insert"]
export type AlteracaoEm<T extends keyof Publico["Tables"]> = Publico["Tables"][T]["Update"]
export type Enums<T extends keyof Publico["Enums"]> = Publico["Enums"][T]
`
}

const schema = consultar()
writeFileSync(DESTINO, gerar(schema))
console.log(
  `src/types/banco.ts gerado: ${schema.tabelas.length} tabelas, ${schema.enums.length} enums, ` +
    `${schema.relacoes.length} relacoes, ${(schema.funcoes ?? []).length} funcoes.`,
)
