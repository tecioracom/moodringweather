#!/usr/bin/env bash
# 接続中の Android 端末の画面を device-captures/ に PNG 保存する。
# 使い方: bash tool/screenshot.sh  (または chmod +x 後 ./tool/screenshot.sh)
set -euo pipefail

ADB="${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb"
[ -x "$ADB" ] || { echo "adb が見つかりません: $ADB"; exit 1; }

# 端末接続チェック
if ! "$ADB" get-state 1>/dev/null 2>&1; then
  echo "端末が接続されていません。USB接続とUSBデバッグ許可を確認してください。"
  "$ADB" devices
  exit 1
fi

DIR="$(cd "$(dirname "$0")/.." && pwd)/device-captures"
mkdir -p "$DIR"
TS=$(date +%Y%m%d_%H%M%S)
OUT="$DIR/screen_$TS.png"

"$ADB" exec-out screencap -p > "$OUT"
echo "保存しました: $OUT"
