// lib/presentation/shared/metric_tiles.dart
//
// ホーム・詳細の指標タイルの中身 (見出し・値・後ろの文字・読み上げ) を 1 か所で組む
// (docs/design-metric-units-proposal.md §2・§3.6)。
//
//   湿度   整数 + 単位「%」
//   風     風速の単位の設定で換算 (m/s は小数 1 桁、km/h・mph は整数) + 記号
//   UV     整数 (四捨五入) + 段階語 (WHO・気象庁 5 区分、表示中の整数で判定)
//   空気質 整数の US AQI + 段階語 (US EPA 6 区分)
//   気圧   整数 + 単位「hPa」
//   気温   formatDegrees の「22°」(単位は設定で決まるので付けない)
//
// 値が無い (null) ときは「—」(textLo) で、後ろの文字は出さない (§3.5)。
// 読み上げは「見出し 値 後ろの文字」。記号は読み方に置き換え (m/s → メートル毎秒)、
// en の空気質の区分 3 の短縮語 (Poor) は EPA の正式名で読む。en の区分 5 は正式名
// 「Very unhealthy」を表示する (3 桁の値のあとには入らないので値の下の行へ回る。
// compliance-review-v1.3.0 §9-2 で §4.1 の例外として許容)。

import '../../core/utils/temperature_unit.dart';
import '../../core/utils/wind_speed_unit.dart';
import '../../domain/metrics/metric_levels.dart';
import '../../l10n/app_localizations.dart';
import 'quiet_glyphs.dart';
import 'quiet_metric_tile.dart';

/// 値が無いときの表示。
const String kMissingMetricValue = '—';

/// UV の段階語 (タイルの表示と読み上げで同じ語)。
String uvLevelLabel(AppLocalizations t, UvLevel level) => switch (level) {
      UvLevel.low => t.uvLevelLow,
      UvLevel.moderate => t.uvLevelModerate,
      UvLevel.high => t.uvLevelHigh,
      UvLevel.veryHigh => t.uvLevelVeryHigh,
      UvLevel.extreme => t.uvLevelExtreme,
    };

/// 空気質の段階語 (タイルの表示)。
String aqiLevelLabel(AppLocalizations t, AqiLevel level) => switch (level) {
      AqiLevel.good => t.aqiLevelGood,
      AqiLevel.moderate => t.aqiLevelModerate,
      AqiLevel.unhealthyForSensitiveGroups => t.aqiLevelUnhealthySensitive,
      AqiLevel.unhealthy => t.aqiLevelUnhealthy,
      AqiLevel.veryUnhealthy => t.aqiLevelVeryUnhealthy,
      AqiLevel.hazardous => t.aqiLevelHazardous,
    };

/// 空気質の段階語の読み上げ。en の区分 3 の短縮語「Poor」だけ EPA の正式名
/// (Unhealthy for sensitive groups) で読む。他言語・他の区分は表示と同じ語。
String aqiLevelSpoken(AppLocalizations t, AqiLevel level) => switch (level) {
      AqiLevel.unhealthyForSensitiveGroups => t.aqiLevelUnhealthySensitiveA11y,
      _ => aqiLevelLabel(t, level),
    };

/// 温度の単位の読み方 (設定 › 一般の切替の「°C / °F」「℃ / ℉」)。
String temperatureUnitSpoken(AppLocalizations t, TemperatureUnit unit) =>
    switch (unit) {
      TemperatureUnit.celsius => t.unitCelsiusA11y,
      TemperatureUnit.fahrenheit => t.unitFahrenheitA11y,
    };

/// 風速の単位の読み方 (記号は表示のまま訳さない)。
String windSpeedUnitSpoken(AppLocalizations t, WindSpeedUnit unit) =>
    switch (unit) {
      WindSpeedUnit.metersPerSecond => t.unitMetersPerSecondA11y,
      WindSpeedUnit.kilometersPerHour => t.unitKilometersPerHourA11y,
      WindSpeedUnit.milesPerHour => t.unitMilesPerHourA11y,
    };

/// 指標タイルの組み立て。[height] はホーム 72 / 詳細 84。
class MetricTiles {
  const MetricTiles(this.t, {this.height = 72, this.labelMaxLines = 1});

  final AppLocalizations t;
  final double height;
  final int labelMaxLines;

  QuietMetricTile _tile({
    required QuietIcon icon,
    required String label,
    required String? value,
    String unit = '',
    String level = '',
    String spoken = '',
  }) {
    final missing = value == null;
    final shown = value ?? kMissingMetricValue;
    return QuietMetricTile(
      icon: icon,
      label: label.toUpperCase(),
      value: shown,
      unit: missing ? '' : unit,
      level: missing ? '' : level,
      semanticsLabel: [label, shown, if (!missing) spoken]
          .where((s) => s.isNotEmpty)
          .join(' '),
      muted: missing,
      height: height,
      labelMaxLines: labelMaxLines,
    );
  }

  /// 湿度 (整数 + %)。「%」の読み方は OS の読み上げに任せる。
  QuietMetricTile humidity(double? percent) => _tile(
        icon: QuietIcon.humidity,
        label: t.statHumidity,
        value: percent == null ? null : '${percent.round()}',
        unit: '%',
        spoken: '%',
      );

  /// 風 (風速の単位で換算 + 記号)。
  QuietMetricTile wind(double? metersPerSecond, WindSpeedUnit unit) => _tile(
        icon: QuietIcon.wind,
        label: t.statWind,
        value:
            metersPerSecond == null ? null : unit.formatValue(metersPerSecond),
        unit: unit.symbol,
        spoken: windSpeedUnitSpoken(t, unit),
      );

  /// UV (整数 + 段階語)。
  QuietMetricTile uv(double? uvIndex) {
    if (uvIndex == null) {
      return _tile(icon: QuietIcon.uv, label: t.statUv, value: null);
    }
    final shown = shownUvIndex(uvIndex);
    final level = uvLevelLabel(t, UvLevel.of(shown));
    return _tile(
      icon: QuietIcon.uv,
      label: t.statUv,
      value: '$shown',
      level: level,
      spoken: level,
    );
  }

  /// 空気質 (整数の US AQI + 段階語)。
  QuietMetricTile air(int? usAqi) {
    if (usAqi == null) {
      return _tile(icon: QuietIcon.air, label: t.metricAir, value: null);
    }
    final level = AqiLevel.of(usAqi);
    return _tile(
      icon: QuietIcon.air,
      label: t.metricAir,
      value: '$usAqi',
      level: aqiLevelLabel(t, level),
      spoken: aqiLevelSpoken(t, level),
    );
  }

  /// 気圧 (整数 + hPa)。グリフは空気の流用 (Figma 3:346 の踏襲。1.3.1 で差し替え)。
  QuietMetricTile pressure(double? hectopascals) => _tile(
        icon: QuietIcon.air,
        label: t.statPressure,
        value: hectopascals == null ? null : '${hectopascals.round()}',
        unit: 'hPa',
        spoken: t.unitHectopascalsA11y,
      );

  /// 気温 (「22°」。単位は設定で決まるので付けない)。グリフは UV と同じ太陽の
  /// 流用 (Figma 3:314 の踏襲。1.3.1 で差し替え)。
  QuietMetricTile temperature(double celsius, TemperatureUnit unit) => _tile(
        icon: QuietIcon.uv,
        label: t.statTemperature,
        value: unit.formatDegrees(celsius),
      );
}
