// test/unit/temperature_unit_test.dart
//
// 温度単位 (°C/°F) 換算の純 Dart ユニットテスト。
// データは常に摂氏で持ち、表示直前にのみ換算する方針の正本検証。

import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/core/utils/temperature_unit.dart';

void main() {
  group('TemperatureUnit.fromCelsius', () {
    test('摂氏はそのまま返す', () {
      expect(TemperatureUnit.celsius.fromCelsius(22), 22);
      expect(TemperatureUnit.celsius.fromCelsius(-5.5), -5.5);
    });

    test('華氏は F = C × 9/5 + 32 で換算する', () {
      expect(TemperatureUnit.fahrenheit.fromCelsius(0), 32);
      expect(TemperatureUnit.fahrenheit.fromCelsius(100), 212);
      expect(TemperatureUnit.fahrenheit.fromCelsius(-40), -40); // 交点
      expect(TemperatureUnit.fahrenheit.fromCelsius(22), closeTo(71.6, 1e-9));
    });
  });

  group('TemperatureUnit.formatDegrees', () {
    test('整数へ四捨五入して「°」を付ける', () {
      expect(TemperatureUnit.celsius.formatDegrees(22.4), '22°');
      expect(TemperatureUnit.fahrenheit.formatDegrees(22), '72°'); // 71.6 → 72
      expect(TemperatureUnit.fahrenheit.formatDegrees(0), '32°');
    });
  });

  group('TemperatureUnit.formatDegreesDelta (差の表示。キャリブレーションの最適温度)', () {
    test('摂氏は小数 1 桁で符号を付け、単位記号は付けない', () {
      expect(TemperatureUnit.celsius.formatDegreesDelta(1.5), '+1.5°');
      expect(TemperatureUnit.celsius.formatDegreesDelta(-0.6), '-0.6°');
      expect(TemperatureUnit.celsius.formatDegreesDelta(3), '+3.0°');
      expect(TemperatureUnit.celsius.formatDegreesDelta(0), '+0.0°');
    });

    test('華氏は差なので ×1.8 だけ (32 は足さない)', () {
      expect(TemperatureUnit.fahrenheit.formatDegreesDelta(1.5), '+2.7°');
      expect(TemperatureUnit.fahrenheit.formatDegreesDelta(-0.6), '-1.1°');
      expect(TemperatureUnit.fahrenheit.formatDegreesDelta(3), '+5.4°');
      expect(TemperatureUnit.fahrenheit.formatDegreesDelta(-3), '-5.4°');
      expect(TemperatureUnit.fahrenheit.formatDegreesDelta(0), '+0.0°');
    });

    test('丸めて 0 になる負の値は「-0.0°」にしない', () {
      expect(TemperatureUnit.celsius.formatDegreesDelta(-0.04), '+0.0°');
      expect(TemperatureUnit.fahrenheit.formatDegreesDelta(-0.02), '+0.0°');
    });
  });

  group('TemperatureUnitX.parse', () {
    test('タグからの往復が成立する', () {
      for (final unit in TemperatureUnit.values) {
        expect(TemperatureUnitX.parse(unit.toTag()), unit);
        expect(TemperatureUnitX.tryParse(unit.toTag()), unit);
      }
    });

    test('未知の値・null は摂氏にフォールバックする', () {
      expect(TemperatureUnitX.parse(null), TemperatureUnit.celsius);
      expect(TemperatureUnitX.parse('kelvin'), TemperatureUnit.celsius);
    });

    test('tryParse は未知の値・null で null (初期値は地域で決める)', () {
      expect(TemperatureUnitX.tryParse(null), isNull);
      expect(TemperatureUnitX.tryParse('kelvin'), isNull);
    });
  });
}
