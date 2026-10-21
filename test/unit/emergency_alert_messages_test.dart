// 緊急通知メッセージ解決 (emergency_alert_messages.dart) のユニット。
//   - kind × severity ごとの文言選択
//   - 4 言語すべてで免責文 (emergencyDisclaimer) が本文に併記されること
//     (compliance §12.10.4 / mri-spec.md §5.3)

import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/core/utils/wind_speed_unit.dart';
import 'package:mood_ring_weather/data/models/weather_snapshot.dart';
import 'package:mood_ring_weather/domain/safety/emergency_advisor.dart';
import 'package:mood_ring_weather/l10n/app_localizations.dart';
import 'package:mood_ring_weather/presentation/notifications/emergency_alert_messages.dart';

const _locales = [
  Locale('en'),
  Locale('ja'),
  Locale('es'),
  Locale('zh'),
];

const _heatSevere = EmergencyAlert(
  kind: EmergencyKind.heatStroke,
  severity: EmergencySeverity.severe,
  metricValue: 29.4,
);
const _heatDanger = EmergencyAlert(
  kind: EmergencyKind.heatStroke,
  severity: EmergencySeverity.danger,
  metricValue: 32.6,
);
const _storm = EmergencyAlert(
  kind: EmergencyKind.storm,
  severity: EmergencySeverity.severe,
  metricValue: 22,
);
const _snow = EmergencyAlert(
  kind: EmergencyKind.heavySnow,
  severity: EmergencySeverity.danger,
  metricValue: 6,
);

const _forecastAlerts = [
  EmergencyAlert(
    kind: EmergencyKind.heatStroke,
    severity: EmergencySeverity.severe,
    metricValue: 33.4,
    source: EmergencySource.forecast,
  ),
  EmergencyAlert(
    kind: EmergencyKind.heatStroke,
    severity: EmergencySeverity.danger,
    metricValue: 35.2,
    source: EmergencySource.forecast,
  ),
  EmergencyAlert(
    kind: EmergencyKind.storm,
    severity: EmergencySeverity.severe,
    metricValue: 22,
    source: EmergencySource.forecast,
  ),
  EmergencyAlert(
    kind: EmergencyKind.heavySnow,
    severity: EmergencySeverity.danger,
    metricValue: 6,
    source: EmergencySource.forecast,
  ),
];

/// [alert] に対応する現在値キー / 予報キーの本文 (免責文なし)。
({String current, String forecast}) _expectedBodies(
  AppLocalizations t,
  EmergencyAlert alert,
) {
  final v = alert.metricValue.round().toString();
  final danger = alert.severity == EmergencySeverity.danger;
  return switch (alert.kind) {
    EmergencyKind.heatStroke => (
        current: danger
            ? t.emergencyHeatBodyDanger(v)
            : t.emergencyHeatBodySevere(v),
        forecast: danger
            ? t.emergencyHeatBodyDangerForecast(v)
            : t.emergencyHeatBodySevereForecast(v),
      ),
    // 暴風の {wind} は単位込み (既定の m/s)。
    EmergencyKind.storm => (
        current: t.emergencyStormBody(
          WindSpeedUnit.metersPerSecond.formatRounded(alert.metricValue),
        ),
        forecast: t.emergencyStormBodyForecast(
          WindSpeedUnit.metersPerSecond.formatRounded(alert.metricValue),
        ),
      ),
    EmergencyKind.heavySnow => (
        current: t.emergencySnowBody(v),
        forecast: t.emergencySnowBodyForecast(v),
      ),
  };
}

