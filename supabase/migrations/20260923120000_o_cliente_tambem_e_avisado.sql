-- =============================================================================
-- O cliente tambem e avisado.
--
-- O aviso por push existia so para um lado: a loja era avisada quando entrava
-- pedido, e o cliente nao era avisado de nada. Quem pediu ficava abrindo o
-- aplicativo para ver se tinha andado — que e exatamente o que o push existe
-- para evitar.
--
-- O gatilho disparava so em `received`, com um retorno antecipado para todo o
-- resto. Passa a disparar tambem nas viradas que interessam a quem pediu, e
-- quem decide o texto e a audiencia de cada uma e a Edge Function.
--
-- Quais viradas, e por que nao todas:
--
--   confirmed          "a loja aceitou". E a hora da ansiedade.
--   ready              so em retirada e mesa — ali e A hora de levantar da
--                      cadeira. Em entrega o cliente nao faz nada com isso, e
--                      o aviso util vem no passo seguinte.
--   out_for_delivery   "saiu para entrega".
--   delivered          fecha o ciclo.
--   rejected           a loja recusou. Nao avisar disto e deixar a pessoa
--                      esperando comida que nao vem.
--   cancelled          idem.
--
-- `preparing` fica de fora de proposito: vem colado em `confirmed` e nao conta
-- nada novo. Aviso demais e a maneira mais rapida de ensinar alguem a desligar
-- os avisos.
-- =============================================================================

create or replace function app.avisar_pedido()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_url text := current_setting('app.url_da_funcao_de_aviso', true);
  v_chave text := current_setting('app.chave_de_servico', true);
  v_virou boolean;
begin
  -- Mudou de status de verdade? Um UPDATE que nao mexe no status - e sao
  -- muitos, porque a tabela tem gatilho de `updated_at` - nao avisa ninguem.
  v_virou := tg_op = 'INSERT' or old.status is distinct from new.status;
  if not v_virou then
    return new;
  end if;

  if not (
    new.status = 'received'
    or new.status in ('confirmed', 'out_for_delivery', 'delivered', 'rejected', 'cancelled')
    -- Pronto so importa a quem vai buscar: em entrega, o aviso que vale e o
    -- "saiu para entrega", logo em seguida.
    or (new.status = 'ready' and new.fulfillment <> 'delivery')
  ) then
    return new;
  end if;

  -- Sem configuracao, o gatilho nao faz nada e nao reclama: um banco de
  -- desenvolvimento recem-criado nao deve tentar mandar push.
  if v_url is null or v_url = '' then
    return new;
  end if;

  -- Chamada dinamica, e nao `perform net.http_post(...)` direto: sem pg_net
  -- instalado, a referencia a `net.http_post` impediria ate a CRIACAO desta
  -- funcao, e a migracao nao aplicaria num Postgres comum.
  if to_regproc('net.http_post') is null then
    return new;
  end if;

  execute format(
    'select net.http_post(url := %L, headers := %L::jsonb, body := %L::jsonb)',
    v_url,
    jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || coalesce(v_chave, '')
    )::text,
    jsonb_build_object(
      'type', tg_op,
      'record', to_jsonb(new),
      'old_record', case when tg_op = 'UPDATE' then to_jsonb(old) else null end
    )::text
  );

  return new;
end;
$$;

comment on function app.avisar_pedido() is
  'Chama a Edge Function de aviso nas viradas de status que interessam a alguem: a loja quando o pedido entra, o cliente quando ele anda. Assincrono por pg_net - o pedido nao espera nem depende do push.';
