-- =============================================================================
-- Tronvix Facil - a nota do cliente e a assinatura do entregador autonomo
--
-- Como rodar:  npm run db:test
-- =============================================================================

\set ON_ERROR_STOP on

begin;

create or replace function pg_temp.conferir(p_condicao boolean, p_contexto text)
returns void language plpgsql as $$
begin
  if not coalesce(p_condicao, false) then
    raise exception 'FALHOU: %', p_contexto;
  end if;
  raise notice 'ok - %', p_contexto;
end;
$$;

create or replace function pg_temp.deve_falhar(p_sql text, p_contexto text)
returns void language plpgsql as $$
begin
  execute p_sql;
  raise exception 'FALHOU: % deveria ter sido rejeitado, mas passou.', p_contexto;
exception
  when check_violation or insufficient_privilege or unique_violation or no_data_found then
    raise notice 'ok - rejeitado como esperado: %', p_contexto;
end;
$$;

grant usage on schema public to authenticated;
grant select on all tables in schema public to authenticated;

-- -----------------------------------------------------------------------------
-- O Pix e o mesmo do site
-- -----------------------------------------------------------------------------
do $$
begin
  -- Referencia tirada de src/lib/pix.ts (gerarBrCode) com os mesmos dados.
  perform pg_temp.conferir(
    app.pix_br_code('+5528999990000', 'Tronvix Fácil Ltda', 'Cachoeiro de Itapemirim',
                    1000, 'TVXABC123')
    = '00020126360014br.gov.bcb.pix0114+5528999990000520400005303986540510.005802BR5918TRONVIX FACIL LTDA6015CACHOEIRO DE IT62130509TVXABC1236304B850',
    'o copia-e-cola do banco e identico ao do site, com CRC');
end;
$$;

-- -----------------------------------------------------------------------------
-- Cenario
-- -----------------------------------------------------------------------------
insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'cliente@teste.test'),
  ('22222222-2222-2222-2222-222222222222', 'outro.cliente@teste.test'),
  ('33333333-3333-3333-3333-333333333333', 'autonomo@teste.test'),
  ('55555555-5555-5555-5555-555555555555', 'admin@teste.test');

select set_config('request.jwt.claim.role', 'service_role', true);
update profiles set platform_role = 'platform_admin'
 where id = '55555555-5555-5555-5555-555555555555';
select set_config('request.jwt.claim.role', '', true);

insert into restaurants (id, slug, name, status, delivery_fee_cents, accepts_platform_couriers,
                         latitude, longitude)
values ('aaaaaaaa-0000-0000-0000-000000000001', 'cantina', 'Cantina', 'approved', 700, true,
        -20.8489, -41.1129);

insert into couriers (id, user_id, restaurant_id, status, approved_at, vehicle_type,
                      current_latitude, current_longitude, location_updated_at)
values ('77777777-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333',
        null, 'approved', now() - interval '45 days', 'motorcycle',
        -20.8500, -41.1129, now());

insert into orders (id, restaurant_id, number, customer_id, customer_name, status, fulfillment,
                    address_summary, subtotal_cents, delivery_fee_cents, total_cents)
values
  ('eeeeeeee-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 1,
   '11111111-1111-1111-1111-111111111111', 'Cliente', 'delivered', 'delivery',
   'Rua A, 1', 2000, 700, 2700),
  ('eeeeeeee-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000001', 2,
   '11111111-1111-1111-1111-111111111111', 'Cliente', 'ready', 'delivery',
   'Rua A, 1', 2000, 700, 2700);

insert into deliveries (order_id, restaurant_id, courier_id, status, distance_km) values
  ('eeeeeeee-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001',
   '77777777-0000-0000-0000-000000000001', 'delivered', 2);

-- -----------------------------------------------------------------------------
-- A avaliacao
-- -----------------------------------------------------------------------------
do $$
begin
  perform set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);
  perform pg_temp.deve_falhar(
    $q$select avaliar_pedido('eeeeeeee-0000-0000-0000-000000000001', 5, 5)$q$,
    'avaliar o pedido de outra pessoa');

  perform set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
  perform pg_temp.deve_falhar(
    $q$select avaliar_pedido('eeeeeeee-0000-0000-0000-000000000002', 5, 5)$q$,
    'avaliar pedido que ainda nao chegou');
  perform pg_temp.deve_falhar(
    $q$select avaliar_pedido('eeeeeeee-0000-0000-0000-000000000001', 6)$q$,
    'nota fora de 1 a 5');

  perform avaliar_pedido('eeeeeeee-0000-0000-0000-000000000001', 4, 2, 'Demorou');
  perform pg_temp.conferir(
    (select restaurant_rating = 4 and courier_rating = 2
            and courier_id = '77777777-0000-0000-0000-000000000001'
            and restaurant_id = 'aaaaaaaa-0000-0000-0000-000000000001'
       from reviews where order_id = 'eeeeeeee-0000-0000-0000-000000000001'),
    'a avaliacao guarda a loja e o entregador do proprio pedido');
  perform pg_temp.conferir(
    (select rating_avg = 2 and rating_count = 1 from couriers
      where id = '77777777-0000-0000-0000-000000000001'),
    'a nota entra na media do entregador');

  perform avaliar_pedido('eeeeeeee-0000-0000-0000-000000000001', 5, 3);
  perform pg_temp.conferir(
    (select count(*) = 1 and max(courier_rating) = 3 from reviews),
    'avaliar de novo corrige a nota, nao cria outra');
end;
$$;

