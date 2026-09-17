#!/usr/bin/env bash
# =============================================================================
# Carrega os dados de demonstracao no projeto Supabase configurado.
#
# Ordem importa: primeiro o seed (estabelecimentos e cardapio), depois os
# usuarios - o script de usuarios liga cada pessoa a um estabelecimento que
# precisa ja existir.
#
# Uso:  npm run db:semente
# =============================================================================
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$RAIZ"

if [ ! -f .env.local ]; then
  echo "Falta o .env.local. Copie .env.example e preencha as chaves do Supabase."
  exit 1
fi

echo "==> Carregando dados de demonstracao"
supabase db push --include-seed

echo "==> Criando usuarios de teste"
node scripts/criar-usuarios-de-teste.mjs
