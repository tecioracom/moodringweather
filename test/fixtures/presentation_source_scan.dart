// test/fixtures/presentation_source_scan.dart
//
// 画面のコード (lib/presentation の Dart ソース) の静的検査の共通部品。
// 表示から外した機能 (花粉・配信の仕組みが無い通知設定) が、画面に戻ってこないことを
// 確かめる検査 (test/qa/*_hidden_static_test.dart) で使う。

import 'dart:io';

/// lib/presentation の Dart ソース。
List<File> presentationDartFiles() => Directory('lib/presentation')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

/// 行コメント (//、///) とブロックコメント (/* */) を落とした本文。
/// 文字列中の「//」(URL) も落ちるが、検査する識別子を消すことはないので問題ない。
String withoutComments(String source) => source
    .split('\n')
    .map((line) {
      final i = line.indexOf('//');
      return i < 0 ? line : line.substring(0, i);
    })
    .join('\n')
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');

/// [files] (既定は lib/presentation) で [forbidden] のどれかに当たる行
/// (「パス:行 名前: 本文」)。コメントは見ない。
List<String> findForbiddenReferences(
  Map<String, RegExp> forbidden, {
  List<File>? files,
}) {
  final hits = <String>[];
  for (final file in files ?? presentationDartFiles()) {
    final lines = withoutComments(file.readAsStringSync()).split('\n');
    for (var i = 0; i < lines.length; i++) {
      for (final MapEntry(key: name, value: pattern) in forbidden.entries) {
        if (pattern.hasMatch(lines[i])) {
          hits.add('${file.path}:${i + 1} $name: ${lines[i].trim()}');
        }
      }
    }
  }
  return hits;
}
