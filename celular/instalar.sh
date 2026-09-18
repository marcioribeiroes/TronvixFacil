#!/usr/bin/env bash
# =============================================================================
# Deixa o aplicativo instalado em TODO aparelho ligado.
#
# Por que existe: `flutter drive` e `flutter test integration_test` instalam uma
# versao instrumentada do aplicativo, rodam o teste e DESINSTALAM ao terminar. O
# atalho some da tela inicial, e parece defeito do simulador quando e so o ciclo
# do teste.
#
# A primeira versao instalava num aparelho so, o que era passado com -d. Bastava
# rodar um teste no iPhone e outro no Android para o segundo ficar vazio — e foi
# exatamente o que aconteceu. Agora, sem argumento, ele cobre todos: cada
# simulador de iOS ligado e cada aparelho que o adb enxerga.
#
# Nao adianta reinstalar o que sobrou em build/: o que esta la pode ser o
# aplicativo de teste, cujo ponto de entrada e o arquivo de teste. Aberto pelo
# atalho, ele rodaria o teste em vez do aplicativo. Por isso aqui recompila.
#
# Uso:
#   ./instalar.sh                    # todos os aparelhos ligados
#   ./instalar.sh -d "iPhone 17"     # so um, pelo nome ou pelo identificador
#   ./instalar.sh --se-faltar        # so onde o aplicativo sumiu
#   ./instalar.sh --conferir         # so diz onde esta e onde nao esta
# =============================================================================
set -uo pipefail
cd "$(dirname "$0")"

ALVO=""
SE_FALTAR=0
CONFERIR=0
while [ $# -gt 0 ]; do
  case "$1" in
    -d|--device-id) ALVO="$2"; shift 2 ;;
    --se-faltar) SE_FALTAR=1; shift ;;
    --conferir) CONFERIR=1; shift ;;
    *) shift ;;
  esac
done

IOS_ID="br.com.tronvix.tronvixFacil"
ANDROID_ID="br.com.tronvix.tronvix_facil"

# --- quem esta ligado --------------------------------------------------------
simuladores=()
while IFS= read -r linha; do
  [ -n "$linha" ] && simuladores+=("$linha")
done < <(xcrun simctl list devices booted -j 2>/dev/null | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)['devices']
except Exception:
    raise SystemExit
for _, aparelhos in d.items():
    for a in aparelhos:
        if a.get('state') == 'Booted':
            print(f\"{a['udid']}\t{a['name']}\")
" 2>/dev/null)

androides=()
if command -v adb >/dev/null; then
  while IFS= read -r linha; do
    [ -n "$linha" ] && androides+=("$linha")
  done < <(adb devices 2>/dev/null | awk '/\tdevice$/ {print $1}')
fi

# Com -d, fica so o que casar com o nome ou o identificador.
if [ -n "$ALVO" ]; then
  filtrados=()
  for s in "${simuladores[@]:-}"; do
    [ -n "$s" ] && case "$s" in *"$ALVO"*) filtrados+=("$s") ;; esac
  done
  simuladores=("${filtrados[@]:-}")

  filtrados=()
  for a in "${androides[@]:-}"; do
    [ -n "$a" ] && case "$a" in *"$ALVO"*) filtrados+=("$a") ;; esac
  done
  androides=("${filtrados[@]:-}")
fi

# Arrays vazios com `set -u` viram erro; esta forma os deixa contaveis.
qtd_ios=$(printf '%s\n' "${simuladores[@]:-}" | grep -c . || true)
qtd_android=$(printf '%s\n' "${androides[@]:-}" | grep -c . || true)

if [ "$qtd_ios" -eq 0 ] && [ "$qtd_android" -eq 0 ]; then
  echo "Nenhum simulador ligado e nenhum aparelho conectado."
  exit 0
fi