-- Dez notas baixas tiram o autonomo da fila.
do $$
begin
  -- A nota so muda pelo gatilho ou pela chave de servico: e por ela que o
  -- teste monta o historico.
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);
  update couriers set rating_count = 9, rating_avg = 3 where id = '77777777-0000-0000-0000-000000000001';
  perform set_config('request.jwt.claim.role', '', true);
  perform set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
  alter table reviews disable trigger reviews_refresh_ratings;
  perform avaliar_pedido('eeeeeeee-0000-0000-0000-000000000001', 5, 2);
  alter table reviews enable trigger reviews_refresh_ratings;
  perform pg_temp.conferir(
    (select status = 'approved' from couriers where id = '77777777-0000-0000-0000-000000000001'),
    'com poucas avaliacoes, nota baixa ainda nao suspende');

  -- O recalculo poe a contagem real (1); simulamos o historico direto na
  -- linha e disparamos pela avaliacao.
  perform set_config('request.jwt.claim.role', 'service_role', true);
  update couriers set rating_count = 10, rating_avg = 3 where id = '77777777-0000-0000-0000-000000000001';
  perform set_config('request.jwt.claim.role', '', true);
  alter table reviews disable trigger reviews_refresh_ratings;
  perform avaliar_pedido('eeeeeeee-0000-0000-0000-000000000001', 5, 1);
  alter table reviews enable trigger reviews_refresh_ratings;

  perform pg_temp.conferir(
    (select status = 'suspended' and availability = 'offline' and review_note like '%3,5%'
       from couriers where id = '77777777-0000-0000-0000-000000000001'),
    'autonomo com media abaixo de 3,5 em 10 avaliacoes e suspenso, com o motivo');

  perform set_config('request.jwt.claim.sub', '55555555-5555-5555-5555-555555555555', true);
  update couriers set status = 'approved', review_note = null, rating_avg = 4.8
   where id = '77777777-0000-0000-0000-000000000001';
end;
$$;

-- -----------------------------------------------------------------------------
-- A assinatura
-- -----------------------------------------------------------------------------
insert into platform_settings (id) values (true) on conflict (id) do nothing;

insert into orders (id, restaurant_id, number, customer_name, status, fulfillment,
                    address_summary, subtotal_cents, delivery_fee_cents, total_cents)
values ('eeeeeeee-0000-0000-0000-000000000003', 'aaaaaaaa-0000-0000-0000-000000000001', 3,
        'Fila', 'ready', 'delivery', 'Rua B, 2', 2000, 700, 2700);
insert into deliveries (order_id, restaurant_id, status, distance_km) values
  ('eeeeeeee-0000-0000-0000-000000000003', 'aaaaaaaa-0000-0000-0000-000000000001',
   'searching_courier', 3);
update deliveries set searching_since = now() - interval '10 minutes'
 where order_id = 'eeeeeeee-0000-0000-0000-000000000003';

create or replace function pg_temp.autonomo_ve_a_fila()
returns boolean language plpgsql as $$
declare n int;
begin
  perform set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', true);
  set local role authenticated;
  select count(*) into n from deliveries where status = 'searching_courier';
  reset role;
  return n = 1;
end;
$$;

do $$
declare
  v jsonb;
begin
  perform set_config('request.jwt.claim.role', 'service_role', true);
  update platform_settings set courier_subscription_starts_on = null,
                               courier_subscription_price_cents = 1000,
                               platform_pix_key = '+5528999990000',
                               platform_pix_holder = 'Tronvix Facil',
                               platform_pix_city = 'Cachoeiro de Itapemirim';
  perform set_config('request.jwt.claim.role', '', true);

  perform pg_temp.conferir(pg_temp.autonomo_ve_a_fila(),
    'com a cobranca desligada, o autonomo recebe corrida');

  -- Cobranca comeca ha 40 dias; aprovado ha 45: o mes gratis acabou ha 10.
  perform set_config('request.jwt.claim.role', 'service_role', true);
  update platform_settings set courier_subscription_starts_on = current_date - 40;
  perform set_config('request.jwt.claim.role', '', true);

  perform pg_temp.conferir(not pg_temp.autonomo_ve_a_fila(),
    'assinatura vencida: a corrida some da fila do autonomo');

  perform set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', true);
  v := minha_assinatura();
  perform pg_temp.conferir(
    (v ->> 'cobrando')::boolean and not (v ->> 'em_dia')::boolean
    and (v ->> 'vence')::date = current_date - 10,
    'a tela do entregador sabe que venceu, e quando');

  perform gerar_pagamento_da_assinatura();
  perform gerar_pagamento_da_assinatura();
  perform pg_temp.conferir(
    (select count(*) = 1 and max(amount_cents) = 1000 from courier_payments),
    'pedir o Pix duas vezes devolve o mesmo pagamento pendente');

  v := minha_assinatura();
  perform pg_temp.conferir(
    (v -> 'pendente' ->> 'copia_e_cola') like '000201%'
    and (v -> 'pendente' ->> 'copia_e_cola') like '%' || (v -> 'pendente' ->> 'referencia') || '6304%',
    'o Pix do pagamento leva a referencia, para o admin casar com o extrato');

  perform pg_temp.deve_falhar(
    format($q$select confirmar_pagamento_do_entregador('%s')$q$, v -> 'pendente' ->> 'id'),
    'o proprio entregador confirmando o pagamento');

  perform set_config('request.jwt.claim.sub', '55555555-5555-5555-5555-555555555555', true);
  perform confirmar_pagamento_do_entregador((v -> 'pendente' ->> 'id')::uuid);

  perform pg_temp.conferir(
    (select paid_until = current_date + 30 from couriers
      where id = '77777777-0000-0000-0000-000000000001'),
    'pagou atrasado: os 30 dias contam de hoje');
  perform pg_temp.conferir(pg_temp.autonomo_ve_a_fila(),
    'assinatura paga: a corrida volta para a fila');
end;
$$;

rollback;
