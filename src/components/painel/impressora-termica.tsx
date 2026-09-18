"use client"

import { useEffect, useState } from "react"
import { Printer, Usb } from "lucide-react"

import { Button } from "@/components/ui/button"
import {
  desligarImpressora,
  escolherImpressora,
  impressoraLigada,
  reconectarImpressora,
  temImpressoraDireta,
} from "@/lib/impressora"

/**
 * Ligar a impressora térmica desta máquina.
 *
 * O navegador exige um clique para autorizar a porta, e exige de novo a cada
 * abertura do navegador — é proteção contra páginas que saem lendo aparelhos
 * sozinhas, e não tem como contornar. O que dá para evitar é a janela de
 * escolha: uma vez autorizada, a porta volta sem perguntar.
 *
 * Onde não há Web Serial — Firefox, Safari, celular — este botão nem aparece,
 * e a impressão continua pelo driver do sistema.
 */
export function ImpressoraTermica({ colunas }: { colunas: 32 | 48 }) {
  const [existe, setExiste] = useState(false)
  const [ligada, setLigada] = useState(false)
  const [tentando, setTentando] = useState(false)

  useEffect(() => {
    if (!temImpressoraDireta()) return
    // Adiado para depois do quadro: setState direto dentro do efeito encadeia
    // renderizações, e o lint pega.
    queueMicrotask(() => setExiste(true))

    // Porta já autorizada antes volta sozinha. Sem isto, o balcão teria de
    // escolher a impressora na lista toda manhã.
    void reconectarImpressora().then((ok) => {
      if (ok) setLigada(true)
    })
  }, [])

  if (!existe) return null

  return (
    <Button
      size="sm"
      variant={ligada ? "outline" : "ghost"}
      disabled={tentando}
      title={
        ligada
          ? `Comanda saindo direto na térmica, papel de ${colunas === 32 ? "58" : "80"}mm`
          : "Ligar a impressora térmica desta máquina"
      }
      onClick={async () => {
        setTentando(true)
        if (ligada) {
          await desligarImpressora()
          setLigada(false)
        } else {
          const ok = await escolherImpressora()
          setLigada(ok && impressoraLigada())
        }
        setTentando(false)
      }}
    >
      {ligada ? (
        <>
          <Printer className="size-4" aria-hidden="true" />
          Térmica ligada
        </>
      ) : (
        <>
          <Usb className="size-4" aria-hidden="true" />
          Ligar térmica
        </>
      )}
    </Button>
  )
}
