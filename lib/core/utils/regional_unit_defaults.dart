// lib/core/utils/regional_unit_defaults.dart
//
// 単位の初期値を端末の地域で決める (設定 › 一般。docs/design-metric-units-proposal.md
// §2.6)。**まだ選んでいない人だけ** に使い、保存済みの設定は変えない
// (settings_provider.dart)。
//
// 表は CLDR の単位の好み (`units.xml`: speed / wind、temperature / weather。
// 2026-09-30 に main で確認) のまま:
//   風速  m/s  … JP CN KR DK FI NO PL RU SE
//         mph  … US GB
//         km/h … それ以外
//   気温  °F   … US PR BS BZ KY PW
//         °C   … それ以外
// 地域 (国コード) が取れないときは、アプリの言語が ja / zh なら m/s、それ以外は
// km/h (気温は °C)。
//
// 純 Dart (Flutter 非依存) — ユニットテスト対象。

import 'temperature_unit.dart';
import 'wind_speed_unit.dart';

/// 風速を m/s で表す地域 (CLDR `wind`)。
const Set<String> kMetersPerSecondRegions = {
  'JP',
  'CN',
  'KR',
  'DK',
  'FI',
  'NO',
  'PL',
  'RU',
  'SE',
};

/// 風速を mph で表す地域 (CLDR `wind`)。
const Set<String> kMilesPerHourRegions = {'US', 'GB'};

/// 気温を °F で表す地域 (CLDR `weather`)。
const Set<String> kFahrenheitRegions = {'US', 'PR', 'BS', 'BZ', 'KY', 'PW'};

/// 地域が取れないとき、風速を m/s にするアプリの言語。
const Set<String> kMetersPerSecondLanguages = {'ja', 'zh'};

/// 単位の初期値を決める材料: 端末の地域 (国コード) と、地域が取れないときに
/// 使うアプリの言語。
class UnitRegion {
  /// [countryCode] は大文字の国コード ('US')、[languageCode] は小文字 ('en')。
  /// 端末の値をそのまま渡すときは [UnitRegion.fromCodes] (大小・空文字を整える)。
  const UnitRegion({this.countryCode, this.languageCode});

  /// 端末のロケールの国コードとアプリの言語から作る。空文字は「無い」扱い。
  factory UnitRegion.fromCodes({String? countryCode, String? languageCode}) {
    String? clean(String? s) => (s == null || s.trim().isEmpty) ? null : s;
    return UnitRegion(
      countryCode: clean(countryCode)?.toUpperCase(),
      languageCode: clean(languageCode)?.toLowerCase(),
    );
  }

  /// 端末の地域 (ISO 3166-1 の国コード、大文字)。取れないときは null。
  final String? countryCode;

  /// アプリの言語 (地域が取れないときだけ使う)。
  final String? languageCode;

  /// 気温の初期値。
  TemperatureUnit get defaultTemperatureUnit =>
      kFahrenheitRegions.contains(countryCode)
          ? TemperatureUnit.fahrenheit
          : TemperatureUnit.celsius;

  /// 風速の初期値。
  WindSpeedUnit get defaultWindSpeedUnit {
    final country = countryCode;
    if (country == null) {
      return kMetersPerSecondLanguages.contains(languageCode)
          ? WindSpeedUnit.metersPerSecond
          : WindSpeedUnit.kilometersPerHour;
    }
    if (kMetersPerSecondRegions.contains(country)) {
      return WindSpeedUnit.metersPerSecond;
    }
    if (kMilesPerHourRegions.contains(country)) {
      return WindSpeedUnit.milesPerHour;
    }
    return WindSpeedUnit.kilometersPerHour;
  }

  @override
  bool operator ==(Object other) =>
      other is UnitRegion &&
      other.countryCode == countryCode &&
      other.languageCode == languageCode;

  @override
  int get hashCode => Object.hash(countryCode, languageCode);

  @override
  String toString() =>
      'UnitRegion(${countryCode ?? '-'}, ${languageCode ?? '-'})';
}
