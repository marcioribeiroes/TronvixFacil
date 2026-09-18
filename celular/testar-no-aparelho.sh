#!/usr/bin/env bash
# =============================================================================
# Roda os testes de integracao no aparelho, com as chaves do projeto.
#
#   ./testar-no-aparelho.sh                              # tudo, no aparelho padrao
#   ./testar-no-aparelho.sh -d "iPhone 17"               # tudo, num aparelho
#   ./testar-no-aparelho.sh -d "iPhone 17" mesa_test     # so esse teste
#
# O nome do teste pode vir curto: "mesa" acha integration_test/mesa_test.dart.
# =============================================================================
set -uo pipefail
cd "$(dirname "$0")"

# O ferramental desinstala o aplicativo ao terminar o teste. O trap reinstala,
# passando ou falhando — senao o atalho some da tela inicial toda vez que
# alguem roda os testes, e a culpa parece ser do simulador.
#
# Sem -d, e de proposito: testar no iPhone e depois no Android deixava o
# primeiro vazio, porque o trap so cuidava do aparelho daquela rodada. O
# --se-faltar pula quem ainda tem o aplicativo, entao cobrir todos nao custa
# compilacao a mais.
trap './instalar.sh --se-faltar || true' EXIT

# Separa o que e do flutter (-d, --flag) do que e nome de teste. Antes tudo ia
# para o fim da linha, depois da pasta — e `flutter test integration_test
# mesa_test.dart` roda a pasta INTEIRA, ignorando o arquivo em silencio.
ALVO=""
OPCOES=()
while [ $# -gt 0 ]; do
  case "$1" in
    -d|--device-id) OPCOES+=("$1" "$2"); shift 2 ;;
    -*) OPCOES+=("$1"); shift ;;
    *) ALVO="$1"; shift ;;
  esac
done

if [ -n "$ALVO" ]; then
  # Aceita "mesa", "mesa_test" e o caminho inteiro.
  for tentativa in "$ALVO" "integration_test/$ALVO" \
                   "integration_test/${ALVO}_test.dart" "integration_test/$ALVO.dart"; do
    if [ -f "$tentativa" ]; then ALVO="$tentativa"; break; fi
  done
  if [ ! -f "$ALVO" ]; then
    echo "Nao achei o teste: $ALVO"
    echo "Os que existem:"
    ls integration_test/*_test.dart | sed 's|integration_test/|  |; s|_test.dart||'
    exit 1
  fi
else
  ALVO="integration_test"
fi

ler() { grep -E "^$1=" ../.env.local | tail -1 | cut -d= -f2- | sed 's/^"//; s/"$//'; }

echo "==> $ALVO"
flutter test "$ALVO" \
  --dart-define=SUPABASE_URL="$(ler NEXT_PUBLIC_SUPABASE_URL)" \
  --dart-define=SUPABASE_ANON_KEY="$(ler NEXT_PUBLIC_SUPABASE_ANON_KEY)" \
  "${OPCOES[@]:-}"
