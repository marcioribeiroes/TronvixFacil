"use client"

import { useRouter } from "next/navigation"
import { useState, useTransition } from "react"
import { Loader2 } from "lucide-react"

import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { buscarCep, cepCompleto, formatarCep } from "@/lib/cep"
import { formatarTelefone } from "@/lib/telefone"
import { cadastrarEstabelecimento } from "@/modules/parceiro/cadastro"

/**
 * O cadastro do estabelecimento, pela propria loja.
 *
 * Pede o minimo para a plataforma conseguir analisar e ligar de volta: nome,
 * telefone e endereco. Cardapio, taxa de entrega e horario ficam para o painel
 * - sao o trabalho do dia seguinte, e exigi-los aqui faria metade das pessoas
 * abandonar o formulario no meio.
 *
 * O CEP preenche rua, bairro e cidade. Quando nao acha, nao reclama: CEP novo e
 * CEP de zona rural existem, e travar o cadastro por causa deles seria pior do
 * que nao ter a busca.
 */

const ESTADOS = [
  "AC", "AL", "AP", "AM", "BA", "CE", "DF", "ES", "GO", "MA", "MT", "MS", "MG",
  "PA", "PB", "PR", "PE", "PI", "RJ", "RN", "RS", "RO", "RR", "SC", "SP", "SE", "TO",
]

