#!/usr/bin/env bash
# Fotografa as telas do aplicativo rodando contra o Supabase do projeto.
# As imagens caem em celular/capturas/.
#   ./passear.sh -d "iPhone 17"
set -uo pipefail
cd "$(dirname "$0")"

# O ferramental desinstala o aplicativo ao terminar o teste. O trap reinstala,
# passando ou falhando — senao o atalho some da tela inicial toda vez que
# alguem roda os testes, e a culpa parece ser do simulador.
ARGUMENTOS=("$@")
trap './instalar.sh "${ARGUMENTOS[@]}" || true' EXIT

ler() { grep -E "^$1=" ../.env.local | tail -1 | cut -d= -f2- | sed 's/^"//; s/"$//'; }

flutter drive \
  --driver=test_driver/integration_driver.dart \
  --target=integration_test/passeio_test.dart \
  --dart-define=SUPABASE_URL="$(ler NEXT_PUBLIC_SUPABASE_URL)" \
  --dart-define=SUPABASE_ANON_KEY="$(ler NEXT_PUBLIC_SUPABASE_ANON_KEY)" \
  "$@"
