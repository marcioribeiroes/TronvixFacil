import type { Metadata } from "next"

import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirAdminDaPlataforma } from "@/modules/auth/sessao"

export const metadata: Metadata = { title: "Usuários" }

/**
 * Quem tem conta na plataforma.
 *
 * Nao ha botao de "tornar administrador" aqui, e nao e esquecimento: o gatilho
 * app.guard_platform_role recusa a promocao vinda de sessao de usuario, mesmo
 * de um administrador. Promover e um ato deliberado, feito pela chave de
 * servico:
 *
 *     npm run db:administrador -- pessoa@exemplo.com.br "Nome"
 *
 * Botao na tela e sessao roubada viram, juntos, a plataforma inteira nas maos
 * de outra pessoa.
 */

const PAPEL = {
  platform_admin: "Administrador da plataforma",
  support: "Suporte",
  customer: "Cliente",
  courier: "Entregador",
} as const

export default async function PaginaDeUsuarios() {
  await exigirAdminDaPlataforma()
  const supabase = await criarClienteDoServidor()

  const [{ data: pessoas }, { data: vinculos }, { data: entregadores }] = await Promise.all([
    supabase
      .from("profiles")
      .select("id, full_name, email, phone, platform_role, is_active, created_at")
      .order("created_at", { ascending: false })
      .limit(500),
    supabase
      .from("restaurant_members")
      .select("user_id, role, restaurants(name)")
      .eq("is_active", true)
      .is("deleted_at", null),
    supabase.from("couriers").select("user_id, status").is("deleted_at", null),
  ])

  const lojaDe = new Map<string, string[]>()
  for (const v of vinculos ?? []) {
    const nome = v.restaurants?.name
    if (!nome) continue
    const cargo =
      v.role === "owner" ? "dono" : v.role === "manager" ? "gerente" : "atendente"
    lojaDe.set(v.user_id, [...(lojaDe.get(v.user_id) ?? []), `${nome} (${cargo})`])
  }

  const entregaDe = new Map((entregadores ?? []).map((c) => [c.user_id, c.status]))

  const lista = pessoas ?? []
  const administradores = lista.filter((p) => p.platform_role === "platform_admin")

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">Usuários</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          {lista.length} contas · {administradores.length} com acesso de administrador.
        </p>
      </div>

      <p className="rounded-xl border border-dashed p-4 text-sm text-muted-foreground">
        Promover alguém a administrador não se faz por aqui. O banco recusa a mudança vinda de
        uma sessão de usuário — inclusive da sua. A promoção é por linha de comando, com a
        chave de serviço:{" "}
        <code className="rounded bg-muted px-1.5 py-0.5 text-xs">
          npm run db:administrador -- pessoa@exemplo.com.br &quot;Nome&quot;
        </code>
      </p>

      <ul className="divide-y rounded-xl border bg-card">
        {lista.map((p) => {
          const lojas = lojaDe.get(p.id)
          const entrega = entregaDe.get(p.id)
          return (
            <li key={p.id} className="flex flex-wrap items-center gap-x-3 gap-y-1 p-3 text-sm">
              <span className="min-w-0 flex-1">
                <span className="block truncate font-medium">
                  {p.full_name || "(sem nome)"}
                </span>
                <span className="block truncate text-xs text-muted-foreground">
                  {p.email ?? "—"}
                  {p.phone ? ` · ${p.phone}` : ""}
                </span>
              </span>

              <span className="min-w-0 flex-1 truncate text-xs text-muted-foreground">
                {lojas?.join(", ") ??
                  (entrega
                    ? `entregador (${entrega === "approved" ? "aprovado" : entrega === "pending" ? "esperando" : entrega})`
                    : "—")}
              </span>

              {!p.is_active ? (
                <span className="shrink-0 rounded-md bg-red-100 px-2 py-0.5 text-xs font-semibold text-red-800 dark:bg-red-950 dark:text-red-300">
                  inativo
                </span>
              ) : null}

              <span
                className={`shrink-0 rounded-md px-2 py-0.5 text-xs font-semibold ${
                  p.platform_role === "platform_admin"
                    ? "bg-marca text-white"
                    : "bg-muted text-muted-foreground"
                }`}
              >
                {PAPEL[p.platform_role as keyof typeof PAPEL] ?? p.platform_role}
              </span>
            </li>
          )
        })}
        {lista.length === 0 ? (
          <li className="p-4 text-sm text-muted-foreground">Nenhuma conta ainda.</li>
        ) : null}
      </ul>
    </div>
  )
}
