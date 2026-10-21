// v1.3 セマンティックトークン (lib/presentation/theme/mrw_tokens.dart) のユニット。
//   - 16 変数 × Dark/Light が Figma `MRW Semantic` の実測値と一致する
//   - MRI → 帯色の境界 (指示書 §4.3: 下限を含む)
//   - ランプの昇順 7 ストップ
//   - ThemeData に登録され、MrwTokens.of で取り出せる

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/presentation/theme/app_theme.dart';
import 'package:mood_ring_weather/presentation/theme/mrw_tokens.dart';

void main() {
  group('state/* (Figma MRW Semantic §2.2)', () {
    test('Dark = bright ストップ', () {
      const d = MrwTokens.dark;
      expect(d.stateCold, const Color(0xFF7B84F2));
      expect(d.stateCool, const Color(0xFF58A0EE));
      expect(d.stateFresh, const Color(0xFF38C0CC));
      expect(d.stateComfortable, const Color(0xFF46C795));
      expect(d.stateWarm, const Color(0xFFEBAE4A));
      expect(d.stateHot, const Color(0xFFF0795A));
      expect(d.stateDanger, const Color(0xFFE5533D));
    });
    test('Light = deep ストップ', () {
      const l = MrwTokens.light;
      expect(l.stateCold, const Color(0xFF5B63D6));
      expect(l.stateCool, const Color(0xFF3E7FD4));
      expect(l.stateFresh, const Color(0xFF269DA8));
      expect(l.stateComfortable, const Color(0xFF2FA37A));
      expect(l.stateWarm, const Color(0xFFC9871F));
      expect(l.stateHot, const Color(0xFFE0603C));
      expect(l.stateDanger, const Color(0xFFCE362B));
    });
  });

  group('action/* (§2.3) と commerce/plus (§2.4)', () {
    test('操作色は彩度ゼロ (RGB の最大差が 12/255 以下)', () {
      // HSL 彩度は白・黒に近い色で不安定なため、チャンネル差 (chroma) で判定する。
      for (final t in [MrwTokens.dark, MrwTokens.light]) {
        for (final c in [
          t.actionPrimaryFill,
          t.actionPrimaryLabel,
          t.actionSecondaryFill,
          t.actionSecondaryLabel,
          t.actionTertiaryLabel,
        ]) {
          final v = c.toARGB32();
          final r = (v >> 16) & 0xFF, g = (v >> 8) & 0xFF, b = v & 0xFF;
          final chroma = [r, g, b].reduce((a, x) => a > x ? a : x) -
              [r, g, b].reduce((a, x) => a < x ? a : x);
          expect(chroma, lessThanOrEqualTo(12), reason: '$c');
        }
      }
    });
    test('primary は Dark pearl / Light onyx-900 で反転する', () {
      expect(MrwTokens.dark.actionPrimaryFill, const Color(0xFFF4F2EC));
      expect(MrwTokens.dark.actionPrimaryLabel, const Color(0xFF0D0E11));
      expect(MrwTokens.light.actionPrimaryFill, const Color(0xFF0D0E11));
      expect(MrwTokens.light.actionPrimaryLabel, const Color(0xFFF4F2EC));
    });
    test('destructive は ember 系のみ (Dark #E5533D / Light #CE362B)', () {
      expect(MrwTokens.dark.actionDestructiveLabel, const Color(0xFFE5533D));
      expect(MrwTokens.light.actionDestructiveLabel, const Color(0xFFCE362B));
    });
    test('Plus 紫 #8B7BD8 は両モード共通、tint 12% / badge 32%', () {
      for (final t in [MrwTokens.dark, MrwTokens.light]) {
        expect(t.plusBase, const Color(0xFF8B7BD8));
        expect(t.plusTint.toARGB32() & 0x00FFFFFF, 0x8B7BD8);
        expect(t.plusBadge.toARGB32() & 0x00FFFFFF, 0x8B7BD8);
        expect((t.plusTint.a * 100).round(), 12);
        expect((t.plusBadge.a * 100).round(), 32);
      }
    });
    test('課金色は状態色のアンバー (#EBAE4A) を使わない', () {
      expect(MrwTokens.dark.plusBase, isNot(MrwTokens.dark.stateWarm));
    });
  });

  group('stateColorForMri (§4.3: 境界は下限を含む)', () {
    test('80 は涼しい、79 は快適', () {
      expect(MrwTokens.dark.stateColorForMri(80), MrwTokens.dark.stateCool);
      expect(
          MrwTokens.dark.stateColorForMri(79), MrwTokens.dark.stateComfortable);
    });
    test('60/59, 40/39, 20/19 の境界', () {
      const t = MrwTokens.light;
      expect(t.stateColorForMri(60), t.stateComfortable);
      expect(t.stateColorForMri(59), t.stateWarm);
      expect(t.stateColorForMri(40), t.stateWarm);
      expect(t.stateColorForMri(39), t.stateHot);
      expect(t.stateColorForMri(20), t.stateHot);
      expect(t.stateColorForMri(19), t.stateDanger);
      expect(t.stateColorForMri(0), t.stateDanger);
      expect(t.stateColorForMri(100), t.stateCool);
    });
    test('範囲外はクランプ', () {
      expect(MrwTokens.dark.stateColorForMri(-5), MrwTokens.dark.stateDanger);
      expect(MrwTokens.dark.stateColorForMri(140), MrwTokens.dark.stateCool);
    });
    test('ラベルを持たない cold / fresh は単独要素に返さない', () {
      for (var mri = 0; mri <= 100; mri++) {
        final c = MrwTokens.dark.stateColorForMri(mri);
        expect(c, isNot(MrwTokens.dark.stateCold));
        expect(c, isNot(MrwTokens.dark.stateFresh));
      }
    });
  });

  test('ランプは MRI 昇順 7 ストップ (Foundations 2:72)', () {
    const t = MrwTokens.dark;
    expect(t.rampColors, [
      t.stateDanger,
      t.stateHot,
      t.stateWarm,
      t.stateComfortable,
      t.stateFresh,
      t.stateCool,
      t.stateCold,
    ]);
    expect(MrwTokens.rampStops, [0.0, 0.20, 0.40, 0.60, 0.78, 0.90, 1.0]);
  });

  group('ThemeData への登録', () {
    testWidgets('MrwTokens.of は brightness に応じた値を返す', (tester) async {
      late MrwTokens dark;
      late MrwTokens light;
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(Brightness.light),
        darkTheme: buildAppTheme(Brightness.dark),
        themeMode: ThemeMode.dark,
        home: Builder(builder: (context) {
          dark = MrwTokens.of(context);
          return const SizedBox();
        }),
      ));
      await tester.pumpAndSettle();
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(Brightness.light),
        darkTheme: buildAppTheme(Brightness.dark),
        themeMode: ThemeMode.light,
        home: Builder(builder: (context) {
          light = MrwTokens.of(context);
          return const SizedBox();
        }),
      ));
      // MaterialApp はテーマ切替をアニメーションするため、完了後の値で判定する。
      await tester.pumpAndSettle();
      expect(dark.bg, MrwTokens.dark.bg);
      expect(light.bg, MrwTokens.light.bg);
    });

    test('lerp(0) は自身、lerp(1) は相手', () {
      final a = MrwTokens.dark.lerp(MrwTokens.light, 0);
      final b = MrwTokens.dark.lerp(MrwTokens.light, 1);
      expect(a.bg, MrwTokens.dark.bg);
      expect(b.bg, MrwTokens.light.bg);
    });
  });
}
