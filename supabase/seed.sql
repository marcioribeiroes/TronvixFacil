-- =============================================================================
-- Tronvix Facil - dados de demonstracao
--
-- Cinco estabelecimentos, cardapio, adicionais, cupons e pedidos em varios
-- estagios, para que todas as telas tenham o que mostrar.
--
-- Os LOGINS de teste NAO sao criados aqui. Usuario e senha vivem em
-- auth.users, que e gerenciado pelo Supabase Auth e nao aceita INSERT direto
-- de forma confiavel entre versoes. Quem cria os logins e
-- scripts/criar-usuarios-de-teste.mjs, que usa a API de administracao.
--
-- Este arquivo e idempotente: pode rodar de novo sem duplicar nada.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Categorias da plataforma
-- -----------------------------------------------------------------------------

insert into platform_categories (slug, name, icon, position) values
  ('lanches',     'Lanches',     'sandwich',  1),
  ('pizzas',      'Pizzas',      'pizza',     2),
  ('bebidas',     'Bebidas',     'cup-soda',  3),
  ('porcoes',     'Porções',     'utensils',  4),
  ('acai',        'Açaí',        'ice-cream', 5),
  ('sobremesas',  'Sobremesas',  'cake',      6),
  ('restaurantes','Restaurantes','store',     7)
on conflict (slug) do update set name = excluded.name, position = excluded.position;

-- -----------------------------------------------------------------------------
-- Estabelecimentos
-- -----------------------------------------------------------------------------

-- Enderecos e CEPs REAIS de Goiania, conferidos no ViaCEP. Os primeiros eram
-- inventados, e isso deixou de ser inofensivo quando o cadastro de endereco
-- passou a buscar o CEP: digitar um CEP da demonstracao devolvia "nao achei",
-- e a demonstracao parecia quebrada.
--
-- As coordenadas continuam aproximadas, no bairro certo: servem para o mapa do
-- entregador ter onde fincar o alfinete. Nao sao levantamento de campo, e
-- nenhuma conta de distancia real deve depender delas.
insert into restaurants (
  id, slug, name, description, status, is_open,
  street, number, district, city, state, postal_code, latitude, longitude,
  phone, delivery_fee_cents, min_order_cents, avg_prep_minutes, avg_delivery_minutes,
  commission_bps, approved_at
) values
  ('a0000000-0000-4000-8000-000000000001', 'burger-house', 'Burger House',
   'Hambúrgueres artesanais, porções e bebidas.', 'approved', true,
   'Rua T 30', '450', 'Setor Bueno', 'Goiânia', 'GO', '74210060',
   -16.7045000, -49.2726000,
   '6232000001', 500, 2000, 25, 20, 1200, now()),

  ('a0000000-0000-4000-8000-000000000002', 'pizzaria-do-chef', 'Pizzaria do Chef',
   'Pizzas de forno a lenha, massa fina e recheio generoso.', 'approved', true,
   'Avenida T 9', '1200', 'Jardim América', 'Goiânia', 'GO', '74255220',
   -16.7089000, -49.2897000,
   '6232000002', 600, 3000, 35, 25, 1000, now()),

  ('a0000000-0000-4000-8000-000000000003', 'lanchonete-do-ze', 'Lanchonete do Zé',
   'O lanche de sempre, do jeito que você gosta.', 'approved', true,
   'Rua 84', '77', 'Setor Sul', 'Goiânia', 'GO', '74080959',
   -16.6910000, -49.2610000,
   '6232000003', 400, 1500, 20, 15, 1000, now()),

  ('a0000000-0000-4000-8000-000000000004', 'acai-mania', 'Açaí Mania',
   'Açaí cremoso, montado do seu jeito.', 'approved', true,
   'Avenida Anhanguera', '3300', 'Setor Central', 'Goiânia', 'GO', '74043906',
   -16.6780000, -49.2560000,
   '6232000004', 450, 1800, 15, 20, 1000, now()),

  -- Fica pendente de proposito: e com ele que a fila de aprovacao do painel
  -- administrativo tem o que mostrar.
  ('a0000000-0000-4000-8000-000000000005', 'sabor-e-cia', 'Sabor & Cia',
   'Comida caseira, marmitas e pratos executivos.', 'pending', false,
   'Rua 1004', '15', 'Setor Pedro Ludovico', 'Goiânia', 'GO', '74820170',
   -16.7180000, -49.2620000,
   '6232000005', 550, 2500, 30, 20, 1000, null)
