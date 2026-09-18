-- =============================================================================
-- Tronvix Facil - ligar o Realtime nas tabelas que o aplicativo assina
--
-- Tres telas do produto prometem "sozinho":
--
--   * o balcao, onde pedido que entra tem de aparecer sem ninguem puxar;
--   * a fila do entregador, quando o balcao despacha;
--   * o acompanhamento do cliente, quando a cozinha muda o estado.
--
-- As tres assinam postgres_changes e as tres nunca receberam nada. O motivo e
-- que no Supabase o Realtime so transmite tabela que esteja na publicacao
-- `supabase_realtime` - e nenhuma migracao tinha adicionado nenhuma. O canal
-- conectava, a assinatura era aceita, e o evento nao vinha: falha silenciosa,
-- que e a pior especie.
--
-- Descoberto olhando a tela de rastreio: o pedido estava `delivered` no banco e
-- o cabecalho continuava dizendo "Saiu para entrega".
--
-- O que NAO entra aqui, de proposito: `couriers`. A posicao do entregador e
-- consultada por funcao justamente para nao transmitir a linha dele - poe-la
-- na publicacao desfaria essa escolha.
-- =============================================================================

do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
end;
$$;

do $$
declare
  v_tabela text;
begin
  foreach v_tabela in array array['orders', 'deliveries'] loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = v_tabela
    ) then
      execute format(
        'alter publication supabase_realtime add table public.%I', v_tabela);
    end if;
  end loop;
end;
$$;

comment on publication supabase_realtime is
  'O que o aplicativo assina. Entrar aqui significa que a linha viaja ate quem a RLS deixa ver - entao so entra tabela cuja linha inteira pode mesmo ser vista por quem a assina.';
