// lib/data/datasources/city_name_datasource.dart
//
// 座標 → 都市名の逆ジオコーディング (OS のジオコーダを使用。API キー不要)。
// 表示専用の補助データ。失敗時は null を返し、UI 側で「現在地」へフォールバック。
// 座標・地名は保存・送信しない (spec §13)。

import 'package:geocoding/geocoding.dart';

class CityNameDataSource {
  const CityNameDataSource();

  Future<String?> resolve(double latitude, double longitude) async {
    try {
      final placemarks = await placemarkFromCoordinates(latitude, longitude);
      if (placemarks.isEmpty) return null;
      final p = placemarks.first;
      final city = _firstNonEmpty([
        p.locality,
        p.subAdministrativeArea,
        p.administrativeArea,
      ]);
      return city;
    } catch (_) {
      return null; // 表示専用なので静かに諦める。
    }
  }

  String? _firstNonEmpty(List<String?> candidates) {
    for (final c in candidates) {
      if (c != null && c.trim().isNotEmpty) return c.trim();
    }
    return null;
  }
}
