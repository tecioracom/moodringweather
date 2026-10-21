// lib/core/utils/external_url.dart
//
// 外部 URL を OS のブラウザ/ストアで開く薄いヘルパー。
// Paywall の利用規約/プライバシー (App Store 3.1.2 必須リンク) と
// サブスク管理導線で共用する。失敗は例外を投げず false を返す。

import 'package:url_launcher/url_launcher.dart';

/// [rawUrl] を外部アプリ (ブラウザ/ストア) で開く。空・不正・失敗時は false。
Future<bool> openExternalUrl(String rawUrl) async {
  if (rawUrl.isEmpty) return false;
  final uri = Uri.tryParse(rawUrl);
  if (uri == null) return false;
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
