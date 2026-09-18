-- =============================================================================
-- O horário de funcionamento passa a fechar a loja.
--
-- restaurant_hours existe desde o primeiro dia, tem tela no painel, e nunca foi
-- lida por ninguém. O comentário na tabela restaurants dizia:
--
--   "Chave manual de aberto/fechado. O horario de funcionamento
--    (restaurant_hours) decide o resto: o estabelecimento so aceita pedido se
--    as duas coisas concordarem."
--
-- Era uma promessa que o código nunca cumpriu. `fechar_pedido` olhava só
-- `is_open`, e a vitrine também. Quem cadastrava "abre às 18h" via a loja
-- aberta às seis da manhã e recebia pedido que não tinha como atender.
--
-- Agora as duas coisas concordam de verdade:
--
--   is_open        a chave da mão. Fechou por falta de gás? Desliga.
--   horário        a rotina. Abre 18h, fecha 23h, e ninguém precisa lembrar.
--
-- Loja SEM horário cadastrado continua valendo só pela chave — senão esta
-- migração fecharia todo mundo que nunca preencheu a tela.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- O fuso é da loja, não do servidor
-- -----------------------------------------------------------------------------
-- O Postgres do Supabase roda em UTC. "18h" cadastrado por um restaurante em
-- Goiânia é 21h UTC, e comparar direto abriria a loja três horas cedo. Guardar
-- o fuso por estabelecimento é uma coluna, e evita o dia em que alguém vender
-- isto para Manaus ou para Fernando de Noronha.
alter table restaurants
  add column if not exists timezone text not null default 'America/Sao_Paulo';

-- -----------------------------------------------------------------------------
-- Está dentro do horário agora?
-- -----------------------------------------------------------------------------
create or replace function app.dentro_do_horario(
  p_restaurante uuid,
  p_momento timestamptz default now()
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_fuso text;
  v_local timestamp;
  v_dia int;
  v_hora time;
  v_tem_horario boolean;
begin
  select timezone into v_fuso from restaurants where id = p_restaurante;
  if v_fuso is null then return false; end if;

  v_local := p_momento at time zone v_fuso;
  v_dia := extract(dow from v_local)::int;  -- 0 = domingo
  v_hora := v_local::time;

  select exists (
    select 1 from restaurant_hours h where h.restaurant_id = p_restaurante
  ) into v_tem_horario;

  -- Sem horário cadastrado, quem manda é só a chave da mão. Fechar quem nunca
  -- preencheu a tela seria tirar do ar lojas que estão vendendo hoje.
  if not v_tem_horario then return true; end if;

  return exists (
    select 1
    from restaurant_hours h
    where h.restaurant_id = p_restaurante
      and (
        -- Faixa normal: 11:00 às 15:00.
        (h.closes_at > h.opens_at
         and h.weekday = v_dia
         and v_hora >= h.opens_at
         and v_hora < h.closes_at)

        -- Faixa que atravessa a meia-noite: 18:00 às 02:00. Vale até 23:59 do
        -- dia dela, e da meia-noite às 02:00 do dia seguinte — que é a hora em
        -- que a pizzaria mais vende, e a que uma comparação ingênua perde.
        or (h.closes_at <= h.opens_at
            and (
              (h.weekday = v_dia and v_hora >= h.opens_at)
              or (h.weekday = (v_dia + 6) % 7 and v_hora < h.closes_at)
            ))
      )
  );
end;
$$;

comment on function app.dentro_do_horario is
  'O relogio da loja, no fuso dela. Faixa que atravessa a meia-noite conta. Loja sem horario cadastrado responde true: quem manda e a chave da mao.';

-- -----------------------------------------------------------------------------
-- A loja está aberta agora?
-- -----------------------------------------------------------------------------
-- Coluna calculada do PostgREST: uma funcao que recebe a linha de `restaurants`
-- vira uma coluna virtual, pedida por `select=*,aberto_agora`. Assim a vitrine
-- nao precisa buscar horario de trinta lojas e cruzar no cliente — o banco
-- responde a pergunta que a tela faz.
create or replace function public.aberto_agora(restaurants)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select $1.status = 'approved'
     and $1.deleted_at is null
     and $1.is_open
     and app.dentro_do_horario($1.id);
$$;

comment on function public.aberto_agora(restaurants) is
  'Coluna calculada: a loja aceita pedido agora? Chave da mao E horario, as duas concordando.';

grant execute on function public.aberto_agora(restaurants) to anon, authenticated;
