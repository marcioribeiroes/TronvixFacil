-- =============================================================================
-- O código do Pix é montado pelo BANCO.
--
-- A primeira tentativa montava o BR Code no servidor do Next e gravava em
-- `payments` logo depois de fechar o pedido. Não funcionou, e a RLS estava
-- certa: o cliente não pode escrever em `payments`. O update não pegava
-- nenhuma linha, em silêncio, e o cliente via a tela de pagamento vazia.
--
-- A correção não é afrouxar a política. É a mesma regra que sustenta o projeto
-- inteiro — "o preço não vem do aplicativo" — aplicada ao dinheiro que vai
-- entrar numa conta: a chave de quem recebe e o valor cobrado saem do banco,
-- junto com o pedido, na mesma transação. Nem o aplicativo nem o navegador têm
-- como trocar a chave por outra.
--
-- O formato é o EMV® QRCPS do Banco Central: campos id+tamanho+valor, com um
-- CRC16/CCITT-FALSE no fim, calculado sobre o texto inteiro já com "6304".
-- =============================================================================

-- -----------------------------------------------------------------------------
-- CRC16/CCITT-FALSE
-- -----------------------------------------------------------------------------
-- Polinômio 0x1021, inicial 0xFFFF, sem reflexão, sem XOR final. O valor de
-- conferência do algoritmo para "123456789" é 29B1 — está nos testes.
create or replace function app.crc16(p_texto text)
returns text
language plpgsql
immutable
as $$
declare
  v_crc int := 65535;  -- 0xFFFF
  i int;
  b int;
begin
  for i in 1 .. length(p_texto) loop
    v_crc := v_crc # (ascii(substr(p_texto, i, 1)) * 256);
    v_crc := v_crc & 65535;

    for b in 1 .. 8 loop
      if (v_crc & 32768) <> 0 then          -- 0x8000
        v_crc := ((v_crc * 2) # 4129) & 65535;  -- 0x1021
      else
        v_crc := (v_crc * 2) & 65535;
      end if;
    end loop;
  end loop;

  return upper(lpad(to_hex(v_crc), 4, '0'));
end;
$$;

-- -----------------------------------------------------------------------------
-- Um campo do BR Code: id, tamanho em dois dígitos, valor
-- -----------------------------------------------------------------------------
create or replace function app.campo_emv(p_id text, p_valor text)
returns text
language sql
immutable
as $$
  select p_id || lpad(length(p_valor)::text, 2, '0') || p_valor;
$$;

-- -----------------------------------------------------------------------------
-- Nome e cidade, como o padrão aceita
-- -----------------------------------------------------------------------------
-- Aparecem no aplicativo do banco na hora de confirmar. Acento vira caractere
-- estranho em parte dos bancos, e o padrão limita o tamanho.
create or replace function app.texto_emv(p_texto text, p_limite int)
returns text
language sql
immutable
as $$
  select upper(
    substr(
      regexp_replace(
        translate(coalesce(p_texto, ''),
          'áàâãäéèêëíìîïóòôõöúùûüçñÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ',
          'aaaaaeeeeiiiiooooouuuucnAAAAAEEEEIIIIOOOOOUUUUCN'),
        '[^A-Za-z0-9 .\-]', '', 'g'),
      1, p_limite)
  );
$$;

-- -----------------------------------------------------------------------------
-- A chave, no formato que o BR Code quer
-- -----------------------------------------------------------------------------
create or replace function app.chave_pix_normalizada(p_chave text, p_tipo text)
returns text
language plpgsql
immutable
as $$
declare
  v_digitos text := regexp_replace(coalesce(p_chave, ''), '\D', '', 'g');
begin
  return case p_tipo
    when 'cpf'  then v_digitos
    when 'cnpj' then v_digitos
    -- O padrão pede o formato internacional: +5562990000000.
    when 'telefone' then '+55' || case
      when length(v_digitos) > 11 and left(v_digitos, 2) = '55'
      then substr(v_digitos, 3)
      else v_digitos
    end
    when 'email' then lower(trim(p_chave))
    else trim(p_chave)
  end;
end;
$$;

-- -----------------------------------------------------------------------------
-- O BR Code inteiro
-- -----------------------------------------------------------------------------
create or replace function app.brcode_pix(
  p_chave text,
  p_tipo text,
  p_nome text,
  p_cidade text,
  p_centavos bigint,
  p_identificador text default null
)
returns text
language plpgsql
immutable
as $$
declare
  v_conta text;
  v_txid text;
  v_sem_crc text;
begin
  if p_chave is null or p_tipo is null then return null; end if;

  v_conta := app.campo_emv('00', 'br.gov.bcb.pix')
          || app.campo_emv('01', app.chave_pix_normalizada(p_chave, p_tipo));

  -- "***" é o valor que o padrão define para "sem identificador".
  v_txid := coalesce(
    nullif(substr(regexp_replace(coalesce(p_identificador, ''), '[^A-Za-z0-9]', '', 'g'), 1, 25), ''),
    '***');

  v_sem_crc :=
       app.campo_emv('00', '01')
    || app.campo_emv('26', v_conta)
    -- 52: ramo de atividade não informado. 53: moeda 986, o real.
    || app.campo_emv('52', '0000')
    || app.campo_emv('53', '986')
    || app.campo_emv('54', to_char(p_centavos / 100.0, 'FM999999990.00'))
    || app.campo_emv('58', 'BR')
    || app.campo_emv('59', app.texto_emv(p_nome, 25))
    || app.campo_emv('60', app.texto_emv(p_cidade, 15))
    || app.campo_emv('62', app.campo_emv('05', v_txid))
    || '6304';

  return v_sem_crc || app.crc16(v_sem_crc);
end;
$$;

comment on function app.brcode_pix is
  'O "copia e cola" do Pix, montado pelo banco. A chave de quem recebe e o valor cobrado nao passam pelo aplicativo.';
