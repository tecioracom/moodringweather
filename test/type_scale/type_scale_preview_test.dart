// test/type_scale/type_scale_preview_test.dart
//
// 型スケール (現状 / 案1 / 案2) の比較画像を書き出す。golden と同じ手順
// (buildAppTheme + 同梱フォント + 固定時刻・固定天気、390×844 / DPR 1) で描画し、
// 縮小せず等倍で保存する。golden の基準画像には触らない。
//
// 実行 (出力先を渡したときだけ動く。通常の flutter test ではスキップ):
//   flutter test test/type_scale/type_scale_preview_test.dart \
//     --dart-define=MRW_TYPE_PREVIEW_OUT=/abs/path/to/dir
//
// 出力:
//   {画面}_{現状|案1|案2}_{系統}.png   各 390×844
//   比較_{画面}_{系統}.png             現状 | 案1 | 案2 を横に並べたもの
//                                      (上に 24px のラベル帯、間と周囲に 12px)
// 系統: Dark_JA / Light_EN (+ qa 用に Dark_ES_x1.3: 文字倍率 1.3)

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/presentation/theme/app_theme.dart';
import 'package:mood_ring_weather/presentation/theme/mrw_type.dart';

import '../golden/golden_harness.dart';
import 'type_scale_scenarios.dart';

const String _outDir = String.fromEnvironment('MRW_TYPE_PREVIEW_OUT');

/// 比較画像の系統。
class _System {
  const _System(this.name, this.brightness, this.locale, {this.textScale = 1});
  final String name;
  final Brightness brightness;
  final Locale locale;
  final double textScale;
}

const _mainSystems = [
  _System('Dark_JA', Brightness.dark, Locale('ja')),
  _System('Light_EN', Brightness.light, Locale('en')),
];

/// ユーザー判断用 (designer 指定の 6 画面) + 波及確認用 (Paywall 等 4 画面)。
const _mainScreens = [
  'ホーム現在地',
  'ホーム保存地点',
  '詳細',
  '設定トップ',
  '設定地点',
  '設定通知',
  'Paywall',
  'CalibrationHome',
  'TwinSearch',
  '地点追加シート',
];

/// qa 用 (任意): ES × 文字倍率 1.3。
const _qaSystem =
    _System('Dark_ES_x1.3', Brightness.dark, Locale('es'), textScale: 1.3);
const _qaScreens = ['ホーム現在地', '詳細', '一般設定', '地点追加シート'];

const double _band = 24;
const double _gap = 12;

void main() {
  setUpAll(loadAppFonts);

  final skip = _outDir.isEmpty
      ? '--dart-define=MRW_TYPE_PREVIEW_OUT=<dir> を付けたときだけ書き出す'
      : null;

  void cases(List<String> screens, _System system) {
    for (final screen in screens) {
      testWidgets('比較 $screen (${system.name})', skip: skip != null,
          (tester) async {
        final shots = <MrwTypeScale, ui.Image>{};
        for (final scale in MrwTypeScale.values) {
          await kTypeScaleScenarios[screen]!(
            tester,
            TypeScaleCase(
              brightness: system.brightness,
              locale: system.locale,
              typeScale: scale,
              textScale: system.textScale,
            ),
          );
          final image = await tester.runAsync(
            () => captureImage(find.byType(MaterialApp).evaluate().single),
          );
          shots[scale] = image!;
          await _writePng(
            image,
            '${screen}_${scale.displayName}_${system.name}.png',
            tester,
          );
          // 次のプリセットの前に画面を捨てる (状態を持ち越さない)。
          await tester.pumpWidget(const SizedBox.shrink());
        }
        await _writeComparison(tester, screen, system, shots);
      });
    }
  }

  cases(_mainScreens, _mainSystems[0]);
  cases(_mainScreens, _mainSystems[1]);
  cases(_qaScreens, _qaSystem);
}

Future<void> _writePng(
  ui.Image image,
  String name,
  WidgetTester tester,
) async {
  final bytes = await tester.runAsync(() async {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  });
  final dir = Directory(_outDir)..createSync(recursive: true);
  File('${dir.path}/$name').writeAsBytesSync(bytes!);
}

Future<void> _writeComparison(
  WidgetTester tester,
  String screen,
  _System system,
  Map<MrwTypeScale, ui.Image> shots,
) async {
  final w = kGoldenSize.width;
  final h = kGoldenSize.height;
  final width = (w * 3 + _gap * 4).toInt();
  final height = (_band + h + _gap).toInt();
  final dark = system.brightness == Brightness.dark;

  final composed = await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = dark ? const Color(0xFF3A3E46) : const Color(0xFFC9D0D8),
    );
    for (final (i, scale) in MrwTypeScale.values.indexed) {
      final left = _gap + i * (w + _gap);
      final paragraph = (ui.ParagraphBuilder(ui.ParagraphStyle(
        textAlign: TextAlign.center,
        fontFamily: MrwFonts.plexSansJp,
        fontSize: 13,
        maxLines: 1,
      ))
            ..pushStyle(ui.TextStyle(
              color: dark ? const Color(0xFFF4F2EC) : const Color(0xFF151922),
              fontWeight: FontWeight.w700,
            ))
            ..addText('${scale.displayName} (${scale.name}) · ${system.name}'))
          .build()
        ..layout(ui.ParagraphConstraints(width: w));
      canvas.drawParagraph(
        paragraph,
        Offset(left, (_band - paragraph.height) / 2),
      );
      canvas.drawImage(shots[scale]!, Offset(left, _band), Paint());
    }
    final picture = recorder.endRecording();
    return picture.toImage(width, height);
  });
  await _writePng(composed!, '比較_${screen}_${system.name}.png', tester);
}
