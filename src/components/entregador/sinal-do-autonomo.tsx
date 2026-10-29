"use client"

import { useEffect } from "react"
import { useRouter } from "next/navigation"

import { publicarPosicao } from "@/modules/entregador/corridas"

/**
 * O autonomo disponivel, no navegador, da sinal de vida a cada 45 segundos:
 * manda a posicao e rele a fila.
 *
 * Espelho do relogio de celular/lib/entregador/inicio.dart. A posicao e o que
 * faz a corrida por perto aparecer; reler e o que mostra a corrida quando a
 * espera da loja termina, momento em que nenhuma linha muda no banco.
 *
 * Nao desenha nada. Sem permissao de localizacao, so rele a fila - e a tela
 * de corridas ja explica que sem posicao nao chega corrida.
 */
export function SinalDoAutonomo() {
  const router = useRouter()

  useEffect(() => {
    function sinal() {
      if (!("geolocation" in navigator)) {
        router.refresh()
        return
      }
      navigator.geolocation.getCurrentPosition(
        async (p) => {
          await publicarPosicao(p.coords.latitude, p.coords.longitude)
          router.refresh()
        },
        () => router.refresh(),
        { enableHighAccuracy: true, maximumAge: 30_000, timeout: 15_000 },
      )
    }

    sinal()
    const relogio = window.setInterval(sinal, 45_000)
    return () => window.clearInterval(relogio)
  }, [router])

  return null
}
