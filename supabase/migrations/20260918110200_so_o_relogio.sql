-- =============================================================================
-- Só o relógio, como coluna à parte.
--
-- `aberto_agora` responde "vende agora?", que é o que a vitrine pergunta. O
-- painel precisa de outra resposta: POR QUE não vende — a chave da mão ou o
-- horário. Sem esta coluna o painel teria de deduzir uma da outra, e a dedução
-- é impossível: com a chave desligada, `aberto_agora` é false diga o relógio o
-- que disser, e o dono ficaria sem saber se abrir a chave resolve.
-- =============================================================================
create or replace function public.no_horario(restaurants)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select app.dentro_do_horario($1.id);
$$;

comment on function public.no_horario(restaurants) is
  'Coluna calculada: o relogio da loja diz que e hora de funcionar? Ignora a chave da mao.';

grant execute on function public.no_horario(restaurants) to anon, authenticated;