void main() {
  test('source の既定値は current (既存のローカル通知経路の挙動を変えない)', () {
    expect(_heatSevere.source, EmergencySource.current);
    expect(
      const EmergencyAdvisor()
          .evaluate(WeatherSnapshot(
            timestamp: DateTime(2026, 7, 15, 12),
            latitude: 35.66,
            longitude: 139.75,
            temperature: 38,
            humidity: 70,
            windSpeed: 25,
            snowfallCm: 6,
          ))
          .map((a) => a.source)
          .toSet(),
      {EmergencySource.current},
    );
  });

  test('予報経路と現在値経路で異なる文言が選ばれる (4 言語 × 全 kind)', () {
    for (final locale in _locales) {
      final t = lookupAppLocalizations(locale);
      for (final forecast in _forecastAlerts) {
        final current = EmergencyAlert(
          kind: forecast.kind,
          severity: forecast.severity,
          metricValue: forecast.metricValue,
        );
        final expected = _expectedBodies(t, forecast);
        final fMsg = resolveEmergencyAlertMessage(t, forecast);
        final cMsg = resolveEmergencyAlertMessage(t, current);

        // 予報は *Forecast キー、現在値は既存キー。互いに取り違えない。
        expect(fMsg.body, '${expected.forecast}\n${t.emergencyDisclaimer}',
            reason: '$locale ${forecast.kind} forecast');
        expect(cMsg.body, '${expected.current}\n${t.emergencyDisclaimer}',
            reason: '$locale ${forecast.kind} current');
        expect(fMsg.body, isNot(equals(cMsg.body)));
        expect(expected.forecast, isNot(equals(expected.current)),
            reason: '$locale ${forecast.kind} の予報文言が現在値文言と同一');
        // タイトルは共通 (種別を表す)。値は両方に入る。
        expect(fMsg.title, cMsg.title);
        expect(fMsg.body, contains(forecast.metricValue.round().toString()));
      }
    }
  });

  test('予報文言 (ja) は現在形「です」で値を断定せず「見込み / 予想」で表現する', () {
    final t = lookupAppLocalizations(const Locale('ja'));
    for (final alert in _forecastAlerts) {
      final body =
          resolveEmergencyAlertMessage(t, alert).body.split('\n').first;
      expect(body, isNot(contains('°Cです')), reason: '${alert.kind}');
      expect(body, isNot(contains('の暴風です')));
      expect(body, isNot(contains('の降雪です')));
      expect(body, anyOf(contains('見込み'), contains('予想')));
    }
  });

  test('予報文言 (ja) は公式アラート名 (熱中症警戒アラート等) を本文に含めない (spec §12.10.4)', () {
    // 独自判定と公式アラートの区別を文言で崩さない (mri-spec §5.4)。
    // 公式名への言及は免責文の否定形 (「公式警報ではありません」) に限る。
    final t = lookupAppLocalizations(const Locale('ja'));
    for (final alert in _forecastAlerts) {
      final body =
          resolveEmergencyAlertMessage(t, alert).body.split('\n').first;
      expect(body, isNot(contains('警戒アラート')), reason: '${alert.kind}');
      expect(body, isNot(contains('特別警戒')), reason: '${alert.kind}');
    }
  });

  test('4 言語すべてで免責文が本文に併記される (全 kind × severity)', () {
    for (final locale in _locales) {
      final t = lookupAppLocalizations(locale);
      for (final alert in [
        _heatSevere,
        _heatDanger,
        _storm,
        _snow,
        ..._forecastAlerts
      ]) {
        final msg = resolveEmergencyAlertMessage(t, alert);
        expect(msg.body, contains(t.emergencyDisclaimer),
            reason: '$locale ${alert.kind} ${alert.severity} に免責文がない');
        expect(msg.title, isNotEmpty);
      }
    }
  });

  test('熱中症: severity で本文が切り替わり WBGT 値 (丸め) が入る', () {
    final t = lookupAppLocalizations(const Locale('ja'));
    final severe = resolveEmergencyAlertMessage(t, _heatSevere);
    final danger = resolveEmergencyAlertMessage(t, _heatDanger);
    expect(severe.title, t.emergencyHeatTitle);
    expect(severe.body, contains('29')); // 29.4 → "29"
    expect(danger.body, contains('33')); // 32.6 → "33"
    expect(severe.body, isNot(equals(danger.body)));
  });

  test('暴風: タイトルと風速値', () {
    final t = lookupAppLocalizations(const Locale('en'));
    final msg = resolveEmergencyAlertMessage(t, _storm);
    expect(msg.title, t.emergencyStormTitle);
    expect(msg.body, contains('22'));
  });

  group('暴風の風速は利用者の単位で、単位込み (compliance-review-v1.3.0 §9-4)', () {
    const nbsp = '\u00A0';
    // しきい値 20 / 30 m/s の表示 (判定は m/s のまま)。
    const expected = <(double, WindSpeedUnit, String)>[
      (20.0, WindSpeedUnit.metersPerSecond, '20${nbsp}m/s'),
      (20.0, WindSpeedUnit.kilometersPerHour, '72${nbsp}km/h'),
      (20.0, WindSpeedUnit.milesPerHour, '45${nbsp}mph'),
      (30.0, WindSpeedUnit.metersPerSecond, '30${nbsp}m/s'),
      (30.0, WindSpeedUnit.kilometersPerHour, '108${nbsp}km/h'),
      (30.0, WindSpeedUnit.milesPerHour, '67${nbsp}mph'),
    ];
    for (final locale in _locales) {
      for (final source in EmergencySource.values) {
        for (final (ms, unit, shown) in expected) {
          test(
              '${locale.languageCode} ${source.name} $ms m/s → '
              '${shown.replaceAll(nbsp, ' ')}', () {
            final t = lookupAppLocalizations(locale);
            final alert = EmergencyAlert(
              kind: EmergencyKind.storm,
              severity: ms >= 30
                  ? EmergencySeverity.danger
                  : EmergencySeverity.severe,
              metricValue: ms,
              source: source,
            );
            final msg = resolveEmergencyAlertMessage(t, alert, windUnit: unit);
            final lines = msg.body.split('\n');
            // 本文に単位込みの値が 1 回だけ入り、免責文が続く。
            expect(lines.first, contains(shown));
            expect(shown.allMatches(lines.first), hasLength(1));
            expect(lines.last, t.emergencyDisclaimer);
            expect(msg.body, endsWith('\n${t.emergencyDisclaimer}'));
            // 単位は二重にならない (ARB に単位を書かない)。他の単位も出ない。
            for (final other in WindSpeedUnit.values) {
              final count = RegExp(RegExp.escape(other.symbol))
                  .allMatches(lines.first)
                  .length;
              expect(count, other == unit ? 1 : 0,
                  reason: '${other.symbol} in "${lines.first}"');
            }
            // 数値と単位は改行しない空白でつなぐ (普通の空白で離さない)。
            expect(lines.first, isNot(contains('${shown.split(nbsp).first} ')));
            // 見込み / 現在の文言の選び分けは単位に関係なく同じ。
            final expectedBody = source == EmergencySource.forecast
                ? t.emergencyStormBodyForecast(shown)
                : t.emergencyStormBody(shown);
            expect(lines.first, expectedBody);
          });
        }
      }
    }

    test('熱中症 (WBGT) は単位の設定に関係なく °C のまま (§9-5 R2)', () {
      final t = lookupAppLocalizations(const Locale('en'));
      final msg = resolveEmergencyAlertMessage(
        t,
        _heatDanger,
        windUnit: WindSpeedUnit.milesPerHour,
      );
      expect(msg.body, contains('33°C'));
    });
  });

  test('大雪: タイトルと降雪値', () {
    final t = lookupAppLocalizations(const Locale('zh'));
    final msg = resolveEmergencyAlertMessage(t, _snow);
    expect(msg.title, t.emergencySnowTitle);
    expect(msg.body, contains('6'));
  });

  test('医療断定をしない: 日本語本文に断定的医療表現が含まれない', () {
    final t = lookupAppLocalizations(const Locale('ja'));
    for (final alert in [_heatSevere, _heatDanger]) {
      final msg = resolveEmergencyAlertMessage(t, alert);
      // 「熱中症です」「発症します」のような断定をしない (危険性の注意喚起に留める)。
      expect(msg.body, isNot(contains('発症します')));
      expect(msg.body, isNot(contains('熱中症です')));
    }
  });
}
