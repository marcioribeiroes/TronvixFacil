import { redirect } from "next/navigation"

/** Endereco antigo da barra de baixo. Os pedidos moram em /pedidos. */
export default function PedidosDaConta() {
  redirect("/pedidos")
}
