-- =============================================================================
-- Tronvix Facil - testes das regras que vivem no banco
--
-- Estes testes nao verificam se o SQL compila: verificam se as travas travam.
-- Cada bloco tenta fazer algo proibido e falha se o banco permitir.
--
-- Como rodar:
--   npm run db:test           (usa um Postgres local descartavel)
--   psql -d <banco> -f supabase/tests/regras_do_pedido.sql
-- =============================================================================

\set ON_ERROR_STOP on

begin;

-- Utilitario: executa um comando que DEVE falhar. Se ele passar, o teste
-- quebra com a mensagem de contexto.
create or replace function pg_temp.deve_falhar(p_sql text, p_contexto text)
returns void
language plpgsql
as $$
begin
  execute p_sql;
  raise exception 'FALHOU: % deveria ter sido rejeitado, mas passou.', p_contexto;
exception
  when check_violation or insufficient_privilege or foreign_key_violation
    or not_null_violation or unique_violation then
    raise notice 'ok - rejeitado como esperado: %', p_contexto;
end;
$$;

create or replace function pg_temp.conferir(p_condicao boolean, p_contexto text)
returns void
language plpgsql
as $$
begin
  if not p_condicao then
    raise exception 'FALHOU: %', p_contexto;
  end if;
  raise notice 'ok - %', p_contexto;
end;
$$;

-- -----------------------------------------------------------------------------
-- Cenario
-- -----------------------------------------------------------------------------

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'dono@burgerhouse.test'),
  ('22222222-2222-2222-2222-222222222222', 'cliente@teste.test');

insert into restaurants (id, slug, name, status, is_open, delivery_fee_cents, commission_bps)
values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'burger-house', 'Burger House', 'approved', true, 500, 1200),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'pizzaria-do-chef', 'Pizzaria do Chef', 'approved', true, 600, 1000);

insert into restaurant_members (restaurant_id, user_id, role)
values ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'owner');

