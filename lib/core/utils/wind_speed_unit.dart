// lib/core/utils/wind_speed_unit.dart
//
// 風速単位 (m/s / km/h / mph) の純 Dart ユーティリティ (設定 › 一般、
// docs/design-metric-units-proposal.md §2.6)。
// データ層 (WeatherSnapshot.windSpeed) は常に m/s で持ち、表示直前にのみ換算する
// (temperature_unit.dart と同じ方針)。判定の閾値 (暴風 20 / 30 m/s など) は m/s のまま。
// 記号 (m/s・km/h・mph) は訳さない。Flutter 非依存 — ユニットテスト対象。

/// 表示用の風速単位。並びは設定の切替の順 (m/s | km/h | mph)。
enum WindSpeedUnit { metersPerSecond, kilometersPerHour, milesPerHour }

/// 1 m/s あたりの km/h (定義値)。
const double kKilometersPerHourPerMeterPerSecond = 3.6;

/// 1 m/s あたりの mph (1 mile = 1609.344 m → 3600 / 1609.344)。
const double kMilesPerHourPerMeterPerSecond = 2.2369362920544;

/// 改行しない空白 (U+00A0)。通知の本文で数値と単位を離さない。
const String kNoBreakSpace = '\u00A0';

/// 幅 0 の結合子 (U+2060 WORD JOINER)。前後で行を分けさせない。
const String kWordJoiner = '\u2060';

extension WindSpeedUnitX on WindSpeedUnit {
  /// m/s の生値を、この単位の値へ換算する (丸めない)。
  double fromMetersPerSecond(double metersPerSecond) => switch (this) {
        WindSpeedUnit.metersPerSecond => metersPerSecond,
        WindSpeedUnit.kilometersPerHour =>
          metersPerSecond * kKilometersPerHourPerMeterPerSecond,
        WindSpeedUnit.milesPerHour =>
          metersPerSecond * kMilesPerHourPerMeterPerSecond,
      };

  /// 記号。訳さず、大文字にもしない (「M/S」は M = メガになる)。
  String get symbol => switch (this) {
        WindSpeedUnit.metersPerSecond => 'm/s',
        WindSpeedUnit.kilometersPerHour => 'km/h',
        WindSpeedUnit.milesPerHour => 'mph',
      };

  /// 折り返しのある文の中に置く記号: 「/」の前後に U+2060 を入れ、記号の途中
  /// (「km/」「h」) で行が分かれないようにする。見た目と読み上げは [symbol] と同じ。
  /// 1 行に固定して組む場所 (タイル・設定の切替・通知の数値の直後) は [symbol] のまま。
  /// QA-20 (Comfort-Twin の比較の見出し「Wind (km/h)」)。
  String get nonBreakingSymbol =>
      symbol.replaceAll('/', '$kWordJoiner/$kWordJoiner');

  /// 表示の小数桁数 (m/s は 1 桁、km/h・mph は整数)。
  int get fractionDigits => this == WindSpeedUnit.metersPerSecond ? 1 : 0;

  /// タイルの値 (単位なし): 3.2 m/s → "3.2" / "12" (km/h) / "7" (mph)。四捨五入。
  String formatValue(double metersPerSecond) =>
      fromMetersPerSecond(metersPerSecond).toStringAsFixed(fractionDigits);

  /// 整数に丸めて単位を付ける: 20 m/s → "20 m/s" / "72 km/h" / "45 mph"。
  /// 緊急通知 (暴風) の本文用 (compliance-review-v1.3.0 §9-4 U1・U2・U6):
  ///   - 数値と単位はここで 1 つにまとめて作る (ARB に単位を書かない。数値だけ換算
  ///     し忘れて単位だけ変わる、という過小表示を起こさない)
  ///   - 換算は丸める前の m/s から 1 回だけ、四捨五入 (切り捨て・二重丸めはしない)
  ///   - 数値と単位のあいだは改行しない空白 U+00A0 (通知の折り返しで単位だけが
  ///     次の行に落ちないように)
  String formatRounded(double metersPerSecond) =>
      '${fromMetersPerSecond(metersPerSecond).round()}$kNoBreakSpace$symbol';

  /// 永続化用タグ (enum 名)。
  String toTag() => name;

  /// タグから復元。未知の値・null は null (呼び出し側が初期値を決める)。
  static WindSpeedUnit? tryParse(String? tag) {
    for (final unit in WindSpeedUnit.values) {
      if (unit.name == tag) return unit;
    }
    return null;
  }
}
