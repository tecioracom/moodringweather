// lib/core/constants/app_links.dart
//
// 公開前に埋めるプレースホルダ定数 (docs/privacy-policy.md「要確認」)。
// URL / 連絡先が確定したらここを書き換えるだけで UI に反映される。
// 空文字の間、UI は「準備中 (Coming soon)」を表示する。

class AppLinks {
  AppLinks._();

  /// プライバシーポリシーの公開 URL (HTTPS 恒久 URL)。Vercel ホスト。
  static const String privacyPolicyUrl = 'https://teciora-privacy.vercel.app';

  /// 利用規約の公開 URL (HTTPS 恒久 URL)。Vercel ホスト、2026-09-27 公開。
  static const String termsOfUseUrl =
      'https://teciora-privacy.vercel.app/terms';

  /// サポート連絡先 (メールアドレス)。
  static const String supportEmail = 'contact@teciora.com';

  /// 表示用バージョン (pubspec.yaml の version と同期して手動更新)。
  static const String appVersion = '1.3.0';
}
