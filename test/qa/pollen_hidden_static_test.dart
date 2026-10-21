// test/qa/pollen_hidden_static_test.dart
//
// 花粉の表示・操作がアプリに戻らないことの静的検査 (compliance-review-v1.3.0 §8-4-5、
// ゲート B6)。花粉データは未接続で、MRI も花粉の多寡では動かない (欠測時の定数
// だけ) ため、1.3.0 から花粉のタイル・「MRI とは」のチップ・「花粉激増」の通知設定・
// キャリブレーションのスライダー・気づきを出さない。
//
// lib/presentation の Dart ソース (コメントを除く) が、花粉の文言キーと花粉の
// 設定値・感受性を参照していないことを確かめる。モデル・保存データ・MRI の計算
// (lib/data・lib/domain) は対象外 (表示と操作だけを外した)。
// 花粉データを接続して表示を戻すときは、compliance の再審査のうえでこの検査を外す。

import 'package:flutter_test/flutter_test.dart';

import '../fixtures/presentation_source_scan.dart';

/// 表示に使ってはいけない識別子 (ARB のキー・花粉の値・感受性・通知設定)。
final Map<String, RegExp> _forbidden = {
  'statPollen': RegExp(r'\bstatPollen\b'),
  'notifPollen': RegExp(r'\bnotifPollen\b'),
  'calibrationInsightPollenSensitive':
      RegExp(r'\bcalibrationInsightPollenSensitive\b'),
  'pollenNone〜pollenVeryHigh':
      RegExp(r'\bpollen(None|Low|Medium|High|VeryHigh)\b'),
  'PollenLevel (花粉の値の表示)': RegExp(r'\bPollenLevel\b'),
  'betaPollen (花粉の感受性のスライダー)': RegExp(r'\bbetaPollen\b'),
  'personalToggles.pollen (花粉激増の通知設定)':
      RegExp(r'personalToggles\s*\.\s*(pollen\b|copyWith\(\s*pollen\s*:)'),
};

void main() {
  test('lib/presentation に Dart ソースがある (検査の前提)', () {
    expect(presentationDartFiles(), isNotEmpty);
  });

  test('花粉の文言キー・値・感受性・通知設定を表示に使っていない (B6)', () {
    final hits = findForbiddenReferences(_forbidden);
    expect(hits, isEmpty, reason: hits.join('\n'));
  });

  test('検査の仕組みが花粉の参照を拾える (検出器の自己確認)', () {
    const sample = '''
      label: t.statPollen, // ここは本文
      // t.notifPollen はコメントなので拾わない
      value: prefs.personalToggles.pollen,
      p.personalToggles.copyWith(pollen: v),
      _pollenLabel(t, snapshot.pollen) => t.pollenVeryHigh,
''';
    final body = withoutComments(sample);
    expect(_forbidden['statPollen']!.hasMatch(body), isTrue);
    expect(_forbidden['notifPollen']!.hasMatch(body), isFalse);
    expect(
      _forbidden['personalToggles.pollen (花粉激増の通知設定)']!.allMatches(body).length,
      2,
    );
    expect(_forbidden['pollenNone〜pollenVeryHigh']!.hasMatch(body), isTrue);
  });
}
