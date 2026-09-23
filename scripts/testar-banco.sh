#!/usr/bin/env bash
# =============================================================================
# Roda as migracoes e os testes de regra num Postgres local descartavel.
#
# Existe porque o stack local do Supabase depende de Docker, e nem toda
# maquina de desenvolvimento tem um. Aqui basta um Postgres com psql: o
# arquivo supabase/tests/ambiente-local.sql reproduz o minimo do Supabase
# (papeis, schema auth, auth.uid()) para que as mesmas migracoes rodem.
#
# Uso:  npm run db:test
# =============================================================================
set -euo pipefail

BANCO="${BANCO_DE_TESTE:-tronvix_facil_teste}"
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# As migracoes sao UTF-8. No Windows o psql assume a codepage do sistema
# (WIN1252) e morre no primeiro acento; no macOS isto ja e o padrao e nao muda
# nada. Sem esta linha, `npm run db:test` nao roda em maquina Windows.
export PGCLIENTENCODING="${PGCLIENTENCODING:-UTF8}"

if ! pg_isready -q; then
  echo "Nenhum Postgres respondendo em localhost:5432."
  echo "Suba um antes de rodar os testes. Com Homebrew:"
  echo "  brew services start postgresql@17"
  exit 1
fi

echo "==> Recriando o banco de teste ($BANCO)"
dropdb --if-exists "$BANCO"
createdb "$BANCO"

echo "==> Preparando o ambiente que imita o Supabase"
psql -q -d "$BANCO" -v ON_ERROR_STOP=1 \
  -c 'create extension if not exists pgcrypto;' \
  -f "$RAIZ/supabase/tests/ambiente-local.sql" > /dev/null

echo "==> Aplicando as migracoes"
for migracao in "$RAIZ"/supabase/migrations/*.sql; do
  echo "    $(basename "$migracao")"
  psql -q -d "$BANCO" -v ON_ERROR_STOP=1 -f "$migracao" > /dev/null
done

echo "==> Verificando as regras"
# O || true e necessario: quando uma regra falha, o psql sai com codigo 1 e o
# set -e mataria o script antes de mostrar qual verificacao quebrou.
total=0
falhou=0
for teste in "$RAIZ"/supabase/tests/regras_*.sql; do
  echo "    $(basename "$teste")"
  saida=$(psql -d "$BANCO" -v ON_ERROR_STOP=1 -f "$teste" 2>&1) || true

  echo "$saida" | grep -E "NOTICE:|ERROR:" | sed -E 's/^psql:[^ ]+ //; s/^NOTICE:  //' || true

  if echo "$saida" | grep -q "ERROR:"; then
    falhou=1
  fi
  total=$(( total + $(echo "$saida" | grep -c "ok - " || true) ))
done

if [ "$falhou" -eq 1 ]; then
  echo
  echo "FALHOU: ao menos uma regra do banco nao se comportou como esperado."
  exit 1
fi

echo
echo "$total regras verificadas, todas passaram."
