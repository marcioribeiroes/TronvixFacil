import type { Metadata } from "next"
import QRCode from "qrcode"

import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirGestao } from "@/modules/auth/sessao"

export const metadata: Metadata = { title: "Etiquetas das mesas" }

/**
 * A folha de etiquetas, pronta para o papel.
 *
 * Sem menu, sem barra lateral, sem cabecalho: e uma pagina que existe para
 * sair na impressora. Seis por folha A4, com o codigo escrito por extenso
 * embaixo do QR - camera de celular velho falha, e alguem vai digitar a mao.
 *
 * O QR e gerado no SERVIDOR, como SVG embutido no HTML. Gerar no navegador
 * traria uma biblioteca para o cliente e, pior, deixaria a impressao na mao do
 * tempo de carregamento de um script.
 */
export default async function EtiquetasDasMesas() {
  const { vinculo } = await exigirGestao()
  const supabase = await criarClienteDoServidor()

  const { data: mesas } = await supabase
    .from("restaurant_tables")
    .select("id, label, code")
    .eq("restaurant_id", vinculo.restauranteId)
    .is("deleted_at", null)
    .order("label")

  const site = process.env.NEXT_PUBLIC_URL_DO_SITE ?? "http://localhost:3000"

  const etiquetas = await Promise.all(
    (mesas ?? []).map(async (m) => ({
      rotulo: m.label,
      codigo: m.code,
      // Caminho curto de propósito: quanto menos caracteres, menos denso o QR,
      // e mais fácil a câmera ler numa mesa com luz baixa.
      svg: await QRCode.toString(`${site}/m/${m.code}`, {
        type: "svg",
        margin: 1,
        errorCorrectionLevel: "M",
      }),
    })),
  )

  return (
    <div className="mx-auto max-w-[210mm] p-6 print:p-0">
      <div className="mb-6 flex items-center justify-between print:hidden">
        <div>
          <h1 className="text-xl font-bold">Etiquetas das mesas</h1>
          <p className="text-sm text-muted-foreground">
            {etiquetas.length} etiqueta(s). Imprima, recorte e cole na mesa.
          </p>
        </div>
        <p className="text-sm text-muted-foreground">Ctrl/Cmd + P para imprimir</p>
      </div>

      {etiquetas.length === 0 ? (
        <p className="rounded-xl border border-dashed p-10 text-center text-sm text-muted-foreground">
          Nenhuma mesa cadastrada ainda.
        </p>
      ) : (
        <div className="grid grid-cols-2 gap-4 print:gap-2">
          {etiquetas.map((e) => (
            <div
              key={e.codigo}
              className="flex break-inside-avoid flex-col items-center rounded-lg border border-dashed p-5 text-center"
            >
              <p className="text-xs font-semibold uppercase tracking-wide text-neutral-500">
                {vinculo.nome}
              </p>
              <p className="mt-1 text-2xl font-black">{e.rotulo}</p>

              <div
                className="mt-3 w-40 [&>svg]:h-full [&>svg]:w-full"
                // O SVG vem do gerador de QR, não de dado do usuário: o único
                // conteúdo variável é a URL, que o próprio banco produziu.
                dangerouslySetInnerHTML={{ __html: e.svg }}
              />

              <p className="mt-3 text-sm font-semibold">Aponte a câmera e peça</p>
              <p className="text-[11px] text-neutral-500">
                ou acesse {site.replace(/^https?:\/\//, "")}/m/
                <strong className="font-mono">{e.codigo}</strong>
              </p>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
