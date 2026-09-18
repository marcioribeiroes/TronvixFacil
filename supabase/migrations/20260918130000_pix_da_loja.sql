-- =============================================================================
-- Pix direto da loja.
--
-- Ate aqui, escolher "Pix pelo site" criava um pedido em `awaiting_payment` que
-- NUNCA chegava a cozinha: nenhum provedor estava ligado, e ninguem confirmava
-- pagamento online. Uma armadilha silenciosa — o cliente achava que pediu, o
-- restaurante nunca soube.
--
-- A escolha aqui e o Pix da propria loja, e nao um gateway:
--
--   o dinheiro cai direto na conta do restaurante, sem intermediario
--   nao ha taxa por transacao, nem contrato a assinar
--   funciona hoje, sem ninguem abrir conta em lugar nenhum
--
-- A contrapartida e honesta e esta escrita na tela: a confirmacao e MANUAL.
-- Alguem do balcao ve o dinheiro entrar e libera o pedido. E assim que a
-- maioria dos restaurantes pequenos ja trabalha, e e melhor do que a alternativa
-- que existia — a de perder o pedido.
--
-- O BR Code (o "copia e cola") e montado no servidor a partir destes campos.
-- Nada disto e digitado pelo cliente.
-- =============================================================================

alter table restaurants
  add column if not exists pix_key text,
  add column if not exists pix_key_type text,
  -- Nome e cidade vao DENTRO do código Pix, e o banco do cliente os mostra na
  -- hora de confirmar. Nome errado aqui é o cliente desistindo do pagamento
  -- porque não reconhece quem vai receber.
  add column if not exists pix_recipient_name text,
  add column if not exists pix_city text;

alter table restaurants drop constraint if exists restaurants_pix_key_type;
alter table restaurants add constraint restaurants_pix_key_type check (
  pix_key_type is null
  or pix_key_type in ('cpf', 'cnpj', 'email', 'telefone', 'aleatoria')
);

-- Chave sem tipo, ou tipo sem chave, seria um Pix pela metade: o BR Code sairia
-- errado e o cliente veria "chave inválida" no banco dele.
alter table restaurants drop constraint if exists restaurants_pix_completo;
alter table restaurants add constraint restaurants_pix_completo check (
  (pix_key is null and pix_key_type is null)
  or (pix_key is not null and pix_key_type is not null)
);

comment on column restaurants.pix_key is
  'Chave Pix da loja. O dinheiro vai direto para a conta dela; a plataforma nao passa no meio.';

-- -----------------------------------------------------------------------------
-- A loja aceita Pix agora?
-- -----------------------------------------------------------------------------
-- Coluna calculada, como `aberto_agora`: a tela de fechar pedido precisa saber
-- se vale oferecer Pix, e oferecer sem chave cadastrada e repetir a armadilha
-- com outra roupa.
create or replace function public.aceita_pix(restaurants)
returns boolean
language sql
stable
as $$
  select $1.pix_key is not null and $1.pix_key_type is not null;
$$;

comment on function public.aceita_pix(restaurants) is
  'Coluna calculada: a loja tem chave Pix cadastrada? Sem ela, nao se oferece Pix.';

grant execute on function public.aceita_pix(restaurants) to anon, authenticated;

-- -----------------------------------------------------------------------------
-- Confirmar que o Pix caiu
-- -----------------------------------------------------------------------------
-- Duas coisas numa transacao so: marcar o pagamento como pago e soltar o pedido
-- para a cozinha. Separadas, uma poderia acontecer sem a outra — pagamento pago
-- com pedido parado, ou pedido solto sem pagamento registrado.
--
-- Quem pode: a gestao e o atendente da loja. Nao o cliente, por motivos obvios.
create or replace function public.confirmar_pix(p_pedido uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pedido orders;
  v_pagamento payments;
begin
  select * into v_pedido from orders where id = p_pedido;
  if v_pedido.id is null then
    raise exception 'Pedido nao encontrado.' using errcode = 'no_data_found';
  end if;

  if not (app.is_member(v_pedido.restaurant_id) or app.is_platform_admin()) then
    raise exception 'Somente o estabelecimento confirma o recebimento.'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_pagamento from payments where order_id = p_pedido limit 1;
  if v_pagamento.id is null then
    raise exception 'Este pedido nao tem pagamento registrado.' using errcode = 'no_data_found';
  end if;
  if v_pagamento.method <> 'pix' or v_pagamento.timing <> 'online' then
    raise exception 'Este pedido nao e de Pix pelo site.' using errcode = 'check_violation';
  end if;
  if v_pagamento.status = 'paid' then
    raise exception 'Este Pix ja foi confirmado.' using errcode = 'check_violation';
  end if;

  update payments
     set status = 'paid', paid_at = now()
   where id = v_pagamento.id;

  -- So sai de "aguardando pagamento". Um pedido ja aceito e em preparo nao
  -- volta para tras so porque alguem clicou duas vezes.
  if v_pedido.status = 'awaiting_payment' then
    update orders set status = 'received' where id = p_pedido;
  end if;
end;
$$;

revoke all on function public.confirmar_pix(uuid) from public;
grant execute on function public.confirmar_pix(uuid) to authenticated;

comment on function public.confirmar_pix is
  'O balcao confirma que o Pix caiu: marca o pagamento e solta o pedido para a cozinha, numa transacao so.';
