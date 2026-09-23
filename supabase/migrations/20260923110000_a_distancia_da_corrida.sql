-- =============================================================================
-- A distancia da corrida deixa de ser uma coluna vazia.
--
-- `deliveries.distance_km` existe desde a fundacao e NUNCA foi escrita: nem o
-- fechamento do pedido, nem gatilho, nem tela. O aplicativo ja tentava mostrar
-- ("X de percurso", na tela da corrida) e nunca mostrava nada, porque o valor
-- era sempre nulo.
--
-- E o dado estava ali o tempo todo. O estabelecimento tem latitude e longitude
-- no cadastro; o pedido tem as do endereco de entrega. Faltava a conta.
--
-- Isso importa porque o entregador decide sem ela. O cartao da corrida diz
-- quanto ele recebe e para onde vai, mas nao quanto vai rodar — e e a razao
-- entre as duas coisas que faz a corrida valer ou nao. Para quem pedala, mais
-- ainda.
--
-- E DISTANCIA EM LINHA RETA, nao rota. Nao passa por rio, viaduto ou mao
-- unica. Serve para comparar corridas entre si e para recusar o que esta longe
-- demais; nao serve para prometer tempo de chegada ao cliente.
-- =============================================================================

create or replace function app.haversine_km(
  p_lat1 numeric,
  p_lon1 numeric,
  p_lat2 numeric,
  p_lon2 numeric
)
returns numeric
language sql
immutable
as $$
  select case
    when p_lat1 is null or p_lon1 is null or p_lat2 is null or p_lon2 is null
      then null
    else round(
      (6371 * 2 * asin(least(1, sqrt(
        power(sin(radians(p_lat2::double precision - p_lat1::double precision) / 2), 2)
        + cos(radians(p_lat1::double precision))
          * cos(radians(p_lat2::double precision))
          * power(sin(radians(p_lon2::double precision - p_lon1::double precision) / 2), 2)
      ))))::numeric,
      2)
  end;
$$;

comment on function app.haversine_km(numeric, numeric, numeric, numeric) is
  'Distancia em linha reta entre dois pontos, em km. Nao e rota: nao conhece rua, rio nem mao unica.';

-- -----------------------------------------------------------------------------
-- A conta acontece quando a corrida nasce
-- -----------------------------------------------------------------------------
-- Como gatilho, e nao dentro de `fechar_pedido`, porque ha mais de um caminho
-- que cria entrega — o fechamento normal e o do salao. Regra que mora em dois
-- lugares envelhece em um deles.
--
-- Congelada no momento em que a corrida nasce, do mesmo jeito que
-- `courier_fee_cents`: se a loja mudar de endereco no mes que vem, o historico
-- de quem rodou continua dizendo o que foi rodado.
create or replace function app.fill_delivery_distance()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.distance_km is not null then
    return new;
  end if;

  select app.haversine_km(r.latitude, r.longitude, o.address_latitude, o.address_longitude)
    into new.distance_km
    from orders o
    join restaurants r on r.id = o.restaurant_id
   where o.id = new.order_id;

  return new;
end;
$$;

comment on function app.fill_delivery_distance is
  'Escreve deliveries.distance_km quando a corrida nasce, a partir das coordenadas da loja e do endereco de entrega. Nulo continua sendo normal: nem todo cliente deixa marcar o endereco no mapa.';

drop trigger if exists deliveries_fill_distance on deliveries;
create trigger deliveries_fill_distance
  before insert on deliveries
  for each row execute function app.fill_delivery_distance();

-- -----------------------------------------------------------------------------
-- As corridas que ja existem
-- -----------------------------------------------------------------------------
-- Vale ate para as entregues: o historico do entregador passa a saber quanto
-- ele rodou, e sem isto o "quanto rendeu por km" nasceria cego para tras.
update deliveries d
   set distance_km = app.haversine_km(
         r.latitude, r.longitude, o.address_latitude, o.address_longitude)
  from orders o
  join restaurants r on r.id = o.restaurant_id
 where o.id = d.order_id
   and d.distance_km is null;
