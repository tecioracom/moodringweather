// test/fixtures/unit_region_fixtures.dart
//
// 単位の初期値 (端末の地域で決まる。settings_provider.dart の unitRegionProvider) を
// テストで固定する。flutter_test の端末のロケールは en_US なので、何もしないと
// 初期値が °F・mph になる。画面のテスト・golden は従来どおり °C・m/s (日本) に
// 固定し、単位の差分が回帰の差分に混ざらないようにする。地域ごとの初期値そのものは
// test/unit/settings_provider_test.dart と regional_unit_defaults_test.dart で見る。

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mood_ring_weather/core/utils/regional_unit_defaults.dart';
import 'package:mood_ring_weather/providers/settings_provider.dart';

/// 日本の端末 (°C・m/s)。
const UnitRegion kTestUnitRegionJp =
    UnitRegion(countryCode: 'JP', languageCode: 'ja');

/// 端末の地域を [region] (既定は日本) に固定する override。
Override unitRegionOverride([UnitRegion region = kTestUnitRegionJp]) =>
    unitRegionProvider.overrideWithValue(region);
