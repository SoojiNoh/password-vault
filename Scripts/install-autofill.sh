#!/bin/bash
# 크롬 자동완성 붙이기.
#
#   ./Scripts/install-autofill.sh            설치
#   ./Scripts/install-autofill.sh --uninstall  제거
#
# 하는 일은 하나입니다. 크롬에게 "이 확장이 이 프로그램과 이야기해도 된다"고 알려 주는
# 파일 하나를 만듭니다. 비밀번호는 이 파일을 지나가지 않습니다.
set -euo pipefail

EXT_ID="fnomagecdbekelhnahanfljhmlhgfpdi"
HOST_NAME="com.github.soojinoh.passwordvault"
APP="${PASSWORD_VAULT_APP:-}"

# 크롬 계열 브라우저들의 설정 폴더
DIRS=(
  "$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
  "$HOME/Library/Application Support/Google/Chrome Beta/NativeMessagingHosts"
  "$HOME/Library/Application Support/Chromium/NativeMessagingHosts"
  "$HOME/Library/Application Support/Microsoft Edge/NativeMessagingHosts"
  "$HOME/Library/Application Support/BraveSoftware/Brave-Browser/NativeMessagingHosts"
)

if [[ "${1:-}" == "--uninstall" ]]; then
  for d in "${DIRS[@]}"; do rm -f "$d/$HOST_NAME.json"; done
  echo "지웠습니다. 크롬에서 확장도 함께 제거해 주세요."
  exit 0
fi

# 앱 위치 찾기
if [[ -z "$APP" ]]; then
  for c in "/Applications/PasswordVault.app" \
           "$HOME/Applications/PasswordVault.app" \
           "$(cd "$(dirname "$0")/.." && pwd)/build/PasswordVault.app"; do
    [[ -x "$c/Contents/MacOS/PasswordVault" ]] && APP="$c" && break
  done
fi
if [[ -z "$APP" || ! -x "$APP/Contents/MacOS/PasswordVault" ]]; then
  echo "PasswordVault.app 을 찾지 못했습니다." >&2
  echo "  ./Scripts/build-app.sh 로 먼저 빌드하거나," >&2
  echo "  PASSWORD_VAULT_APP=/응용프로그램/경로/PasswordVault.app $0 처럼 알려 주세요." >&2
  exit 1
fi
BIN="$APP/Contents/MacOS/PasswordVault"

made=0
for d in "${DIRS[@]}"; do
  parent="$(dirname "$d")"
  [[ -d "$parent" ]] || continue          # 안 깔린 브라우저는 건너뛴다
  mkdir -p "$d"
  cat > "$d/$HOST_NAME.json" <<JSON
{
  "name": "$HOST_NAME",
  "description": "비밀번호 금고 자동완성 다리",
  "path": "$BIN",
  "type": "stdio",
  "allowed_origins": ["chrome-extension://$EXT_ID/"]
}
JSON
  chmod 600 "$d/$HOST_NAME.json"
  echo "  등록: $d/$HOST_NAME.json"
  made=$((made+1))
done

if [[ $made -eq 0 ]]; then
  echo "크롬 계열 브라우저를 찾지 못했습니다." >&2
  exit 1
fi

EXT_DIR="$(cd "$(dirname "$0")/.." && pwd)/extension"
cat <<MSG

앱 위치: $BIN

이제 크롬에서 확장을 한 번만 넣어 주세요.
  1. 주소창에 chrome://extensions 를 붙여넣기
  2. 오른쪽 위 '개발자 모드' 켜기
  3. '압축해제된 확장 프로그램을 로드합니다' → 아래 폴더 고르기
     $EXT_DIR
  4. 확장 ID 가 $EXT_ID 인지 확인 (다르면 이 스크립트를 다시 실행하세요)

금고 앱을 열어 잠금을 풀어 두면, 로그인 칸을 누를 때 목록이 뜹니다.
MSG
