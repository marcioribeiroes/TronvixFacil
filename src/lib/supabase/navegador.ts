"use client"

import { createBrowserClient } from "@supabase/ssr"

import { exigirAmbientePublico } from "@/lib/ambiente"
import type { Banco } from "@/types/banco"

/**
 * Cliente Supabase do navegador.
 *
 * Usa a chave anonima e carrega o JWT do usuario logado, entao toda consulta
 * feita por aqui passa pela RLS. Serve para leitura reativa e para o Realtime
 * (o Kanban de pedidos do restaurante). Escrita de regra de negocio nao passa
 * por aqui: vai por Server Action.
 */
export function criarClienteDoNavegador() {
  const { supabaseUrl, supabaseAnonKey } = exigirAmbientePublico()
  return createBrowserClient<Banco>(supabaseUrl, supabaseAnonKey)
}
