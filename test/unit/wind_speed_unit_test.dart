// test/unit/wind_speed_unit_test.dart
//
// 風速単位 (m/s / km/h / mph) の換算と表示の純 Dart ユニットテスト
// (docs/design-metric-units-proposal.md §2.6)。データは常に m/s で持ち、
// 表示直前にのみ換算する方針の正本検証。

import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/core/utils/wind_speed_unit.dart';

void main() {
  group('WindSpeedUnit.fromMetersPerSecond', () {
    test('m/s はそのまま返す', () {
      expect(WindSpeedUnit.metersPerSecond.fromMetersPerSecond(3.2), 3.2);
    });

    test('km/h は ×3.6、mph は ×2.2369362920544', () {
      expect(
        WindSpeedUnit.kilometersPerHour.fromMetersPerSecond(10),
        closeTo(36, 1e-9),
      );
      expect(
        WindSpeedUnit.milesPerHour.fromMetersPerSecond(10),
        closeTo(22.369362920544, 1e-9),
      );
      // 1 mile = 1609.344 m の定義どおり (1 mph = 0.44704 m/s)。
      expect(
        WindSpeedUnit.milesPerHour.fromMetersPerSecond(0.44704),
        closeTo(1, 1e-9),
      );
    });
  });

  group('WindSpeedUnit.formatValue (タイルの値)', () {
    test('m/s は小数 1 桁、km/h・mph は整数 (四捨五入)', () {
      expect(WindSpeedUnit.metersPerSecond.formatValue(3.2), '3.2');
      expect(WindSpeedUnit.metersPerSecond.formatValue(2), '2.0');
      expect(WindSpeedUnit.kilometersPerHour.formatValue(3.2), '12'); // 11.52
      expect(WindSpeedUnit.milesPerHour.formatValue(3.2), '7'); // 7.158
      expect(WindSpeedUnit.kilometersPerHour.formatValue(30), '108');
      expect(WindSpeedUnit.milesPerHour.formatValue(30), '67'); // 67.1
      expect(WindSpeedUnit.milesPerHour.formatValue(0), '0');
    });
  });

  group('WindSpeedUnit.formatRounded (緊急通知の本文)', () {
    const nbsp = '\u00A0';
    test('整数に丸めて、改行しない空白 (U+00A0) のあとに記号を付ける', () {
      expect(WindSpeedUnit.metersPerSecond.formatRounded(20), '20${nbsp}m/s');
      expect(WindSpeedUnit.metersPerSecond.formatRounded(22.4), '22${nbsp}m/s');
      expect(
          WindSpeedUnit.kilometersPerHour.formatRounded(20), '72${nbsp}km/h');
      expect(WindSpeedUnit.milesPerHour.formatRounded(20), '45${nbsp}mph');
      // 閾値 (暴風の danger 30 m/s) の表示。
      expect(
          WindSpeedUnit.kilometersPerHour.formatRounded(30), '108${nbsp}km/h');
      expect(WindSpeedUnit.milesPerHour.formatRounded(30), '67${nbsp}mph');
      expect(kNoBreakSpace, '\u00A0');
    });

    test('換算は丸める前の m/s から 1 回だけ四捨五入する (二重丸め・切り捨てなし)', () {
      // 19.6 m/s: m/s を先に丸める (20) と 72 km/h だが、正しくは 70.56 → 71。
      expect(
          WindSpeedUnit.kilometersPerHour.formatRounded(19.6), '71${nbsp}km/h');
      // 20.0 m/s = 44.74 mph → 45 (切り捨ての 44 にしない)。
      expect(WindSpeedUnit.milesPerHour.formatRounded(20.0), '45${nbsp}mph');
    });
  });

  test('nonBreakingSymbol: 「/」の前後に U+2060 を入れ、ほかは記号のまま (QA-20)', () {
    expect(WindSpeedUnit.metersPerSecond.nonBreakingSymbol, 'm\u2060/\u2060s');
    expect(
        WindSpeedUnit.kilometersPerHour.nonBreakingSymbol, 'km\u2060/\u2060h');
    expect(WindSpeedUnit.milesPerHour.nonBreakingSymbol, 'mph');
    for (final unit in WindSpeedUnit.values) {
      expect(unit.nonBreakingSymbol.replaceAll(kWordJoiner, ''), unit.symbol);
    }
  });

  test('記号は訳さず、大文字にしない', () {
    expect(
      WindSpeedUnit.values.map((u) => u.symbol),
      ['m/s', 'km/h', 'mph'],
    );
  });

  group('WindSpeedUnitX.tryParse', () {
    test('タグからの往復が成立する', () {
      for (final unit in WindSpeedUnit.values) {
        expect(WindSpeedUnitX.tryParse(unit.toTag()), unit);
      }
    });

    test('未知の値・null は null (初期値は呼び出し側が地域で決める)', () {
      expect(WindSpeedUnitX.tryParse(null), isNull);
      expect(WindSpeedUnitX.tryParse('knots'), isNull);
      expect(WindSpeedUnitX.tryParse(''), isNull);
    });
  });
}