export function FormularioDeEstabelecimento() {
  const router = useRouter()
  const [enviando, iniciar] = useTransition()
  const [erro, setErro] = useState<string | null>(null)
  const [campoComErro, setCampoComErro] = useState<string | null>(null)
  const [buscandoCep, setBuscandoCep] = useState(false)

  const [nome, setNome] = useState("")
  const [telefone, setTelefone] = useState("")
  const [documento, setDocumento] = useState("")
  const [email, setEmail] = useState("")
  const [descricao, setDescricao] = useState("")

  const [cep, setCep] = useState("")
  const [rua, setRua] = useState("")
  const [numero, setNumero] = useState("")
  const [complemento, setComplemento] = useState("")
  const [bairro, setBairro] = useState("")
  const [cidade, setCidade] = useState("")
  const [estado, setEstado] = useState("GO")

  async function aoMudarCep(valor: string) {
    setCep(formatarCep(valor))
    if (!cepCompleto(valor)) return

    setBuscandoCep(true)
    const achado = await buscarCep(valor)
    setBuscandoCep(false)
    if (!achado) return

    // Nao sobrescreve o que a pessoa ja digitou: quem corrigiu a rua a mao
    // tinha um motivo, e o CEP nao sabe qual era.
    if (achado.rua) setRua((atual) => atual || achado.rua)
    if (achado.bairro) setBairro((atual) => atual || achado.bairro)
    setCidade((atual) => atual || achado.cidade)
    setEstado(achado.estado)
  }

  function enviar() {
    setErro(null)
    setCampoComErro(null)
    iniciar(async () => {
      const resultado = await cadastrarEstabelecimento({
        nome, telefone, documento, descricao, email,
        cep, rua, numero, complemento, bairro, cidade, estado,
      })
      if (resultado.ok) {
        router.push(`/cadastrar-restaurante/enviado?loja=${resultado.slug}`)
      } else {
        setErro(resultado.erro)
        setCampoComErro(resultado.campo ?? null)
      }
    })
  }

  const ruim = (campo: string) => campoComErro === campo

  return (
    <form
      className="space-y-8"
      noValidate
      onSubmit={(e) => {
        e.preventDefault()
        enviar()
      }}
    >
      <section className="space-y-4">
        <h2 className="text-sm font-bold uppercase tracking-wide text-muted-foreground">
          O estabelecimento
        </h2>

        <div className="grid gap-4 sm:grid-cols-2">
          <div className="space-y-2 sm:col-span-2">
            <Label htmlFor="nome">Nome *</Label>
            <Input
              id="nome"
              value={nome}
              onChange={(e) => setNome(e.target.value)}
              placeholder="Pizzaria da Esquina"
              aria-invalid={ruim("nome")}
              required
            />
            <p className="text-xs text-muted-foreground">
              É como o cliente vai ver na vitrine.
            </p>
          </div>

          <div className="space-y-2">
            <Label htmlFor="telefone">Telefone *</Label>
            <Input
              id="telefone"
              inputMode="tel"
              value={telefone}
              onChange={(e) => setTelefone(e.target.value)}
              onBlur={() => setTelefone(formatarTelefone(telefone) || telefone)}
              placeholder="(62) 3241-0000"
              aria-invalid={ruim("telefone")}
              required
            />
          </div>

          <div className="space-y-2">
            <Label htmlFor="documento">CNPJ</Label>
            <Input
              id="documento"
              inputMode="numeric"
              value={documento}
              onChange={(e) => setDocumento(e.target.value)}
              placeholder="00.000.000/0000-00"
            />
          </div>

          <div className="space-y-2 sm:col-span-2">
            <Label htmlFor="email-da-loja">E-mail do estabelecimento</Label>
            <Input
              id="email-da-loja"
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="contato@sualoja.com.br"
            />
          </div>

          <div className="space-y-2 sm:col-span-2">
            <Label htmlFor="descricao">Uma linha sobre a loja</Label>
            <Textarea
              id="descricao"
              rows={2}
              value={descricao}
              onChange={(e) => setDescricao(e.target.value)}
              placeholder="Pizza em forno a lenha, massa fina, desde 2014."
            />
          </div>
        </div>
      </section>

      <section className="space-y-4">
        <h2 className="text-sm font-bold uppercase tracking-wide text-muted-foreground">
          Onde fica
        </h2>
        <p className="-mt-2 text-xs text-muted-foreground">
          É daqui que o entregador retira o pedido.
        </p>

        <div className="grid gap-4 sm:grid-cols-6">
          <div className="space-y-2 sm:col-span-2">
            <Label htmlFor="cep">CEP</Label>
            <div className="relative">
              <Input
                id="cep"
                inputMode="numeric"
                value={cep}
                onChange={(e) => aoMudarCep(e.target.value)}
                placeholder="74230-035"
              />
              {buscandoCep ? (
                <Loader2
                  className="absolute right-3 top-1/2 size-4 -translate-y-1/2 animate-spin text-muted-foreground"
                  aria-hidden="true"
                />
              ) : null}
            </div>
          </div>

          <div className="space-y-2 sm:col-span-4">
            <Label htmlFor="rua">Rua *</Label>
            <Input
              id="rua"
              value={rua}
              onChange={(e) => setRua(e.target.value)}
              aria-invalid={ruim("rua")}
              required
            />
          </div>

          <div className="space-y-2 sm:col-span-2">
            <Label htmlFor="numero">Número *</Label>
            <Input
              id="numero"
              value={numero}
              onChange={(e) => setNumero(e.target.value)}
              aria-invalid={ruim("numero")}
              required
            />
          </div>

          <div className="space-y-2 sm:col-span-4">
            <Label htmlFor="complemento">Complemento</Label>
            <Input
              id="complemento"
              value={complemento}
              onChange={(e) => setComplemento(e.target.value)}
              placeholder="Loja 2, esquina com a T-10"
            />
          </div>

          <div className="space-y-2 sm:col-span-3">
            <Label htmlFor="bairro">Bairro *</Label>
            <Input
              id="bairro"
              value={bairro}
              onChange={(e) => setBairro(e.target.value)}
              aria-invalid={ruim("bairro")}
              required
            />
          </div>

          <div className="space-y-2 sm:col-span-2">
            <Label htmlFor="cidade">Cidade *</Label>
            <Input
              id="cidade"
              value={cidade}
              onChange={(e) => setCidade(e.target.value)}
              aria-invalid={ruim("cidade")}
              required
            />
          </div>

          <div className="space-y-2 sm:col-span-1">
            <Label htmlFor="estado">UF</Label>
            <select
              id="estado"
              value={estado}
              onChange={(e) => setEstado(e.target.value)}
              className="h-9 w-full rounded-md border bg-transparent px-3 text-sm shadow-xs"
            >
              {ESTADOS.map((uf) => (
                <option key={uf} value={uf}>
                  {uf}
                </option>
              ))}
            </select>
          </div>
        </div>
      </section>

      {erro ? (
        <p className="rounded-lg border border-destructive/40 bg-destructive/5 p-3 text-sm text-destructive">
          {erro}
        </p>
      ) : null}

      <div className="space-y-3">
        <Button type="submit" size="lg" className="w-full" disabled={enviando}>
          {enviando ? "Enviando…" : "Enviar para análise"}
        </Button>
        <p className="text-center text-xs text-muted-foreground">
          A plataforma analisa e libera. Enquanto isso a loja não aparece na vitrine — mas você
          já entra no painel e monta o cardápio.
        </p>
      </div>
    </form>
  )
}