insert into categories (id, restaurant_id, name)
values ('bbbbbbbb-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'Lanches');

insert into products (id, restaurant_id, category_id, name, price_cents)
values ('cccccccc-0000-0000-0000-000000000001',
        'aaaaaaaa-0000-0000-0000-000000000001',
        'bbbbbbbb-0000-0000-0000-000000000001',
        'X-Bacon', 2790);

-- -----------------------------------------------------------------------------
-- Cardapio
-- -----------------------------------------------------------------------------

select pg_temp.deve_falhar($$
  insert into products (restaurant_id, category_id, name, price_cents)
  values ('aaaaaaaa-0000-0000-0000-000000000002',
          'bbbbbbbb-0000-0000-0000-000000000001', 'Invasor', 1000)
$$, 'produto apontando para categoria de outro estabelecimento');

select pg_temp.deve_falhar($$
  insert into products (restaurant_id, category_id, name, price_cents, promo_price_cents)
  values ('aaaaaaaa-0000-0000-0000-000000000001',
          'bbbbbbbb-0000-0000-0000-000000000001', 'X-Caro', 1000, 2000)
$$, 'promocao mais cara que o preco cheio');

select pg_temp.deve_falhar($$
  insert into addon_groups (restaurant_id, product_id, name, is_required, min_select, max_select)
  values ('aaaaaaaa-0000-0000-0000-000000000001',
          'cccccccc-0000-0000-0000-000000000001', 'Ponto da carne', true, 0, 1)
$$, 'grupo obrigatorio com minimo zero');

-- -----------------------------------------------------------------------------
-- Numeracao dos pedidos: sequencial e independente por estabelecimento
-- -----------------------------------------------------------------------------

insert into orders (id, restaurant_id, customer_id, customer_name, status, fulfillment,
                    address_summary, subtotal_cents, delivery_fee_cents, total_cents)
values ('dddddddd-0000-0000-0000-000000000001',
        'aaaaaaaa-0000-0000-0000-000000000001',
        '22222222-2222-2222-2222-222222222222',
        'Joao Silva', 'received', 'delivery',
        'Rua das Flores, 123', 2790, 500, 3290);

insert into orders (id, restaurant_id, customer_id, customer_name, status, fulfillment,
                    address_summary, subtotal_cents, delivery_fee_cents, total_cents)
values ('dddddddd-0000-0000-0000-000000000002',
        'aaaaaaaa-0000-0000-0000-000000000001',
        '22222222-2222-2222-2222-222222222222',
        'Maria Souza', 'received', 'delivery',
        'Rua B, 9', 1000, 500, 1500);

insert into orders (id, restaurant_id, customer_id, customer_name, status, fulfillment,
                    address_summary, subtotal_cents, delivery_fee_cents, total_cents)
values ('dddddddd-0000-0000-0000-000000000003',
        'aaaaaaaa-0000-0000-0000-000000000002',
        '22222222-2222-2222-2222-222222222222',
        'Carlos Lima', 'received', 'delivery',
        'Rua C, 10', 4000, 600, 4600);

select pg_temp.conferir(
  (select number from orders where id = 'dddddddd-0000-0000-0000-000000000001') = 1
  and (select number from orders where id = 'dddddddd-0000-0000-0000-000000000002') = 2,
  'numeracao avanca dentro do mesmo estabelecimento');

select pg_temp.conferir(
  (select number from orders where id = 'dddddddd-0000-0000-0000-000000000003') = 1,
  'cada estabelecimento comeca a propria numeracao no 1');

-- -----------------------------------------------------------------------------
-- Aritmetica do pedido
-- -----------------------------------------------------------------------------

select pg_temp.deve_falhar($$
  insert into orders (restaurant_id, customer_name, status, fulfillment, address_summary,
                      subtotal_cents, delivery_fee_cents, discount_cents, total_cents)
  values ('aaaaaaaa-0000-0000-0000-000000000001', 'Fraude', 'received', 'delivery',
          'Rua X, 1', 5000, 500, 0, 100)
$$, 'total que nao fecha com as partes');

select pg_temp.deve_falhar($$
  insert into orders (restaurant_id, customer_name, status, fulfillment, address_summary,
                      subtotal_cents, delivery_fee_cents, discount_cents, total_cents)
  values ('aaaaaaaa-0000-0000-0000-000000000001', 'Fraude', 'received', 'delivery',
          'Rua X, 1', 1000, 500, 9000, -7500)
$$, 'desconto maior que o pedido');

select pg_temp.deve_falhar($$
  insert into orders (restaurant_id, customer_name, status, fulfillment,
                      subtotal_cents, delivery_fee_cents, total_cents)
  values ('aaaaaaaa-0000-0000-0000-000000000001', 'Sem endereco', 'received', 'delivery',
          1000, 500, 1500)
$$, 'pedido de entrega sem endereco');

-- Item do pedido: o total do item tem de fechar com preco, adicionais e quantidade.
select pg_temp.deve_falhar($$
  insert into order_items (order_id, product_name, unit_price_cents, quantity, total_cents)
  values ('dddddddd-0000-0000-0000-000000000001', 'X-Bacon', 2790, 2, 2790)
$$, 'total do item ignorando a quantidade');

insert into order_items (order_id, product_id, product_name, unit_price_cents, quantity,
                         addons_total_cents, total_cents)
values ('dddddddd-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-000000000001',
        'X-Bacon', 2790, 1, 0, 2790);

-- -----------------------------------------------------------------------------
-- Maquina de estados do pedido
-- -----------------------------------------------------------------------------

select pg_temp.deve_falhar($$
  update orders set status = 'delivered'
  where id = 'dddddddd-0000-0000-0000-000000000001'
$$, 'pular de "recebido" direto para "entregue"');

update orders set status = 'confirmed' where id = 'dddddddd-0000-0000-0000-000000000001';
update orders set status = 'preparing' where id = 'dddddddd-0000-0000-0000-000000000001';
update orders set status = 'ready'     where id = 'dddddddd-0000-0000-0000-000000000001';

select pg_temp.conferir(
  (select confirmed_at is not null and ready_at is not null
   from orders where id = 'dddddddd-0000-0000-0000-000000000001'),
  'marcos de tempo preenchidos pelo proprio banco');

update orders set status = 'out_for_delivery' where id = 'dddddddd-0000-0000-0000-000000000001';
update orders set status = 'delivered'        where id = 'dddddddd-0000-0000-0000-000000000001';

select pg_temp.deve_falhar($$
  update orders set status = 'preparing'
  where id = 'dddddddd-0000-0000-0000-000000000001'
$$, 'voltar de "entregue" para "em preparo"');

select pg_temp.conferir(
  (select count(*) from order_status_history
   where order_id = 'dddddddd-0000-0000-0000-000000000001') = 6,
  'historico registrou a criacao e as cinco transicoes');

-- Retirada nao passa pela rua.
insert into orders (id, restaurant_id, customer_name, status, fulfillment,
                    subtotal_cents, delivery_fee_cents, total_cents)
values ('dddddddd-0000-0000-0000-000000000004',
        'aaaaaaaa-0000-0000-0000-000000000001', 'Retirada', 'received', 'pickup',
        2000, 0, 2000);

update orders set status = 'confirmed' where id = 'dddddddd-0000-0000-0000-000000000004';
update orders set status = 'preparing' where id = 'dddddddd-0000-0000-0000-000000000004';
update orders set status = 'ready'     where id = 'dddddddd-0000-0000-0000-000000000004';

select pg_temp.deve_falhar($$
  update orders set status = 'out_for_delivery'
  where id = 'dddddddd-0000-0000-0000-000000000004'
$$, 'pedido de retirada saindo para entrega');

update orders set status = 'delivered' where id = 'dddddddd-0000-0000-0000-000000000004';

select pg_temp.conferir(
  (select status from orders where id = 'dddddddd-0000-0000-0000-000000000004') = 'delivered',
  'retirada e concluida direto de "pronto"');

-- -----------------------------------------------------------------------------
-- Valores do pedido sao imutaveis depois de fechado
-- -----------------------------------------------------------------------------

select pg_temp.deve_falhar($$
  update orders set subtotal_cents = 1, total_cents = 501
  where id = 'dddddddd-0000-0000-0000-000000000002'
$$, 'reescrever o valor de um pedido ja fechado');

-- -----------------------------------------------------------------------------
-- Pagamento
-- -----------------------------------------------------------------------------

select pg_temp.deve_falhar($$
  insert into payments (order_id, method, timing, amount_cents, change_for_cents)
  values ('dddddddd-0000-0000-0000-000000000002', 'pix', 'online', 1500, 2000)
$$, 'troco informado em pagamento que nao e dinheiro');

select pg_temp.deve_falhar($$
  insert into payments (order_id, method, timing, amount_cents, change_for_cents)
  values ('dddddddd-0000-0000-0000-000000000002', 'cash', 'on_delivery', 1500, 1000)
$$, 'troco menor que o valor do pedido');

insert into payments (order_id, method, timing, amount_cents, change_for_cents)
values ('dddddddd-0000-0000-0000-000000000002', 'cash', 'on_delivery', 1500, 2000);

-- -----------------------------------------------------------------------------
-- Entrega
-- -----------------------------------------------------------------------------

insert into couriers (id, user_id, status, availability)
values ('eeeeeeee-0000-0000-0000-000000000001',
        '22222222-2222-2222-2222-222222222222', 'approved', 'online');

insert into deliveries (id, order_id, restaurant_id, status, courier_fee_cents)
values ('ffffffff-0000-0000-0000-000000000001',
        'dddddddd-0000-0000-0000-000000000002',
        'aaaaaaaa-0000-0000-0000-000000000001', 'searching_courier', 700);

select pg_temp.deve_falhar($$
  update deliveries set status = 'delivered'
  where id = 'ffffffff-0000-0000-0000-000000000001'
$$, 'entrega concluida sem ter sido aceita');

update deliveries
  set status = 'assigned', courier_id = 'eeeeeeee-0000-0000-0000-000000000001'
  where id = 'ffffffff-0000-0000-0000-000000000001';

-- Desistencia devolve a corrida a fila e solta o entregador.
update deliveries set status = 'searching_courier'
  where id = 'ffffffff-0000-0000-0000-000000000001';

select pg_temp.conferir(
  (select courier_id is null from deliveries where id = 'ffffffff-0000-0000-0000-000000000001'),
  'desistencia devolve a corrida a fila e limpa o entregador');

-- -----------------------------------------------------------------------------
-- Chamar o entregador antes da comida ficar pronta
--
-- A corrida passa a ser aceita durante o preparo, entao o entregador chega
-- antes da comida. Duas regras nascem disso: ele nao consegue "pegar" o que
-- nao esta pronto, e pegar e o que poe o pedido na rua.
-- -----------------------------------------------------------------------------

update deliveries
  set status = 'assigned', courier_id = 'eeeeeeee-0000-0000-0000-000000000001'
  where id = 'ffffffff-0000-0000-0000-000000000001';

update deliveries set status = 'heading_to_restaurant'
  where id = 'ffffffff-0000-0000-0000-000000000001';

-- O pedido ainda esta na cozinha.
update orders set status = 'confirmed' where id = 'dddddddd-0000-0000-0000-000000000002';
update orders set status = 'preparing' where id = 'dddddddd-0000-0000-0000-000000000002';

select pg_temp.deve_falhar($$
  update deliveries set status = 'picked_up'
  where id = 'ffffffff-0000-0000-0000-000000000001'
$$, 'retirada de pedido que ainda esta em preparo');

select pg_temp.conferir(
  (select status from orders where id = 'dddddddd-0000-0000-0000-000000000002') = 'preparing',
  'a retirada recusada nao mexeu no pedido');

update orders set status = 'ready' where id = 'dddddddd-0000-0000-0000-000000000002';

update deliveries set status = 'picked_up'
  where id = 'ffffffff-0000-0000-0000-000000000001';

select pg_temp.conferir(
  (select status from orders where id = 'dddddddd-0000-0000-0000-000000000002') = 'out_for_delivery',
  'retirar o pedido e o que o poe na rua, sem clique do balcao');

select pg_temp.conferir(
  (select picked_up_at is not null from deliveries
    where id = 'ffffffff-0000-0000-0000-000000000001'),
  'a retirada carimba a hora');

-- A previsao e promessa, e nao pode ser confundida com a medicao: quem
-- registra o que aconteceu e ready_at, escrito pelo gatilho.
select pg_temp.conferir(
  (select ready_at is not null and ready_forecast_at is null
     from orders where id = 'dddddddd-0000-0000-0000-000000000002'),
  'ready_at e carimbado pelo gatilho; ready_forecast_at so por quem chama');

-- -----------------------------------------------------------------------------
-- O caminho antigo continua valendo
--
-- Quem despacha na mao - o dono que leva o proprio pedido, a loja sem
-- entregador cadastrado - marca o pedido como saido ANTES de existir corrida.
-- Exigir 'ready' na retirada teria quebrado essa gente.
-- -----------------------------------------------------------------------------

update orders set status = 'confirmed' where id = 'dddddddd-0000-0000-0000-000000000001';
update orders set status = 'preparing' where id = 'dddddddd-0000-0000-0000-000000000001';
update orders set status = 'ready' where id = 'dddddddd-0000-0000-0000-000000000001';
update orders set status = 'out_for_delivery' where id = 'dddddddd-0000-0000-0000-000000000001';

insert into deliveries (id, order_id, restaurant_id, status, courier_fee_cents)
values ('ffffffff-0000-0000-0000-000000000002',
        'dddddddd-0000-0000-0000-000000000001',
        'aaaaaaaa-0000-0000-0000-000000000001', 'searching_courier', 700);

update deliveries
  set status = 'assigned', courier_id = 'eeeeeeee-0000-0000-0000-000000000001'
  where id = 'ffffffff-0000-0000-0000-000000000002';

update deliveries set status = 'heading_to_restaurant'
  where id = 'ffffffff-0000-0000-0000-000000000002';

update deliveries set status = 'picked_up'
  where id = 'ffffffff-0000-0000-0000-000000000002';

select pg_temp.conferir(
  (select status from orders where id = 'dddddddd-0000-0000-0000-000000000001') = 'out_for_delivery',
  'no caminho antigo a retirada passa e nao desfaz o despacho do balcao');

-- -----------------------------------------------------------------------------
-- Entregador
-- -----------------------------------------------------------------------------

insert into auth.users (id, email) values
  ('33333333-3333-3333-3333-333333333333', 'novato@entrega.test');

insert into couriers (id, user_id, status)
values ('eeeeeeee-0000-0000-0000-000000000002',
        '33333333-3333-3333-3333-333333333333', 'pending');

select pg_temp.deve_falhar($$
  update couriers set availability = 'online'
  where id = 'eeeeeeee-0000-0000-0000-000000000002'
$$, 'entregador nao aprovado ficando disponivel');

-- -----------------------------------------------------------------------------
-- Equipe: o ultimo proprietario nao sai
-- -----------------------------------------------------------------------------

select pg_temp.deve_falhar($$
  delete from restaurant_members
  where restaurant_id = 'aaaaaaaa-0000-0000-0000-000000000001'
    and user_id = '11111111-1111-1111-1111-111111111111'
$$, 'remover o unico proprietario do estabelecimento');

select pg_temp.deve_falhar($$
  update restaurant_members set role = 'staff'
  where restaurant_id = 'aaaaaaaa-0000-0000-0000-000000000001'
    and user_id = '11111111-1111-1111-1111-111111111111'
$$, 'rebaixar o unico proprietario do estabelecimento');

-- -----------------------------------------------------------------------------
-- Cupons
-- -----------------------------------------------------------------------------

select pg_temp.deve_falhar($$
  insert into coupons (scope, restaurant_id, code, discount, value)
  values ('platform', 'aaaaaaaa-0000-0000-0000-000000000001', 'MISTO', 'fixed', 500)
$$, 'cupom de plataforma amarrado a um estabelecimento');

select pg_temp.deve_falhar($$
  insert into coupons (scope, restaurant_id, code, discount, value)
  values ('restaurant', 'aaaaaaaa-0000-0000-0000-000000000001', 'IMPOSSIVEL', 'percentage', 15000)
$$, 'desconto percentual acima de 100%');

insert into coupons (scope, restaurant_id, code, discount, value)
values ('restaurant', 'aaaaaaaa-0000-0000-0000-000000000001', 'BEMVINDO', 'percentage', 1500);

select pg_temp.deve_falhar($$
  insert into coupons (scope, restaurant_id, code, discount, value)
  values ('restaurant', 'aaaaaaaa-0000-0000-0000-000000000001', 'bemvindo', 'fixed', 500)
$$, 'codigo de cupom repetido no mesmo estabelecimento (ignorando maiusculas)');

-- -----------------------------------------------------------------------------
-- Avaliacoes
-- -----------------------------------------------------------------------------

insert into reviews (order_id, restaurant_id, customer_id, restaurant_rating)
values ('dddddddd-0000-0000-0000-000000000001',
        'aaaaaaaa-0000-0000-0000-000000000001',
        '22222222-2222-2222-2222-222222222222', 5);

select pg_temp.conferir(
  (select rating_avg = 5.00 and rating_count = 1
   from restaurants where id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  'media do estabelecimento recalculada pelo banco');

-- O recalculo acima chega por gatilho e passa. Uma escrita direta de
-- reputacao, vinda do cliente, tem de ser ignorada em silencio: nota nao se
-- digita.
update restaurants set rating_avg = 1.00, rating_count = 999
  where id = 'aaaaaaaa-0000-0000-0000-000000000001';

select pg_temp.conferir(
  (select rating_avg = 5.00 and rating_count = 1
   from restaurants where id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  'escrita direta de reputacao e descartada');

select pg_temp.deve_falhar($$
  update restaurants set status = 'suspended'
  where id = 'aaaaaaaa-0000-0000-0000-000000000001'
$$, 'estabelecimento mudando a propria situacao');

select pg_temp.deve_falhar($$
  update restaurants set commission_bps = 0
  where id = 'aaaaaaaa-0000-0000-0000-000000000001'
$$, 'estabelecimento baixando a propria comissao');

select pg_temp.deve_falhar($$
  insert into reviews (order_id, restaurant_id, customer_id, restaurant_rating)
  values ('dddddddd-0000-0000-0000-000000000004',
          'aaaaaaaa-0000-0000-0000-000000000001',
          '22222222-2222-2222-2222-222222222222', 9)
$$, 'nota fora da escala de 1 a 5');

-- -----------------------------------------------------------------------------
-- Enderecos
-- -----------------------------------------------------------------------------

insert into addresses (user_id, street, number, district, city, state, postal_code, is_default)
values ('22222222-2222-2222-2222-222222222222', 'Rua das Flores', '123',
        'Centro', 'Goiania', 'GO', '74000000', true);

select pg_temp.deve_falhar($$
  insert into addresses (user_id, street, number, district, city, state, postal_code, is_default)
  values ('22222222-2222-2222-2222-222222222222', 'Rua B', '9',
          'Setor Sul', 'Goiania', 'GO', '74001000', true)
$$, 'segundo endereco padrao para o mesmo cliente');

select pg_temp.deve_falhar($$
  insert into addresses (user_id, street, number, district, city, state, postal_code)
  values ('22222222-2222-2222-2222-222222222222', 'Rua C', '10',
          'Setor Sul', 'Goiania', 'GO', '74001-000')
$$, 'CEP com formatacao em vez de so digitos');

rollback;
