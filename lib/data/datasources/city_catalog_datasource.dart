// lib/data/datasources/city_catalog_datasource.dart
//
// Comfort-Twin 候補都市カタログ (assets/cities.json) の読み込み。
// AssetBundle を注入可能にし、テストではメモリ上の JSON を差し込める。

import 'dart:convert';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import '../../core/errors/app_exception.dart';
import '../models/city.dart';

class CityCatalogDataSource {
  const CityCatalogDataSource({AssetBundle? bundle}) : _bundle = bundle;

  static const String assetPath = 'assets/cities.json';

  final AssetBundle? _bundle;

  /// 同梱カタログを読み込む。壊れている場合は AppException (日本語)。
  Future<List<City>> load() async {
    final bundle = _bundle ?? rootBundle;
    try {
      final raw = await bundle.loadString(assetPath);
      final decoded = jsonDecode(raw) as List<dynamic>;
      return [
        for (final e in decoded) City.fromJson(e as Map<String, dynamic>),
      ];
    } catch (e) {
      throw AppException(
        '都市データを読み込めませんでした。アプリを再起動してください。',
        'Failed to load $assetPath: $e',
        ErrorType.parsing,
      );
    }
  }
}
