// lib/core/utils/temperature_unit.dart
//
// 温度単位 (°C / °F) の純 Dart ユーティリティ (spec.md §4.4 設定 > 一般)。
// データ層 (WeatherSnapshot) は常に摂氏で保持し、表示直前にのみ換算する。
// Flutter 非依存 — ユニットテスト対象 (MRI 計算と同じ方針)。

/// 表示用の温度単位。
enum TemperatureUnit { celsius, fahrenheit }

extension TemperatureUnitX on TemperatureUnit {
  /// 摂氏の生値を、この単位の値へ換算する (丸めない)。
  double fromCelsius(double celsius) =>
      this == TemperatureUnit.celsius ? celsius : celsius * 9 / 5 + 32;

  /// 摂氏の生値を「22°」のような表示文字列にする (整数へ四捨五入)。
  String formatDegrees(double celsius) => '${fromCelsius(celsius).round()}°';

  /// 摂氏の **差** を「+1.5°」「-0.6°」のような表示文字列にする (小数 1 桁)。
  /// 差なので華氏は ×9/5 だけで 32 は足さない (+1.5°C → +2.7°)。0 は「+0.0°」
  /// (丸めて 0 になる負の値も「-0.0°」にしない)。単位記号は付けない
  /// (アプリの気温の表記「22°」と同じ。単位は設定で決まる)。
  String formatDegreesDelta(double celsiusDelta) {
    final delta =
        this == TemperatureUnit.celsius ? celsiusDelta : celsiusDelta * 9 / 5;
    final shown = delta.abs().toStringAsFixed(1);
    final negative = delta < 0 && double.parse(shown) != 0;
    return '${negative ? '-' : '+'}$shown°';
  }

  /// 永続化用タグ ("celsius" / "fahrenheit")。
  String toTag() => name;

  /// タグから復元。未知の値は摂氏にフォールバック。
  static TemperatureUnit parse(String? tag) =>
      tryParse(tag) ?? TemperatureUnit.celsius;

  /// タグから復元。未知の値・null は null (呼び出し側が初期値を決める)。
  static TemperatureUnit? tryParse(String? tag) {
    for (final unit in TemperatureUnit.values) {
      if (unit.name == tag) return unit;
    }
    return null;
  }
}