-- Semear de novo corrige o que estava errado: as coordenadas entram aqui
-- porque um alfinete no lugar errado, corrigido no arquivo, precisa chegar a
-- um banco que ja foi semeado.
on conflict (id) do update set
  name = excluded.name,
  description = excluded.description,
  status = excluded.status,
  street = excluded.street,
  number = excluded.number,
  district = excluded.district,
  postal_code = excluded.postal_code,
  latitude = excluded.latitude,
  longitude = excluded.longitude;

-- Vitrine: em quais categorias cada um aparece
insert into restaurant_platform_categories (restaurant_id, category_id)
select r.id, c.id
from (values
  ('burger-house',     'lanches'),
  ('burger-house',     'porcoes'),
  ('pizzaria-do-chef', 'pizzas'),
  ('lanchonete-do-ze', 'lanches'),
  ('acai-mania',       'acai'),
  ('acai-mania',       'sobremesas'),
  ('sabor-e-cia',      'restaurantes')
) as v(loja, categoria)
join restaurants r on r.slug = v.loja
join platform_categories c on c.slug = v.categoria
on conflict do nothing;

-- Horario: todos os dias, das 11h as 23h
insert into restaurant_hours (restaurant_id, weekday, opens_at, closes_at)
select r.id, dia, time '11:00', time '23:00'
from restaurants r
cross join generate_series(0, 6) as dia
on conflict do nothing;

-- Formas de pagamento aceitas
insert into restaurant_payment_methods (restaurant_id, method, timing)
select r.id, m.metodo::payment_method, m.momento::payment_timing
from restaurants r
cross join (values
  ('pix', 'online'),
  ('credit_card', 'online'),
  ('credit_card', 'on_delivery'),
  ('debit_card', 'on_delivery'),
  ('cash', 'on_delivery')
) as m(metodo, momento)
on conflict do nothing;

-- -----------------------------------------------------------------------------
-- Cardapio
-- -----------------------------------------------------------------------------

insert into categories (id, restaurant_id, name, position) values
  ('b0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000001', 'Lanches', 1),
  ('b0000000-0000-4000-8000-000000000002', 'a0000000-0000-4000-8000-000000000001', 'Porções', 2),
  ('b0000000-0000-4000-8000-000000000003', 'a0000000-0000-4000-8000-000000000001', 'Bebidas', 3),
  ('b0000000-0000-4000-8000-000000000004', 'a0000000-0000-4000-8000-000000000002', 'Pizzas salgadas', 1),
  ('b0000000-0000-4000-8000-000000000005', 'a0000000-0000-4000-8000-000000000002', 'Bebidas', 2),
  ('b0000000-0000-4000-8000-000000000006', 'a0000000-0000-4000-8000-000000000003', 'Lanches', 1),
  ('b0000000-0000-4000-8000-000000000007', 'a0000000-0000-4000-8000-000000000004', 'Açaí', 1)
on conflict (id) do update set name = excluded.name;

insert into products (
  id, restaurant_id, category_id, name, description, price_cents, promo_price_cents,
  is_featured, position
) values
  ('c0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000001',
   'b0000000-0000-4000-8000-000000000001', 'X-Burger',
   'Pão, hambúrguer, queijo, alface, tomate e molho especial.', 2450, null, true, 1),

  ('c0000000-0000-4000-8000-000000000002', 'a0000000-0000-4000-8000-000000000001',
   'b0000000-0000-4000-8000-000000000001', 'X-Bacon',
   'Pão, hambúrguer, bacon, queijo, alface, tomate e molho especial.', 2790, null, true, 2),

  ('c0000000-0000-4000-8000-000000000003', 'a0000000-0000-4000-8000-000000000001',
   'b0000000-0000-4000-8000-000000000001', 'X-Tudo',
   'Pão, dois hambúrgueres, bacon, ovo, queijo, alface e tomate.', 3490, 2990, true, 3),

  ('c0000000-0000-4000-8000-000000000004', 'a0000000-0000-4000-8000-000000000001',
   'b0000000-0000-4000-8000-000000000002', 'Batata Frita',
   'Porção de batata frita crocante. Serve 2 pessoas.', 1290, null, false, 1),

  ('c0000000-0000-4000-8000-000000000005', 'a0000000-0000-4000-8000-000000000001',
   'b0000000-0000-4000-8000-000000000003', 'Coca-Cola 350ml',
   'Lata gelada.', 690, null, false, 1),

  ('c0000000-0000-4000-8000-000000000006', 'a0000000-0000-4000-8000-000000000002',
   'b0000000-0000-4000-8000-000000000004', 'Pizza Margherita',
   'Molho de tomate, muçarela, tomate e manjericão fresco.', 4990, null, true, 1),

  ('c0000000-0000-4000-8000-000000000007', 'a0000000-0000-4000-8000-000000000002',
   'b0000000-0000-4000-8000-000000000004', 'Pizza Calabresa',
   'Molho de tomate, muçarela, calabresa e cebola.', 5290, 4590, true, 2),

  ('c0000000-0000-4000-8000-000000000008', 'a0000000-0000-4000-8000-000000000002',
   'b0000000-0000-4000-8000-000000000004', 'Combo Família',
   'Duas pizzas grandes e um refrigerante de 2 litros.', 9900, 8900, true, 3),

  ('c0000000-0000-4000-8000-000000000009', 'a0000000-0000-4000-8000-000000000003',
   'b0000000-0000-4000-8000-000000000006', 'X-Salada do Zé',
   'O clássico da casa, com salada fresca.', 1990, null, true, 1),

  ('c0000000-0000-4000-8000-00000000000a', 'a0000000-0000-4000-8000-000000000004',
   'b0000000-0000-4000-8000-000000000007', 'Açaí 500ml',
   'Açaí cremoso com até três acompanhamentos.', 1890, null, true, 1),

  ('c0000000-0000-4000-8000-00000000000b', 'a0000000-0000-4000-8000-000000000004',
   'b0000000-0000-4000-8000-000000000007', 'Açaí 300ml',
   'Açaí cremoso com até dois acompanhamentos.', 1390, null, false, 2)
