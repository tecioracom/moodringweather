// test/unit/regional_unit_defaults_test.dart
//
// 単位の初期値 (地域で決める) の純 Dart ユニットテスト
// (docs/design-metric-units-proposal.md §2.6、CLDR `units.xml` の表)。

import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/core/utils/regional_unit_defaults.dart';
import 'package:mood_ring_weather/core/utils/temperature_unit.dart';
import 'package:mood_ring_weather/core/utils/wind_speed_unit.dart';

UnitRegion _region(String? country, [String? language]) =>
    UnitRegion.fromCodes(countryCode: country, languageCode: language);

void main() {
  group('風速の初期値 (CLDR wind)', () {
    test('JP CN KR DK FI NO PL RU SE は m/s', () {
      for (final c in ['JP', 'CN', 'KR', 'DK', 'FI', 'NO', 'PL', 'RU', 'SE']) {
        expect(_region(c, 'en').defaultWindSpeedUnit,
            WindSpeedUnit.metersPerSecond,
            reason: c);
      }
    });

    test('US GB は mph', () {
      for (final c in ['US', 'GB']) {
        expect(
            _region(c, 'ja').defaultWindSpeedUnit, WindSpeedUnit.milesPerHour,
            reason: c);
      }
    });

    test('それ以外の地域は km/h (言語に関係なく)', () {
      for (final c in ['ES', 'MX', 'DE', 'FR', 'AU', 'CA', 'TW', 'HK', 'PR']) {
        expect(_region(c, 'ja').defaultWindSpeedUnit,
            WindSpeedUnit.kilometersPerHour,
            reason: c);
      }
      // 国連の地域コード (es_419 など) も国の表に無いので km/h。
      expect(_region('419', 'es').defaultWindSpeedUnit,
          WindSpeedUnit.kilometersPerHour);
    });

    test('地域が取れないときはアプリの言語で: ja / zh は m/s、それ以外は km/h', () {
      expect(_region(null, 'ja').defaultWindSpeedUnit,
          WindSpeedUnit.metersPerSecond);
      expect(_region(null, 'zh').defaultWindSpeedUnit,
          WindSpeedUnit.metersPerSecond);
      expect(_region(null, 'en').defaultWindSpeedUnit,
          WindSpeedUnit.kilometersPerHour);
      expect(_region(null, 'es').defaultWindSpeedUnit,
          WindSpeedUnit.kilometersPerHour);
      expect(const UnitRegion().defaultWindSpeedUnit,
          WindSpeedUnit.kilometersPerHour);
    });
  });

  group('気温の初期値 (CLDR weather)', () {
    test('US PR BS BZ KY PW は °F', () {
      for (final c in ['US', 'PR', 'BS', 'BZ', 'KY', 'PW']) {
        expect(_region(c).defaultTemperatureUnit, TemperatureUnit.fahrenheit,
            reason: c);
      }
    });

    test('それ以外 (GB・JP・地域なし) は °C', () {
      for (final c in ['GB', 'JP', 'ES', 'CA', 'LR', 'MM', 'GU']) {
        expect(_region(c).defaultTemperatureUnit, TemperatureUnit.celsius,
            reason: c);
      }
      expect(
          _region(null, 'en').defaultTemperatureUnit, TemperatureUnit.celsius);
    });
  });

  group('UnitRegion.fromCodes', () {
    test('国コードは大文字・言語は小文字に整え、空文字は「無い」扱い', () {
      expect(_region('us', 'EN'),
          const UnitRegion(countryCode: 'US', languageCode: 'en'));
      expect(_region('', ''), const UnitRegion());
      expect(_region(' ', null), const UnitRegion());
      expect(_region('gb').defaultWindSpeedUnit, WindSpeedUnit.milesPerHour);
    });
  });
}
