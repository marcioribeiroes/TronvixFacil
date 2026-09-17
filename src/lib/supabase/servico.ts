import "server-only"

import { createClient } from "@supabase/supabase-js"

import { chaveDeServico, exigirAmbientePublico } from "@/lib/ambiente"
import type { Banco } from "@/types/banco"

/**
 * Cliente com a chave de servico: IGNORA A RLS POR COMPLETO.
 *
 * So existe para os casos em que nao ha usuario na requisicao ou em que a
 * operacao e maior do que qualquer usuario:
 *
 *   - webhook de pagamento (o gateway nao tem sessao)
 *   - criacao de login de funcionario pelo painel do restaurante
 *   - rotinas administrativas e carga de dados
 *
 * Toda chamada por aqui e responsavel por filtrar sozinha o que a RLS filtraria.
 * Na duvida, use criarClienteDoServidor().
 */
export function criarClienteDeServico() {
  const { supabaseUrl } = exigirAmbientePublico()

  return createClient<Banco>(supabaseUrl, chaveDeServico(), {
    auth: { autoRefreshToken: false, persistSession: false },
  })
}