on conflict (id) do update set
  name = excluded.name,
  price_cents = excluded.price_cents,
  promo_price_cents = excluded.promo_price_cents;

-- -----------------------------------------------------------------------------
-- Adicionais
--
-- Cobrem os dois casos que a tela precisa saber tratar: escolha obrigatoria e
-- de opcao unica (o ponto da carne) e escolha opcional de varias opcoes com
-- teto (os acompanhamentos do acai).
-- -----------------------------------------------------------------------------

insert into addon_groups (id, restaurant_id, product_id, name, is_required, min_select, max_select, position) values
  ('d0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000001',
   'c0000000-0000-4000-8000-000000000002', 'Ponto da carne', true, 1, 1, 1),
  ('d0000000-0000-4000-8000-000000000002', 'a0000000-0000-4000-8000-000000000001',
   'c0000000-0000-4000-8000-000000000002', 'Adicionais', false, 0, 5, 2),
  ('d0000000-0000-4000-8000-000000000003', 'a0000000-0000-4000-8000-000000000004',
   'c0000000-0000-4000-8000-00000000000a', 'Acompanhamentos', false, 0, 3, 1)
on conflict (id) do update set name = excluded.name;

insert into addons (restaurant_id, group_id, name, price_cents, position) values
  ('a0000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-000000000001', 'Ao ponto',      0, 1),
  ('a0000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-000000000001', 'Bem passado',   0, 2),
  ('a0000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-000000000001', 'Mal passado',   0, 3),
  ('a0000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-000000000002', 'Bacon extra',  450, 1),
  ('a0000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-000000000002', 'Queijo extra', 350, 2),
  ('a0000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-000000000002', 'Ovo',          250, 3),
  ('a0000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-000000000002', 'Cheddar',      400, 4),
  ('a0000000-0000-4000-8000-000000000004', 'd0000000-0000-4000-8000-000000000003', 'Granola',      200, 1),
  ('a0000000-0000-4000-8000-000000000004', 'd0000000-0000-4000-8000-000000000003', 'Leite Ninho',  300, 2),
  ('a0000000-0000-4000-8000-000000000004', 'd0000000-0000-4000-8000-000000000003', 'Banana',       150, 3),
  ('a0000000-0000-4000-8000-000000000004', 'd0000000-0000-4000-8000-000000000003', 'Morango',      350, 4)
on conflict do nothing;

-- -----------------------------------------------------------------------------
-- Cupons
-- -----------------------------------------------------------------------------

insert into coupons (scope, restaurant_id, code, description, discount, value, min_order_cents, first_order_only)
values
  ('platform', null, 'TRONVIX10', '10% de desconto no primeiro pedido', 'percentage', 1000, 2000, true),
  ('restaurant', 'a0000000-0000-4000-8000-000000000001', 'BURGER5',
   'R$ 5,00 de desconto acima de R$ 40,00', 'fixed', 500, 4000, false),
  ('restaurant', 'a0000000-0000-4000-8000-000000000002', 'FRETEGRATIS',
   'Entrega grátis acima de R$ 60,00', 'free_shipping', 0, 6000, false)
on conflict do nothing;

-- -----------------------------------------------------------------------------
-- Banner da home
-- -----------------------------------------------------------------------------

insert into banners (title, image_url, target_url, position)
select 'Pizza é sempre uma boa ideia', '/banners/pizza.jpg', '/restaurante/pizzaria-do-chef', 1
where not exists (select 1 from banners where title = 'Pizza é sempre uma boa ideia');
