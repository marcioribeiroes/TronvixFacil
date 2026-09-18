import type { Metadata } from "next"
import Link from "next/link"
import { ShoppingBasket } from "lucide-react"

import { FecharPedido } from "@/components/cliente/fechar-pedido"
import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirUsuario } from "@/modules/auth/sessao"
import { mesaAtual } from "@/modules/cliente/mesa"

export const metadata: Metadata = { title: "Seu pedido" }

export default async function PaginaDoCarrinho() {
  const contexto = await exigirUsuario("/carrinho")
  const supabase = await criarClienteDoServidor()
  const mesa = await mesaAtual()

  const { data: carrinho } = await supabase
    .from("carts")
    .select(
      "id, restaurant_id, restaurants(id, name, logo_url, is_open, delivery_fee_cents, free_delivery_above_cents, min_order_cents, aceita_pix), cart_items(id, quantity, notes, products(id, name, price_cents, promo_price_cents, promo_starts_at, promo_ends_at), cart_item_addons(quantity, addons(id, name, price_cents)))",
    )
    .eq("user_id", contexto.id)
    .maybeSingle()

  if (!carrinho || !carrinho.restaurants || carrinho.cart_items.length === 0) {
    return (
      <div className="mx-auto max-w-2xl px-4 py-16 text-center">
        <ShoppingBasket className="mx-auto size-10 text-muted-foreground" aria-hidden="true" />
        <h1 className="mt-4 text-xl font-bold">Carrinho vazio</h1>
        <p className="mt-1 text-muted-foreground">
          Escolha um restaurante e monte seu pedido.
        </p>
        <Link
          href="/"
          className="mt-6 inline-flex h-10 items-center rounded-lg bg-marca px-5 text-sm font-semibold text-marca-contraste"
        >
          Ver restaurantes
        </Link>
      </div>
    )
  }

  const [{ data: enderecos }, { data: formas }] = await Promise.all([
    supabase
      .from("addresses")
      .select("id, label, street, number, complement, district, city, state, is_default")
      .eq("user_id", contexto.id)
      .is("deleted_at", null)
      .order("is_default", { ascending: false }),
    supabase
      .from("restaurant_payment_methods")
      .select("method, timing")
      .eq("restaurant_id", carrinho.restaurant_id)
      .eq("is_active", true),
  ])

  const loja = carrinho.restaurants

  // Pix so entra na lista quando a loja tem chave cadastrada. A tabela de
  // formas diz o que o balcao marcou; `aceita_pix` diz o que ele consegue
  // receber. Sem a chave, `fechar_pedido` recusa — e o ultimo toque, depois de
  // escolher o que comer e como pagar, e o pior lugar para dar essa noticia.
  const aceitas = (formas ?? []).filter(
    (f) => f.method !== "pix" || loja.aceita_pix === true,
  )

  return (
    <div className="mx-auto max-w-2xl px-4 py-6">
      <h1 className="text-2xl font-bold tracking-tight">Seu pedido</h1>
      <p className="mt-1 text-sm text-muted-foreground">{loja.name}</p>

      <div className="mt-6">
        <FecharPedido
          mesa={
            mesa && mesa.restauranteId === loja.id
              ? { codigo: mesa.codigo, rotulo: mesa.rotulo }
              : null
          }
          loja={{
            id: loja.id,
            nome: loja.name,
            aberta: loja.is_open,
            taxaCentavos: loja.delivery_fee_cents,
            freteGratisAcima: loja.free_delivery_above_cents,
            minimoCentavos: loja.min_order_cents,
          }}
          itens={carrinho.cart_items.map((i) => ({
            id: i.id,
            quantidade: i.quantity,
            observacao: i.notes,
            produto: {
              nome: i.products?.name ?? "",
              precoCentavos: i.products?.price_cents ?? 0,
              promoCentavos: i.products?.promo_price_cents ?? null,
              promoComeca: i.products?.promo_starts_at ?? null,
              promoTermina: i.products?.promo_ends_at ?? null,
            },
            adicionais: (i.cart_item_addons ?? []).map((a) => ({
              nome: a.addons?.name ?? "",
              precoCentavos: (a.addons?.price_cents ?? 0) * a.quantity,
            })),
          }))}
          enderecos={(enderecos ?? []).map((e) => ({
            id: e.id,
            rotulo: e.label,
            resumo: `${e.street}, ${e.number}${e.complement ? ` — ${e.complement}` : ""}, ${e.district}, ${e.city}-${e.state}`,
          }))}
          formasAceitas={aceitas.map((f) => ({
            metodo: f.method,
            momento: f.timing,
          }))}
        />
      </div>
    </div>
  )
}
