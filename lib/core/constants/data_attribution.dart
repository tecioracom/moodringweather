// lib/core/constants/data_attribution.dart
//
// 地名検索の出典表示に使う定数 (docs/open-meteo-commercial-terms.md §3)。
//
//   - 検索: Open-Meteo Geocoding API (CC BY 4.0。有料プランでも帰属は必須)
//   - 地名データ: GeoNames (CC BY 4.0)。Open-Meteo の案内文は
//     "Location data based on GeoNames"
//
// 画面の文言は ARB (AppLocalizations) で組み立て、ここの固有名と URL を差し込む。
// Figma 修正版 (docs/codex-figma_add-place-modal_revision.md §2) の出典行:
//   JA「検索: Open-Meteo・地名: GeoNames」
// 固有名 (Open-Meteo / GeoNames) は翻訳しない。

class PlaceSearchAttribution {
  PlaceSearchAttribution._();

  /// 検索サービスの名称。
  static const String searchProviderName = 'Open-Meteo';

  /// 検索サービスのリンク先 (帰属表示の要件: データの近くにリンクを置く)。
  static const String searchProviderUrl = 'https://open-meteo.com/';

  /// 地名検索 API の説明ページ。
  static const String geocodingApiUrl =
      'https://open-meteo.com/en/docs/geocoding-api';

  /// 地名データの提供元の名称。
  static const String placeDataName = 'GeoNames';

  /// 地名データの提供元のリンク先。
  static const String placeDataUrl = 'https://www.geonames.org/';

  /// Open-Meteo と GeoNames のデータライセンス。
  static const String licenseName = 'CC BY 4.0';

  /// ライセンス本文へのリンク。
  static const String licenseUrl =
      'https://creativecommons.org/licenses/by/4.0/';

  /// Open-Meteo が示す GeoNames の帰属文 (英語原文。翻訳版は ARB 側で持つ)。
  static const String placeDataCreditEn = 'Location data based on GeoNames';
}
