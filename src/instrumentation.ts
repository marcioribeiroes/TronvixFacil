import type { Instrumentation } from "next"

import { registrarErro } from "@/lib/registrar-erro"

/**
 * Todo erro que o servidor do Next captura vai para o registro de erros
 * (/admin/erros). Sem isto, uma pagina quebrando para um cliente nao deixava
 * rastro em lugar nenhum que alguem olhasse.
 */
export const onRequestError: Instrumentation.onRequestError = async (erro, pedido, contexto) => {
  const e = erro instanceof Error ? erro : new Error(String(erro))
  const digest =
    typeof erro === "object" && erro !== null && "digest" in erro
      ? String((erro as { digest: unknown }).digest)
      : undefined

  await registrarErro({
    origem: "servidor",
    mensagem: e.message,
    pilha: e.stack,
    endereco: pedido.path,
    contexto: {
      metodo: pedido.method,
      digest,
      rota: contexto.routePath,
      tipo: contexto.routeType,
    },
  })
}
