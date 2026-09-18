#!/usr/bin/env bash
# =============================================================================
# Deixa o aplicativo instalado no aparelho.
#
# Existe por causa de um detalhe do ferramental: `flutter drive` e
# `flutter test integration_test` instalam uma versao INSTRUMENTADA do
# aplicativo, rodam o teste e desinstalam ao terminar. O atalho some da tela
# inicial, e parece defeito do simulador quando e so o ciclo do teste.
#
# Nao adianta reinstalar o que sobrou em build/: o que esta la e o aplicativo
# de teste, cujo ponto de entrada e o arquivo de teste. Aberto pelo atalho, ele
# rodaria o teste em vez do aplicativo. Por isso aqui recompila de verdade.
#
# Uso:
#   ./instalar.sh                    # o primeiro simulador ligado
#   ./instalar.sh -d "iPhone 17"     # um aparelho especifico
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")"

DISPOSITIVO=""
while [ $# -gt 0 ]; do
  case "$1" in
    -d|--device-id) DISPOSITIVO="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# Sem aparelho dito, o simulador ligado.
if [ -z "$DISPOSITIVO" ]; then
  DISPOSITIVO="$(xcrun simctl list devices booted -j 2>/dev/null \
    | python3 -c "
import json,sys
d=json.load(sys.stdin)['devices']
for _, aparelhos in d.items():
    for a in aparelhos:
        if a.get('state') == 'Booted':
            print(a['udid']); raise SystemExit
" 2>/dev/null || true)"
fi

if [ -z "$DISPOSITIVO" ]; then
  echo "Nenhum simulador ligado, e nenhum aparelho informado com -d."
  exit 0
fi

# Android: o caminho e outro, e depende do adb, que nem toda maquina tem.
if ! xcrun simctl list devices -j 2>/dev/null | grep -q "$DISPOSITIVO"; then
  if command -v adb >/dev/null && adb devices | grep -q "$DISPOSITIVO"; then
    echo "==> Compilando para Android"
    ./rodar.sh --build apk --debug >/dev/null
    adb -s "$DISPOSITIVO" install -r build/app/outputs/flutter-apk/app-debug.apk
    exit 0
  fi
  echo "Nao reconheci '$DISPOSITIVO' como simulador de iOS nem aparelho Android."
  echo "O aplicativo pode ter ficado desinstalado apos os testes."
  exit 0
fi

echo "==> Recompilando o aplicativo (nao o de teste)"
./rodar.sh --build ios --simulator --debug >/dev/null

echo "==> Instalando"
xcrun simctl install "$DISPOSITIVO" build/ios/iphonesimulator/Runner.app
echo "    pronto: o atalho continua na tela inicial"
