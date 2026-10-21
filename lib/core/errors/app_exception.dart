// lib/core/errors/app_exception.dart
//
// ユーザー向け(日本語)と開発者向け(ログ用)を分離した例外
// (programmer-agent.md §5.1)。

enum ErrorType {
  network,
  permissionDenied,
  location,
  parsing,
  unknown,
}

class AppException implements Exception {
  const AppException(this.userMessage, this.developerMessage, this.type);

  /// ユーザー向けメッセージ。日本語・丁寧・対処方法を示す。
  final String userMessage;

  /// 開発者向けメッセージ (英語可。ログ用)。
  final String developerMessage;

  final ErrorType type;

  @override
  String toString() => 'AppException($type): $developerMessage';
}
