"use client"

import { useRouter } from "next/navigation"
import { useRef, useState, useTransition } from "react"
import { Camera, Check, Loader2 } from "lucide-react"

import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { reduzirImagem } from "@/lib/imagem"
import { criarClienteDoNavegador } from "@/lib/supabase/navegador"
import { cadastrarAutonomo } from "@/modules/entregador/cadastro"

/**
 * O cadastro do entregador autonomo, no navegador.
 *
 * Espelho de celular/lib/entregador/cadastro_autonomo.dart. As fotos sobem
 * direto do aparelho para o balde privado, na pasta da propria pessoa - a
 * politica do balde nao deixa gravar em outra -, e o formulario manda so os
 * caminhos. Quem confere tudo de novo e o banco.
 */

const VEICULOS = [
  ["motorcycle", "Moto"],
  ["car", "Carro"],
  ["bicycle", "Bicicleta"],
  ["foot", "A pé"],
] as const

type Documento = "cnh" | "veiculo" | "selfie"

const escolha = (marcado: boolean) =>
  `rounded-xl border-2 bg-card text-center text-sm font-semibold transition-colors ${
    marcado ? "border-marca bg-marca-suave" : "border-transparent ring-1 ring-border hover:bg-muted"
  }`

function FotoDoDocumento({
  rotulo,
  dica,
  usuarioId,
  tipo,
  caminho,
  aoEnviar,
}: {
  rotulo: string
  dica: string
  usuarioId: string
  tipo: Documento
  caminho: string
  aoEnviar: (caminho: string) => void
}) {
  const campo = useRef<HTMLInputElement>(null)
  const [enviando, setEnviando] = useState(false)
  const [erro, setErro] = useState<string | null>(null)

  async function escolher(arquivo: File) {
    setErro(null)
    setEnviando(true)
    try {
      // 1600 px: o bastante para ler o numero da CNH, sem subir 8 MB de foto.
      const menor = await reduzirImagem(arquivo, { maiorLado: 1600, qualidade: 0.85 })
      const destino = `${usuarioId}/${tipo}-${Date.now()}.jpg`
      const { error } = await criarClienteDoNavegador()
        .storage.from("documentos-entregador")
        .upload(destino, menor, { contentType: "image/jpeg" })
      if (error) throw new Error(error.message)
      aoEnviar(destino)
    } catch {
      setErro("Não consegui enviar esta foto. Tente outra, em JPG ou PNG.")
    } finally {
      setEnviando(false)
      if (campo.current) campo.current.value = ""
    }
  }

  return (
    <div className="space-y-1">
      <button
        type="button"
        onClick={() => campo.current?.click()}
        disabled={enviando}
        className={`flex w-full items-center gap-3 rounded-xl border p-3 text-left transition-colors hover:bg-muted ${caminho ? "border-status-pronto" : ""}`}
      >
        <span
          className={`grid size-10 shrink-0 place-items-center rounded-lg ${caminho ? "bg-status-pronto text-white" : "bg-muted"}`}
        >
          {enviando ? (
            <Loader2 className="size-5 animate-spin" aria-hidden="true" />
          ) : caminho ? (
            <Check className="size-5" aria-hidden="true" />
          ) : (
            <Camera className="size-5 text-muted-foreground" aria-hidden="true" />
          )}
        </span>
        <span className="min-w-0">
          <span className="block font-semibold">{rotulo}</span>
          <span className="block text-xs text-muted-foreground">
            {caminho ? "Enviada. Toque para trocar." : dica}
          </span>
        </span>
      </button>
      <input
        ref={campo}
        type="file"
        accept="image/*"
        capture={tipo === "selfie" ? "user" : "environment"}
        className="hidden"
        onChange={(e) => {
          const arquivo = e.target.files?.[0]
          if (arquivo) void escolher(arquivo)
        }}
      />
      {erro ? <p className="text-xs font-medium text-destructive">{erro}</p> : null}
    </div>
  )
}

