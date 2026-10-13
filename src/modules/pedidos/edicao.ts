import { z } from "zod"

/**
 * Quando um pedido ainda pode mudar, e o formato de um item novo.
 *
 * Espelho de `app.conferir_pedido_editavel`: aqui serve para a tela saber se
 * oferece o botao; quem decide e o banco. Mudar um lado exige mudar o outro.
 */

const SITUACOES_EDITAVEIS = ["received", "confirmed", "preparing", "ready"]

export function pedidoEditavel(
  situacao: string,
  pagamento: { timing: string; status: string } | undefined | null,
): boolean {
  if (!SITUACOES_EDITAVEIS.includes(situacao)) return false
  // Pago pelo site, ou ja recebido no caixa: o valor foi acertado.
  if (pagamento?.timing === "online") return false
  if (pagamento?.status === "paid") return false
  return true
}

export const schemaDoItemNovo = z.object({
  produto_id: z.uuid(),
  quantidade: z.number().int().min(1).max(99),
  observacao: z.string().trim().max(200),
  // Id solto e uma unidade (como o site escolhe); com quantidade, o
  // aplicativo pede 2x bacon. O banco aceita os dois.
  adicionais: z
    .array(z.union([z.uuid(), z.object({ id: z.uuid(), quantidade: z.number().int().min(1).max(20) })]))
    .max(50),
})

export type ItemNovo = z.infer<typeof schemaDoItemNovo>

export const schemaDaEdicao = z.object({
  itens: z.array(z.object({ id: z.uuid(), quantidade: z.number().int().min(0).max(99) })),
  novos: z.array(schemaDoItemNovo).max(50),
})

export type EdicaoDoPedido = z.infer<typeof schemaDaEdicao>

/** Pedido lancado pela loja. Espelho do que `lancar_pedido` aceita. */
export const schemaDoLancamento = z
  .object({
    tipo: z.enum(["pickup", "dine_in", "delivery"]),
    cliente: z.string().trim().max(80),
    telefone: z.string().trim().max(20),
    mesa_id: z.uuid().nullable(),
    mesa: z.string().trim().max(40),
    endereco: z.object({
      rua: z.string().trim().max(120),
      numero: z.string().trim().max(20),
      complemento: z.string().trim().max(80),
      bairro: z.string().trim().max(80),
      cidade: z.string().trim().max(80),
      cep: z.string().trim().max(10),
    }),
    forma: z.enum(["cash", "debit_card", "credit_card", "pix", "meal_voucher"]),
    troco_para_cents: z.number().int().positive().nullable(),
    receber_agora: z.boolean(),
    observacao: z.string().trim().max(500),
    itens: z.array(schemaDoItemNovo).min(1, "Escolha ao menos um item.").max(50),
  })
  .superRefine((d, ctx) => {
    if (d.tipo === "dine_in" && !d.mesa_id && d.mesa === "") {
      ctx.addIssue({ code: "custom", message: "Diga qual é a mesa." })
    }
    if (d.tipo === "delivery") {
      if (!d.endereco.rua || !d.endereco.numero || !d.endereco.bairro) {
        ctx.addIssue({ code: "custom", message: "Entrega precisa de rua, número e bairro." })
      }
      if (d.telefone.replace(/\D/g, "").length < 10) {
        ctx.addIssue({ code: "custom", message: "Entrega precisa do telefone do cliente, com DDD." })
      }
    }
  })

export type Lancamento = z.infer<typeof schemaDoLancamento>
