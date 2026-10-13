"use client"

import { useEffect } from "react"
import { useRouter } from "next/navigation"

import { criarClienteDoNavegador } from "@/lib/supabase/navegador"

/**
 * Mantem o caixa em dia sem ninguem recarregar a pagina.
 *
 * Escuta `payments` (o recebimento feito no celular, em outra aba, por outro
 * atendente) e `orders` (pedido novo a receber, pedido cancelado que sai da
 * lista). Como na fila, nao remenda estado: pede ao servidor a tela de novo, e
 * a RLS continua decidindo o que aparece.
 */
export function CaixaAoVivo({ restauranteId }: { restauranteId: string }) {
  const router = useRouter()

  useEffect(() => {
    const supabase = criarClienteDoNavegador()
    const canal = supabase
      .channel(`caixa:${restauranteId}`)
      // `payments` nao tem restaurant_id para filtrar; a RLS ja so entrega os
      // pagamentos de pedidos que esta pessoa pode ver.
      .on("postgres_changes", { event: "*", schema: "public", table: "payments" }, () =>
        router.refresh(),
      )
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "orders",
          filter: `restaurant_id=eq.${restauranteId}`,
        },
        () => router.refresh(),
      )
      // Fundo e sangria lançados em outra tela ou no celular.
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "cash_movements",
          filter: `restaurant_id=eq.${restauranteId}`,
        },
        () => router.refresh(),
      )
      .subscribe()

    return () => {
      supabase.removeChannel(canal)
    }
  }, [restauranteId, router])

  return null
}
