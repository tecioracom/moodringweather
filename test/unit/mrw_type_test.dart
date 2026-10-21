// test/unit/mrw_type_test.dart
//
// 型スケール (lib/presentation/theme/mrw_type.dart) の単体テスト。
//   - 既定は案2 (plus2。2026-09-29 決裁)。current / plus1 は dart-define で選べる
//   - current (旧 v1.3) は各箇所の v1.3 の値をそのまま返す (v1.3 と 1px も変わらない)
//   - 案1 / 案2 は designer 確定表 (2026-09-29) の値を返す
//   - 段落の行送り・下部ナビの字間・地点タブの上限・寸法の表
//   - buildAppTheme が ThemeExtension として登録する

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/presentation/theme/app_theme.dart';
import 'package:mood_ring_weather/presentation/theme/mrw_type.dart';

/// `--dart-define=MRW_TYPE_SCALE` を付けずに実行しているか (既定の検査はこのときだけ)。
const bool _noDefine = MrwTypeScale.environmentValue == '';

void main() {
  group('MrwTypeScale.parse', () {
    test('既定は案2 (plus2)', () {
      expect(MrwTypeScale.defaultScale, MrwTypeScale.plus2);
    });

    test('名前から。不明な値・空・null は既定の plus2', () {
      expect(MrwTypeScale.parse('plus1'), MrwTypeScale.plus1);
      expect(MrwTypeScale.parse('plus2'), MrwTypeScale.plus2);
      expect(MrwTypeScale.parse('current'), MrwTypeScale.current);
      expect(MrwTypeScale.parse(''), MrwTypeScale.plus2);
      expect(MrwTypeScale.parse('PLUS1'), MrwTypeScale.plus2);
      expect(MrwTypeScale.parse('現状'), MrwTypeScale.plus2);
      expect(MrwTypeScale.parse(null), MrwTypeScale.plus2);
    });

    test('dart-define 未指定なら fromEnvironment は plus2', () {
      expect(MrwTypeScale.fromEnvironment, MrwTypeScale.plus2);
    }, skip: _noDefine ? false : '--dart-define=MRW_TYPE_SCALE 指定時は対象外');
  });

  group('current (旧 v1.3): 引数をそのまま返す', () {
    const type = MrwType.current;
    final specs = [
      for (final role in MrwTypeRole.values) type.spec(role),
      type.navLabel,
      type.placeTab,
    ];

    test('fontSize / height / letterSpacing / lineHeight / scaled', () {
      for (final s in specs) {
        for (final v in const [8.5, 9.0, 10.0, 11.0, 12.0, 13.0, 15.0]) {
          expect(s.fontSize(v), v, reason: '$s');
        }
        // 比は計算し直さない (14/11 などを丸めない)。
        for (final r in const [14 / 11, 17 / 13, 1.5, 1.2, 1.45]) {
          expect(s.height(r), r);
          expect(s.height(r, paragraph: true), r);
        }
        expect(s.height(null), isNull);
        expect(s.letterSpacing(0.55), 0.55);
        expect(s.letterSpacing(0), 0);
        expect(s.lineHeight(17), 17);
        expect(s.scaled(104), 104);
      }
    });

    test('寸法は v1.3 のまま', () {
      final l = type.layout;
      expect(l.valueAxisWidth, 18);
      expect(l.feelsColumnWidth, 130);
      expect(l.homeLabelToRingGap, 18);
      expect(l.homeRingBottomGap, 28);
      expect(l.placeTabBottomGap, 12);
      expect(l.detailTileLabelMaxLines, 1);
    });
  });

  group('案1 / 案2: designer 確定表 (size / 行送り / 字間)', () {
    // (トークン, 現状の引数サイズ, 案1 size/行送り/字間, 案2 size/行送り/字間)
    const expected = <MrwTypeRole, List<(double, double, double?)>>{
      MrwTypeRole.axis: [(11, 13, 0), (12, 14, 0)],
      MrwTypeRole.tag: [(11, 14, 0.4), (12, 16, 0.4)],
      MrwTypeRole.status: [(11, 13, 0.66), (12, 14, 0.6)],
      MrwTypeRole.label: [(12, 15, 0.84), (13, 16, 0.78)],
      MrwTypeRole.meta: [(12, 16, null), (13, 17, null)],
      MrwTypeRole.caption: [(13, 17, null), (14, 18, null)],
      MrwTypeRole.body: [(14, 18, null), (15, 20, null)],
      MrwTypeRole.bodyLg: [(15, 20, null), (16, 21, null)],
      MrwTypeRole.section: [(16, 21, null), (17, 22, null)],
    };

    for (final entry in expected.entries) {
      for (final (i, type) in const [MrwType.plus1, MrwType.plus2].indexed) {
        test('${entry.key.name} (${type.scale.name})', () {
          final (size, line, tracking) = entry.value[i];
          final s = type.spec(entry.key);
          // 現状の引数に関係なく表の値 (レール 8.5・時刻 9 も axis の値になる)。
          expect(s.fontSize(8.5), size);
          expect(s.fontSize(13), size);
          expect(s.lineHeight(11), line);
          expect(s.height(17 / 13)! * size, closeTo(line, 1e-9));
          expect(s.height(null)! * size, closeTo(line, 1e-9));
          // 字間を持たないトークンは呼び出し側の字間のまま。
          expect(s.letterSpacing(0.25), tracking ?? 0.25);
        });
      }
    }

    test('段落の行送り (meta / caption / body)', () {
      double para(MrwType t, MrwTypeRole r) =>
          t.spec(r).lineHeight(0, paragraph: true);
      expect(para(MrwType.plus1, MrwTypeRole.meta), 17);
      expect(para(MrwType.plus2, MrwTypeRole.meta), 18);
      expect(para(MrwType.plus1, MrwTypeRole.caption), 18);
      expect(para(MrwType.plus2, MrwTypeRole.caption), 20);
      expect(para(MrwType.plus1, MrwTypeRole.body), 20);
      // 案2 の body は段落の指定なし = 標準の 20。
      expect(para(MrwType.plus2, MrwTypeRole.body), 20);
      // 段落を持たないトークンは標準の行送り。
      expect(para(MrwType.plus2, MrwTypeRole.section), 22);
    });

    test('下部ナビは status と同じ大きさで字間だけ違う', () {
      expect(MrwType.plus1.navLabel.fontSize(10), 11);
      expect(MrwType.plus1.navLabel.lineHeight(12), 13);
      expect(MrwType.plus1.navLabel.letterSpacing(0.6), 0.55);
      expect(MrwType.plus2.navLabel.fontSize(10), 12);
      expect(MrwType.plus2.navLabel.letterSpacing(0.6), 0.5);
    });

    test('地点タブは案2 でも 14 で止める', () {
      expect(MrwType.plus1.placeTab.fontSize(13), 14);
      expect(MrwType.plus2.placeTab.fontSize(13), 14);
      expect(MrwType.plus2.placeTab.lineHeight(17), 18);
      // 最大幅 (8 字) は文字サイズに比例: 104 × 14/13 = 112。
      expect(MrwType.plus2.placeTab.scaled(104), 112);
      expect(MrwType.plus2.body.fontSize(13), 15);
    });

    test('寸法: 値軸の列幅・FEELS 列・案2 の縦の吸収・詳細タイルの見出し', () {
      expect(MrwType.plus1.layout.valueAxisWidth, 20);
      expect(MrwType.plus2.layout.valueAxisWidth, 22);
      expect(MrwType.plus1.layout.feelsColumnWidth, 150);
      // 案2 も 150 (EN は「FEELS nn°」に短縮し、FEELS 行は省略せず折り返す)。
      expect(MrwType.plus2.layout.feelsColumnWidth, 150);
      expect(MrwType.plus1.layout.homeRingBottomGap, 28);
      expect(MrwType.plus2.layout.homeRingBottomGap, 20);
      expect(MrwType.plus2.layout.homeLabelToRingGap, 16);
      expect(MrwType.plus2.layout.placeTabBottomGap, 9);
      // 見出しは全プリセット 1 行 (2 行だと語中で折れる。収まらないときは縮小)。
      expect(MrwType.plus1.layout.detailTileLabelMaxLines, 1);
      expect(MrwType.plus2.layout.detailTileLabelMaxLines, 1);
    });

    test('小さくならない: 現状 ≤ 案1 ≤ 案2、行送り ≥ サイズ', () {
      for (final role in MrwTypeRole.values) {
        final row = MrwType.row(role);
        expect(row.current.size <= row.plus1.size, isTrue, reason: '$role');
        expect(row.plus1.size <= row.plus2.size, isTrue, reason: '$role');
        for (final v in [row.current, row.plus1, row.plus2]) {
          expect(v.line >= v.size, isTrue, reason: '$role $v');
          expect((v.paragraph ?? v.line) >= v.line, isTrue, reason: '$role');
        }
      }
    });
  });

  group('buildAppTheme', () {
    test('typeScale を ThemeExtension として登録する', () {
      for (final scale in MrwTypeScale.values) {
        final theme = buildAppTheme(Brightness.dark, typeScale: scale);
        expect(theme.extension<MrwType>(), MrwType.forScale(scale));
      }
    });

    test('省略時は --dart-define の指定 (未指定なら既定の plus2)', () {
      final theme = buildAppTheme(Brightness.light);
      expect(theme.extension<MrwType>()?.scale, MrwTypeScale.fromEnvironment);
      if (_noDefine) {
        expect(theme.extension<MrwType>(), MrwType.plus2);
      }
    });

    test('TextTheme (Material の既定) はプリセットで変えない', () {
      final a = buildAppTheme(Brightness.dark, typeScale: MrwTypeScale.current);
      final b = buildAppTheme(Brightness.dark, typeScale: MrwTypeScale.plus2);
      expect(b.textTheme, a.textTheme);
    });
  });

  testWidgets('MrwType.of はテーマの拡張を返す', (tester) async {
    late MrwType found;
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(Brightness.dark, typeScale: MrwTypeScale.plus1),
      home: Builder(builder: (context) {
        found = MrwType.of(context);
        return const SizedBox();
      }),
    ));
    expect(found.scale, MrwTypeScale.plus1);
  });

  testWidgets('MrwType.of: テーマに拡張が無ければ dart-define の指定 (未指定なら plus2)',
      (tester) async {
    late MrwType found;
    // buildAppTheme を通さない (MrwType を登録していない) テーマ。
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        found = MrwType.of(context);
        return const SizedBox();
      }),
    ));
    expect(found.scale, MrwTypeScale.fromEnvironment);
    if (_noDefine) expect(found, MrwType.plus2);
  });
}
