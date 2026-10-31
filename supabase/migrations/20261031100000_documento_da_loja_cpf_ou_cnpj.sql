-- =============================================================================
-- Tronvix Facil - a loja pode se cadastrar com CPF ou CNPJ
--
-- restaurants.document so aceitava 14 digitos. Muita cozinha de bairro vende
-- sem CNPJ - quem digitava o CPF recebia, na tela, o nome cru da restricao
-- ("restaurants_document_digits"). Passa a valer CPF (11) ou CNPJ (14).
-- =============================================================================

alter table restaurants drop constraint if exists restaurants_document_digits;
alter table restaurants
  add constraint restaurants_document_digits
  check (document is null or document ~ '^([0-9]{11}|[0-9]{14})$');
