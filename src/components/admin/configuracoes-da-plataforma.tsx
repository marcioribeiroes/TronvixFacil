"use client"

import { useState, useTransition } from "react"

import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { formatarValor } from "@/lib/dinheiro"
import { salvarConfiguracaoDaPlataforma } from "@/modules/admin/plataforma"

/**
 * A configuracao da plataforma inteira.
 *
 * Dois campos daqui tem efeito imediato e amplo, e por isso vem separados e
 * com o aviso do que fazem: fechar cadastros e o modo manutencao. Um deles
 * derruba a loja de todo mundo; e justo que quem clica saiba disso antes.
 */
export function ConfiguracoesDaPlataforma({
  configuracao,
}: {
  configuracao: {
    brand_name: string
    support_email: string | null
    support_phone: string | null
    default_commission_bps: number
    default_courier_fee_cents: number
    min_order_cents: number
    allow_new_signups: boolean
    maintenance_mode: boolean
  }
}) {
  const [enviando, iniciar] = useTransition()
  const [erro, setErro] = useState<string | null>(null)
  const [salvo, setSalvo] = useState(false)

  const [nomeDaMarca, setNomeDaMarca] = useState(configuracao.brand_name)
  const [emailDeSuporte, setEmailDeSuporte] = useState(configuracao.support_email ?? "")
  const [telefoneDeSuporte, setTelefoneDeSuporte] = useState(configuracao.support_phone ?? "")
  const [comissaoPadrao, setComissaoPadrao] = useState(
    (configuracao.default_commission_bps / 100).toString().replace(".", ","),
  )
  const [taxaDoEntregador, setTaxaDoEntregador] = useState(
    formatarValor(configuracao.default_courier_fee_cents),
  )
  const [pedidoMinimo, setPedidoMinimo] = useState(formatarValor(configuracao.min_order_cents))
  const [aceitaNovosCadastros, setAceitaNovosCadastros] = useState(
    configuracao.allow_new_signups,
  )
  const [emManutencao, setEmManutencao] = useState(configuracao.maintenance_mode)

  function salvar() {
    setErro(null)
    setSalvo(false)
    iniciar(async () => {
      const resultado = await salvarConfiguracaoDaPlataforma({
        nomeDaMarca,
        emailDeSuporte,
        telefoneDeSuporte,
        comissaoPadrao,
        taxaDoEntregador,
        pedidoMinimo,
        aceitaNovosCadastros,
        emManutencao,
      })
      if (resultado.ok) setSalvo(true)
      else setErro(resultado.erro)
    })
  }

  return (
    <div className="space-y-6">
      <section className="rounded-xl border bg-card p-4">
        <h2 className="text-sm font-bold uppercase tracking-wide text-muted-foreground">
          Marca e suporte
        </h2>
        <div className="mt-3 grid gap-4 sm:grid-cols-2">
          <div className="grid gap-1.5">
            <Label htmlFor="marca">Nome da marca</Label>
            <Input id="marca" value={nomeDaMarca} onChange={(e) => setNomeDaMarca(e.target.value)} />
          </div>
          <div className="grid gap-1.5">
            <Label htmlFor="suporte-email">E-mail de suporte</Label>
            <Input
              id="suporte-email"
              type="email"
              value={emailDeSuporte}
              onChange={(e) => setEmailDeSuporte(e.target.value)}
              placeholder="suporte@exemplo.com.br"
            />
          </div>
          <div className="grid gap-1.5">
            <Label htmlFor="suporte-telefone">Telefone de suporte</Label>
            <Input
              id="suporte-telefone"
              value={telefoneDeSuporte}
              onChange={(e) => setTelefoneDeSuporte(e.target.value)}
              placeholder="(62) 90000-0000"
            />
          </div>
        </div>
      </section>

      <section className="rounded-xl border bg-card p-4">
        <h2 className="text-sm font-bold uppercase tracking-wide text-muted-foreground">
          Padrões de um cadastro novo
        </h2>
        <p className="mt-1 text-xs text-muted-foreground">
          Valem para quem se cadastrar daqui em diante. Loja já cadastrada mantém o que tem.
        </p>
        <div className="mt-3 grid gap-4 sm:grid-cols-3">
          <div className="grid gap-1.5">
            <Label htmlFor="comissao">Comissão (%)</Label>
            <Input
              id="comissao"
              inputMode="decimal"
              value={comissaoPadrao}
              onChange={(e) => setComissaoPadrao(e.target.value)}
            />
          </div>
          <div className="grid gap-1.5">
            <Label htmlFor="taxa">Repasse ao entregador (R$)</Label>
            <Input
              id="taxa"
              inputMode="decimal"
              value={taxaDoEntregador}
              onChange={(e) => setTaxaDoEntregador(e.target.value)}
            />
          </div>
          <div className="grid gap-1.5">
            <Label htmlFor="minimo">Pedido mínimo (R$)</Label>
            <Input
              id="minimo"
              inputMode="decimal"
              value={pedidoMinimo}
              onChange={(e) => setPedidoMinimo(e.target.value)}
            />
          </div>
        </div>
      </section>

      <section className="rounded-xl border bg-card p-4">
        <h2 className="text-sm font-bold uppercase tracking-wide text-muted-foreground">
          Chaves gerais
        </h2>
        <div className="mt-3 space-y-3">
          <label className="flex items-start gap-3 rounded-lg border p-3">
            <input
              type="checkbox"
              className="mt-0.5 size-4"
              checked={aceitaNovosCadastros}
              onChange={(e) => setAceitaNovosCadastros(e.target.checked)}
            />
            <span className="text-sm">
              <span className="block font-semibold">Aceitar novos cadastros</span>
              <span className="block text-xs text-muted-foreground">
                Desligado, a tela de criar conta recusa. Quem já tem conta continua entrando.
              </span>
            </span>
          </label>

          <label className="flex items-start gap-3 rounded-lg border border-amber-300 bg-amber-50 p-3 dark:border-amber-900 dark:bg-amber-950/30">
            <input
              type="checkbox"
              className="mt-0.5 size-4"
              checked={emManutencao}
              onChange={(e) => setEmManutencao(e.target.checked)}
            />
            <span className="text-sm">
              <span className="block font-semibold">Modo manutenção</span>
              <span className="block text-xs text-muted-foreground">
                Tira a plataforma do ar para todo mundo: nenhuma loja vende enquanto estiver
                ligado. É para migração de banco, não para fim de expediente.
              </span>
            </span>
          </label>
        </div>
      </section>

      {erro ? <p className="text-sm text-destructive">{erro}</p> : null}
      {salvo ? <p className="text-sm text-emerald-600">Salvo.</p> : null}

      <Button onClick={salvar} disabled={enviando}>
        {enviando ? "Salvando…" : "Salvar"}
      </Button>
    </div>
  )
}
