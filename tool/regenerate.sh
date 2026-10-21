#!/bin/bash
# v1.1 で freezed + json_serializable を導入したため、新規 / 修正したモデルから
# *.freezed.dart と *.g.dart を生成する。
#
# 流れ:
#   1. flutter pub get
#   2. dart run build_runner build --delete-conflicting-outputs
#
# 既存の hand-crafted モデル (PersonalProfile / CalibrationSample / NotificationPreferences)
# は短縮キー JSON のため freezed では未移行。今後段階移行する。

set -euo pipefail

cd "$(dirname "$0")/.."

echo "[regenerate] flutter pub get"
flutter pub get

echo "[regenerate] dart run build_runner build --delete-conflicting-outputs"
dart run build_runner build --delete-conflicting-outputs

echo "[regenerate] flutter gen-l10n (i18n .arb → .dart)"
flutter gen-l10n

echo "[regenerate] done. flutter analyze で確認することを推奨。"