export function FormularioDoAutonomo({
  usuarioId,
  cidades,
}: {
  usuarioId: string
  cidades: string[]
}) {
  const router = useRouter()
  const [enviando, iniciar] = useTransition()
  const [erro, setErro] = useState<string | null>(null)

  const [cpf, setCpf] = useState("")
  const [nascimento, setNascimento] = useState("")
  const [cidade, setCidade] = useState(cidades[0] ?? "")
  const [veiculo, setVeiculo] = useState<string>("motorcycle")
  const [placa, setPlaca] = useState("")
  const [modelo, setModelo] = useState("")
  const [cor, setCor] = useState("")
  const [pix, setPix] = useState("")
  const [documentos, setDocumentos] = useState<Record<Documento, string>>({
    cnh: "",
    veiculo: "",
    selfie: "",
  })

  const motorizado = veiculo === "motorcycle" || veiculo === "car"

  function enviar() {
    setErro(null)
    iniciar(async () => {
      const r = await cadastrarAutonomo({
        cpf,
        nascimento,
        veiculo: veiculo as (typeof VEICULOS)[number][0],
        placa,
        modelo,
        cor,
        cidade,
        pix,
        cnh: documentos.cnh,
        documentoDoVeiculo: motorizado ? documentos.veiculo : "",
        selfie: documentos.selfie,
      })
      if (r.ok) {
        router.push("/entregas")
        router.refresh()
      } else {
        setErro(r.erro)
      }
    })
  }

  return (
    <form
      className="space-y-6"
      noValidate
      onSubmit={(e) => {
        e.preventDefault()
        enviar()
      }}
    >
      <fieldset className="grid gap-4 sm:grid-cols-2">
        <legend className="mb-2 font-bold">Seus dados</legend>
        <div className="space-y-2">
          <Label htmlFor="cpf">CPF</Label>
          <Input
            id="cpf"
            inputMode="numeric"
            value={cpf}
            onChange={(e) => setCpf(e.target.value)}
            placeholder="000.000.000-00"
            maxLength={14}
          />
        </div>
        <div className="space-y-2">
          <Label htmlFor="nascimento">Data de nascimento</Label>
          <Input
            id="nascimento"
            type="date"
            value={nascimento}
            onChange={(e) => setNascimento(e.target.value)}
          />
        </div>
        <div className="space-y-2 sm:col-span-2">
          <Label htmlFor="cidade">Cidade onde vai entregar</Label>
          <select
            id="cidade"
            value={cidade}
            onChange={(e) => setCidade(e.target.value)}
            className="h-9 w-full rounded-lg border border-input bg-transparent px-2.5 text-sm"
          >
            {cidades.map((c) => (
              <option key={c} value={c}>
                {c}
              </option>
            ))}
          </select>
        </div>
      </fieldset>

      <fieldset className="space-y-3">
        <legend className="mb-2 font-bold">Como você entrega</legend>
        <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
          {VEICULOS.map(([valor, rotulo]) => (
            <button
              key={valor}
              type="button"
              aria-pressed={veiculo === valor}
              onClick={() => setVeiculo(valor)}
              className={`px-3 py-3 ${escolha(veiculo === valor)}`}
            >
              {rotulo}
            </button>
          ))}
        </div>
        {motorizado ? (
          <div className="grid gap-3 sm:grid-cols-3">
            <div className="space-y-2">
              <Label htmlFor="placa">Placa</Label>
              <Input
                id="placa"
                value={placa}
                onChange={(e) => setPlaca(e.target.value.toUpperCase())}
                placeholder="ABC1D23"
                maxLength={8}
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="modelo">Modelo</Label>
              <Input
                id="modelo"
                value={modelo}
                onChange={(e) => setModelo(e.target.value)}
                placeholder="CG 160"
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="cor">Cor</Label>
              <Input
                id="cor"
                value={cor}
                onChange={(e) => setCor(e.target.value)}
                placeholder="Vermelha"
              />
            </div>
          </div>
        ) : null}
      </fieldset>

      <fieldset className="space-y-3">
        <legend className="mb-1 font-bold">Documentos</legend>
        <p className="text-xs text-muted-foreground">
          As fotos ficam guardadas em sigilo: só você e a equipe que aprova o cadastro veem.
        </p>
        <FotoDoDocumento
          rotulo={motorizado ? "CNH" : "Documento com foto"}
          dica={motorizado ? "Foto da CNH aberta, legível" : "RG ou CNH, legível"}
          usuarioId={usuarioId}
          tipo="cnh"
          caminho={documentos.cnh}
          aoEnviar={(c) => setDocumentos((d) => ({ ...d, cnh: c }))}
        />
        {motorizado ? (
          <FotoDoDocumento
            rotulo="Documento do veículo (CRLV)"
            dica="Foto do documento da moto ou do carro"
            usuarioId={usuarioId}
            tipo="veiculo"
            caminho={documentos.veiculo}
            aoEnviar={(c) => setDocumentos((d) => ({ ...d, veiculo: c }))}
          />
        ) : null}
        <FotoDoDocumento
          rotulo="Selfie segurando o documento"
          dica="Seu rosto e o documento aparecendo juntos"
          usuarioId={usuarioId}
          tipo="selfie"
          caminho={documentos.selfie}
          aoEnviar={(c) => setDocumentos((d) => ({ ...d, selfie: c }))}
        />
      </fieldset>

      <div className="space-y-2">
        <Label htmlFor="pix">Chave Pix para receber</Label>
        <Input
          id="pix"
          value={pix}
          onChange={(e) => setPix(e.target.value)}
          placeholder="CPF, celular, e-mail ou chave aleatória"
        />
      </div>

      {erro ? (
        <p role="alert" className="text-sm font-medium text-destructive">
          {erro}
        </p>
      ) : null}

      <Button type="submit" size="lg" className="w-full" disabled={enviando}>
        {enviando ? <Loader2 className="size-4 animate-spin" aria-hidden="true" /> : null}
        {enviando ? "Enviando…" : "Enviar cadastro para análise"}
      </Button>
    </form>
  )
}
