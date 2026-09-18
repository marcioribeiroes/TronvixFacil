import type { Metadata } from "next"
import Link from "next/link"
import { ShoppingBasket } from "lucide-react"

import { FecharPedido } from "@/components/cliente/fechar-pedido"
import { criarClienteDoServidor } from "@/lib/supabase/servidor"
import { exigirUsuario } from "@/modules/auth/sessao"

export const metadata: Metadata = { title: "Seu pedido" }

export default async function PaginaDoCarrinho() {
  const contexto = await exigirUsuario("/carrinho")
  const supabase = await criarClienteDoServidor()

  const { data: carrinho } = await supabase
    .from("carts")
    .select(
      "id, restaurant_id, restaurants(id, name, logo_url, is_open, delivery_fee_cents, free_delivery_above_cents, min_order_cents), cart_items(id, quantity, notes, products(id, name, price_cents, promo_price_cents, promo_starts_at, promo_ends_at), cart_item_addons(quantity, addons(id, name, price_cents)))",
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
      .select("method")
      .eq("restaurant_id", carrinho.restaurant_id)
      .eq("is_active", true),
  ])

  const loja = carrinho.restaurants

  return (
    <div className="mx-auto max-w-2xl px-4 py-6">
      <h1 className="text-2xl font-bold tracking-tight">Seu pedido</h1>
      <p className="mt-1 text-sm text-muted-foreground">{loja.name}</p>

      <div className="mt-6">
        <FecharPedido
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
          formasAceitas={(formas ?? []).map((f) => f.method)}
        />
      </div>
    </div>
  )
}