# --- quem ja tem o aplicativo ------------------------------------------------
# Os modos --se-faltar e --conferir existem pelo mesmo motivo: compilar custa
# dois minutos por plataforma, e depois de um teste no iPhone o Android continua
# com o aplicativo. Sem esta conferencia, o trap dos testes pagaria as duas
# compilacoes toda vez.
# A saida vai para uma variavel antes do grep, e nao por cano.
#
# Com `set -o pipefail`, `xcrun ... | grep -q` mente: o grep acha, sai na hora e
# fecha o cano; o xcrun morre com SIGPIPE; o pipefail ve o erro do xcrun e
# devolve falha. O aplicativo estava instalado e o script jurava que nao — foi
# assim que a conferencia disse SUMIU logo depois de instalar.
tem_no_ios() {
  local lista
  lista="$(xcrun simctl listapps "$1" 2>/dev/null)"
  case "$lista" in *"$IOS_ID"*) return 0 ;; *) return 1 ;; esac
}

tem_no_android() {
  local lista
  lista="$(adb -s "$1" shell pm list packages 2>/dev/null)"
  case "$lista" in *"$ANDROID_ID"*) return 0 ;; *) return 1 ;; esac
}

if [ "$CONFERIR" -eq 1 ]; then
  for s in "${simuladores[@]:-}"; do
    [ -z "$s" ] && continue
    udid="${s%%$'\t'*}"; nome="${s##*$'\t'}"
    tem_no_ios "$udid" && echo "  $nome: instalado" || echo "  $nome: SUMIU"
  done
  for a in "${androides[@]:-}"; do
    [ -z "$a" ] && continue
    tem_no_android "$a" && echo "  $a: instalado" || echo "  $a: SUMIU"
  done
  exit 0
fi

# Em --se-faltar, quem ja tem sai da lista antes de qualquer compilacao.
if [ "$SE_FALTAR" -eq 1 ]; then
  filtrados=()
  for s in "${simuladores[@]:-}"; do
    [ -z "$s" ] && continue
    tem_no_ios "${s%%$'\t'*}" || filtrados+=("$s")
  done
  simuladores=("${filtrados[@]:-}")

  filtrados=()
  for a in "${androides[@]:-}"; do
    [ -z "$a" ] && continue
    tem_no_android "$a" || filtrados+=("$a")
  done
  androides=("${filtrados[@]:-}")

  qtd_ios=$(printf '%s\n' "${simuladores[@]:-}" | grep -c . || true)
  qtd_android=$(printf '%s\n' "${androides[@]:-}" | grep -c . || true)

  if [ "$qtd_ios" -eq 0 ] && [ "$qtd_android" -eq 0 ]; then
    echo "    o aplicativo continua em todos os aparelhos ligados"
    exit 0
  fi
fi

# --- iOS ---------------------------------------------------------------------
# Uma compilacao so, mesmo para tres simuladores: o app de simulador serve a
# todos, e recompilar por aparelho seria dois minutos jogados fora em cada.
if [ "$qtd_ios" -gt 0 ]; then
  echo "==> Compilando para iOS"
  if ./rodar.sh --build ios --simulator --debug >/dev/null 2>&1; then
    for s in "${simuladores[@]}"; do
      [ -z "$s" ] && continue
      udid="${s%%$'\t'*}"
      nome="${s##*$'\t'}"
      if xcrun simctl install "$udid" build/ios/iphonesimulator/Runner.app 2>/dev/null; then
        echo "    $nome"
      else
        echo "    $nome — falhou"
      fi
    done
  else
    echo "    a compilacao falhou; os simuladores ficam sem o aplicativo"
  fi
fi

# --- Android -----------------------------------------------------------------
if [ "$qtd_android" -gt 0 ]; then
  echo "==> Compilando para Android"
  if ./rodar.sh --build apk --debug >/dev/null 2>&1; then
    for a in "${androides[@]}"; do
      [ -z "$a" ] && continue
      if adb -s "$a" install -r build/app/outputs/flutter-apk/app-debug.apk >/dev/null 2>&1; then
        echo "    $a"
      else
        echo "    $a — falhou"
      fi
    done
  else
    echo "    a compilacao falhou; o emulador fica sem o aplicativo"
  fi
fi

echo "    pronto: o atalho continua na tela inicial"
