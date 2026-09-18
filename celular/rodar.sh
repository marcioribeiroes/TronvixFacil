#!/usr/bin/env bash
# =============================================================================
# Sobe o aplicativo de celular com as chaves do projeto.
#
# No celular nao existe .env: o que o aplicativo sabe do mundo entra na
# compilacao. Este script le o mesmo .env.local que a web usa e converte em
# --dart-define, para nao haver duas verdades sobre qual Supabase e o certo.
#
# Uso:
#   ./rodar.sh                    escolhe o dispositivo conectado
#   ./rodar.sh -d "iPhone 17"     simulador de iOS
#   ./rodar.sh -d emulator-5554   emulador de Android
#   ./rodar.sh --build ios        compila em vez de rodar
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")"

ENV_LOCAL="../.env.local"

if [ ! -f "$ENV_LOCAL" ]; then
  echo "Nao encontrei $ENV_LOCAL."
  echo "Copie ../.env.example para ../.env.local e preencha as chaves do Supabase."
  echo
  echo "O aplicativo sobe assim mesmo, mas abre na tela que explica o que falta."
  echo
fi

ler() {
  [ -f "$ENV_LOCAL" ] || return 0
  # Ignora comentarios e linhas vazias; nao usa `source` de proposito, para que
  # um valor com espaco ou aspas nao vire comando.
  grep -E "^$1=" "$ENV_LOCAL" | tail -1 | cut -d= -f2- | sed 's/^"//; s/"$//'
}

URL="$(ler NEXT_PUBLIC_SUPABASE_URL)"
CHAVE="$(ler NEXT_PUBLIC_SUPABASE_ANON_KEY)"
MARCA="$(ler NEXT_PUBLIC_NOME_DA_MARCA)"

# Identidade do aplicativo. Tudo opcional: sem nada disto, sai o Tronvix Facil
# em modo multi, que e o padrao.
#
#   CELULAR_MODO=unique               uma loja so, sem vitrine
#   CELULAR_ESTABELECIMENTO=burger-house   o slug dela
#   CELULAR_COR_DA_MARCA=0xFFE11D2F   ARGB
MODO="$(ler CELULAR_MODO)"
LOJA="$(ler CELULAR_ESTABELECIMENTO)"
COR="$(ler CELULAR_COR_DA_MARCA)"
COR_ESCURA="$(ler CELULAR_COR_DA_MARCA_ESCURA)"
COR_REALCE="$(ler CELULAR_COR_DE_REALCE)"

DEFINES=(
  --dart-define=SUPABASE_URL="${URL:-}"
  --dart-define=SUPABASE_ANON_KEY="${CHAVE:-}"
)
[ -n "${MARCA:-}" ] && DEFINES+=(--dart-define=NOME_DA_MARCA="$MARCA")
[ -n "${MODO:-}" ] && DEFINES+=(--dart-define=MODO="$MODO")
[ -n "${LOJA:-}" ] && DEFINES+=(--dart-define=ESTABELECIMENTO="$LOJA")
[ -n "${COR:-}" ] && DEFINES+=(--dart-define=COR_DA_MARCA="$COR")
[ -n "${COR_ESCURA:-}" ] && DEFINES+=(--dart-define=COR_DA_MARCA_ESCURA="$COR_ESCURA")
[ -n "${COR_REALCE:-}" ] && DEFINES+=(--dart-define=COR_DE_REALCE="$COR_REALCE")

if [ "${1:-}" = "--build" ]; then
  shift
  exec flutter build "$@" "${DEFINES[@]}"
fi

exec flutter run "${DEFINES[@]}" "$@"
