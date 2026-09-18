"use client"

import { useState, useTransition } from "react"
import { CircleCheck } from "lucide-react"

import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { salvarPix } from "@/modules/painel/configuracoes"

/**
 * A chave Pix da loja.
 *
 * O texto explica o que a plataforma faz e o que não faz, porque isto é
 * dinheiro: o Pix vai direto para a conta do restaurante, e a confirmação é
 * manual. Descobrir isso depois, com um cliente esperando, seria pior.
 */

const TIPOS = [
  { valor: "cnpj", rotulo: "CNPJ" },
  { valor: "cpf", rotulo: "CPF" },
  { valor: "telefone", rotulo: "Telefone" },
  { valor: "email", rotulo: "E-mail" },
  { valor: "aleatoria", rotulo: "Chave aleatória" },
] as const

export function PixDaLoja({
  pix,
  cidadeDaLoja,
  nomeDaLoja,
}: {
  pix: {
    chave: string | null
    tipo: string | null
    nomeDoRecebedor: string | null
    cidade: string | null
  }
  cidadeDaLoja: string | null
  nomeDaLoja: string
}) {
  const [enviando, iniciar] = useTransition()
  const [erro, setErro] = useState<string | null>(null)
  const [salvo, setSalvo] = useState(false)

  const [chave, setChave] = useState(pix.chave ?? "")
  const [tipo, setTipo] = useState(pix.tipo ?? "cnpj")
  const [nome, setNome] = useState(pix.nomeDoRecebedor ?? nomeDaLoja)
  const [cidade, setCidade] = useState(pix.cidade ?? cidadeDaLoja ?? "")

  function salvar() {
    setErro(null)
    setSalvo(false)
    iniciar(async () => {
      const r = await salvarPix({ chave, tipo, nomeDoRecebedor: nome, cidade })
      if (r.ok) setSalvo(true)
      else setErro(r.erro)
    })
  }

  const ligado = Boolean(pix.chave)

  return (
    <section className="rounded-xl border bg-card p-4">
      <div className="flex flex-wrap items-center gap-2">
        <h2 className="text-sm font-bold uppercase tracking-wide text-muted-foreground">
          Receber por Pix
        </h2>
        {ligado ? (
          <span className="inline-flex items-center gap-1 rounded-md bg-emerald-100 px-2 py-0.5 text-xs font-semibold text-emerald-800 dark:bg-emerald-950 dark:text-emerald-300">
            <CircleCheck className="size-3" aria-hidden="true" />
            ligado
          </span>
        ) : (
          <span className="rounded-md bg-muted px-2 py-0.5 text-xs font-semibold text-muted-foreground">
            desligado
          </span>
        )}
      </div>

      <p className="mt-1 text-xs text-muted-foreground">
        O cliente paga pelo celular e o dinheiro cai <strong>direto na sua conta</strong> — a
        plataforma não passa no meio e não cobra taxa por transação.
      </p>

      <div className="mt-4 grid gap-4 sm:grid-cols-2">
        <div className="space-y-2">
          <Label htmlFor="pix-tipo">Tipo da chave</Label>
          <select
            id="pix-tipo"
            value={tipo}
            onChange={(e) => setTipo(e.target.value)}
            className="h-9 w-full rounded-md border bg-transparent px-3 text-sm shadow-xs"
          >
            {TIPOS.map((t) => (
              <option key={t.valor} value={t.valor}>
                {t.rotulo}
              </option>
            ))}
          </select>
        </div>

        <div className="space-y-2">
          <Label htmlFor="pix-chave">Chave</Label>
          <Input
            id="pix-chave"
            value={chave}
            onChange={(e) => setChave(e.target.value)}
            placeholder="a mesma que você usa no banco"
          />
        </div>

        <div className="space-y-2">
          <Label htmlFor="pix-nome">Nome de quem recebe</Label>
          <Input id="pix-nome" value={nome} onChange={(e) => setNome(e.target.value)} />
          <p className="text-xs text-muted-foreground">
            É o que aparece no banco do cliente na hora de confirmar.
          </p>
        </div>

        <div className="space-y-2">
          <Label htmlFor="pix-cidade">Cidade</Label>
          <Input id="pix-cidade" value={cidade} onChange={(e) => setCidade(e.target.value)} />
        </div>
      </div>

      <div className="mt-4 rounded-lg border border-amber-300 bg-amber-50 p-3 text-xs dark:border-amber-900 dark:bg-amber-950/30">
        <strong>A confirmação é sua.</strong> O pedido pago por Pix fica na coluna{" "}
        <em>Chegou</em>, marcado como “aguardando Pix”. Quando o dinheiro entrar na sua conta,
        toque em <em>Recebi o Pix</em> e ele vai para a cozinha. Enquanto não confirmar, a
        cozinha não começa — é a proteção contra o pedido que ninguém pagou.
      </div>

      {erro ? <p className="mt-3 text-sm text-destructive">{erro}</p> : null}
      {salvo ? <p className="mt-3 text-sm text-emerald-600">Salvo.</p> : null}

      <Button className="mt-4" onClick={salvar} disabled={enviando}>
        {enviando ? "Salvando…" : ligado ? "Salvar" : "Ligar o Pix"}
      </Button>
    </section>
  )
}
