-- =============================================================================
-- Tronvix Facil - codigo de barras e entrada de estoque
--
-- Ate aqui o estoque so andava para baixo pelo livro: o pedido tirava e
-- registrava em `stock_movements`, mas a mercadoria que chegava entrava
-- digitando o saldo novo no formulario do produto - sem rastro de quanto
-- chegou, quando, nem quem recebeu.
--
-- Duas pecas:
--
--   products.barcode          o codigo da embalagem. E por ele que o leitor
--                             encontra o produto na hora de receber. Unico por
--                             loja (dois produtos com o mesmo codigo fariam o
--                             leitor escolher no chute), livre entre lojas.
--   dar_entrada_no_estoque    recebe a nota inteira de uma vez: ou todos os
--                             itens entram, ou nenhum. Cada item soma no saldo
--                             e deixa uma linha 'in' no livro.
-- =============================================================================

alter table products
  add column if not exists barcode text;

alter table products
  drop constraint if exists products_barcode_format;

-- Sem espaco e sem vazio: o leitor manda o codigo cru, e um espaco perdido
-- faria o mesmo produto ter dois codigos que parecem iguais na tela.
alter table products
  add constraint products_barcode_format check (barcode is null or barcode ~ '^\S{1,64}$');

create unique index if not exists products_barcode_unique
  on products (restaurant_id, barcode)
  where barcode is not null and deleted_at is null;

comment on column products.barcode is
  'Codigo de barras da embalagem (EAN, GTIN ou codigo interno). Unico entre os produtos ativos da loja.';

-- -----------------------------------------------------------------------------
-- A nota de entrada
-- -----------------------------------------------------------------------------

create or replace function public.dar_entrada_no_estoque(
  p_restaurante uuid,
  p_itens jsonb,              -- [{"produto": uuid, "quantidade": int}, ...]
  p_observacao text default null
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item jsonb;
  v_produto products;
  v_quantidade int;
  v_saldo int;
  v_motivo text := coalesce(nullif(left(btrim(p_observacao), 200), ''), 'Entrada de mercadoria');
  v_total int := 0;
begin
  -- Receber mercadoria mexe no saldo que o cardapio usa para esgotar: e da
  -- gestao, como o cadastro do produto.
  if not (app.can_manage(p_restaurante) or app.is_platform_admin()) then
    raise exception 'Somente a gestao da loja da entrada no estoque.'
      using errcode = 'insufficient_privilege';
  end if;

  if jsonb_typeof(p_itens) is distinct from 'array' or jsonb_array_length(p_itens) = 0 then
    raise exception 'A entrada precisa de ao menos um item.' using errcode = 'check_violation';
  end if;

  if jsonb_array_length(p_itens) > 200 then
    raise exception 'No maximo 200 itens por entrada.' using errcode = 'check_violation';
  end if;

  for v_item in select * from jsonb_array_elements(p_itens)
  loop
    begin
      v_quantidade := (v_item ->> 'quantidade')::int;
    exception when others then
      v_quantidade := null;
    end;

    if v_quantidade is null or v_quantidade < 1 or v_quantidade > 100000 then
      raise exception 'Quantidade invalida: use um numero inteiro de 1 a 100000.'
        using errcode = 'check_violation';
    end if;

    select * into v_produto
      from products
     where id = (v_item ->> 'produto')::uuid
       and restaurant_id = p_restaurante
       and deleted_at is null
       for update;

    if v_produto.id is null then
      raise exception 'Produto nao encontrado nesta loja.' using errcode = 'no_data_found';
    end if;

    -- Dar entrada e decidir controlar: quem conta o que chegou quer ver o
    -- produto esgotar quando acabar. Saldo de quem nao controlava nao vale
    -- nada (o formulario grava zero), entao a conta parte de zero.
    update products
       set track_stock = true,
           stock_quantity = case when v_produto.track_stock then stock_quantity else 0 end
                            + v_quantidade
     where id = v_produto.id
    returning stock_quantity into v_saldo;

    insert into stock_movements (
      restaurant_id, product_id, kind, quantity, balance_after, reason, created_by
    )
    values (
      p_restaurante, v_produto.id, 'in', v_quantidade, v_saldo, v_motivo, auth.uid()
    );

    v_total := v_total + v_quantidade;
  end loop;

  return v_total;
end;
$$;

revoke all on function public.dar_entrada_no_estoque(uuid, jsonb, text) from public;
grant execute on function public.dar_entrada_no_estoque(uuid, jsonb, text) to authenticated;

comment on function public.dar_entrada_no_estoque is
  'A gestao da loja recebe mercadoria: soma cada item no saldo e registra a entrada no livro de estoque. Tudo ou nada.';
