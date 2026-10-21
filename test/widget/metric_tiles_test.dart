// test/widget/metric_tiles_test.dart
//
// ホーム・詳細の指標タイルの中身 (shared/metric_tiles.dart)。
//   - UV・空気質は表示中の整数で段階語を選ぶ (公式の区分。4 言語)
//   - 値が無いときは「—」(textLo) で、後ろの文字なし
//   - 風は風速の単位で換算 (m/s 小数 1 桁、km/h・mph は整数)
//   - 読み上げは 1 枚で 1 つ。記号は読み方に、en の空気質の区分 3 は正式名で読む
//   - en の空気質の区分 5 は正式名「Very unhealthy」。3 桁の値のあとには入らないので
//     値の下の行へ回り、同じ行の隣のタイルも同じ高さになる (compliance §9-2)

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/core/utils/temperature_unit.dart';
import 'package:mood_ring_weather/core/utils/wind_speed_unit.dart';
import 'package:mood_ring_weather/l10n/app_localizations.dart';
import 'package:mood_ring_weather/presentation/shared/metric_tiles.dart';
import 'package:mood_ring_weather/presentation/shared/quiet_metric_tile.dart';
import 'package:mood_ring_weather/presentation/theme/app_theme.dart';
import 'package:mood_ring_weather/presentation/theme/mrw_tokens.dart';

import '../golden/golden_harness.dart';

/// [build] で組んだタイルを、幅 [width] の画面 (左右 20・間隔 12 の 2 列) に置く。
Future<void> _pump(
  WidgetTester tester,
  Widget Function(MetricTiles tiles) build, {
  Locale locale = const Locale('en'),
  double width = 360,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    locale: locale,
    supportedLocales: const [
      Locale('en'),
      Locale('ja'),
      Locale('es'),
      Locale('zh'),
    ],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: buildAppTheme(Brightness.dark, locale: locale),
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: build(MetricTiles(AppLocalizations.of(context))),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
}

Finder _value(String text) => find.byWidgetPredicate(
      (w) => w is Text && w.data == text && w.style?.fontSize == 18,
    );

void main() {
  setUpAll(loadAppFonts);

  group('UV・空気質の段階語 (4 言語)', () {
    for (final (locale, uv, air) in const [
      (
        Locale('en'),
        ['Low', 'Moderate', 'High', 'Very high', 'Extreme'],
        ['Good', 'Moderate', 'Poor', 'Unhealthy', 'Very unhealthy', 'Hazardous']
      ),
      (
        Locale('ja'),
        ['弱い', '中程度', '強い', '非常に強い', '極端に強い'],
        ['良い', '普通', 'やや悪い', '悪い', '非常に悪い', '極めて悪い']
      ),
      (
        Locale('es'),
        ['Bajo', 'Moderado', 'Alto', 'Muy alto', 'Extremo'],
        ['Bueno', 'Moderado', 'Deficiente', 'Malo', 'Muy malo', 'Pésimo']
      ),
      (
        Locale('zh'),
        ['低', '中等', '高', '很高', '极高'],
        ['良好', '中等', '较差', '不健康', '很不健康', '有害']
      ),
    ]) {
      testWidgets('${locale.languageCode}: 区分ごとの語 (表示中の整数で判定)', (tester) async {
        // UV: 2.4 →「2」弱い / 2.5 →「3」中程度 / 6 / 10.4 →「10」/ 11。
        const uvs = [2.4, 2.5, 6.0, 10.4, 11.0];
        const aqis = [50, 51, 101, 151, 201, 301];
        for (var i = 0; i < uvs.length; i++) {
          await _pump(tester, (t) => t.uv(uvs[i]), locale: locale);
          expect(find.text(uv[i]), findsOneWidget,
              reason: '${locale.languageCode} UV ${uvs[i]}');
          expect(_value('${uvs[i].round()}'), findsOneWidget);
        }
        for (var i = 0; i < aqis.length; i++) {
          await _pump(tester, (t) => t.air(aqis[i]), locale: locale);
          expect(find.text(air[i]), findsOneWidget,
              reason: '${locale.languageCode} AQI ${aqis[i]}');
        }
      });
    }

    testWidgets('en の区分 5 は「Harmful」ではなく正式名「Very unhealthy」', (tester) async {
      await _pump(tester, (t) => t.air(250));
      expect(find.text('Very unhealthy'), findsOneWidget);
      expect(find.text('Harmful'), findsNothing);
    });
  });

  group('欠測 (null)', () {
    testWidgets('値は「—」(textLo) で、単位・段階語は出さない', (tester) async {
      await _pump(
        tester,
        (t) => Column(
          children: [
            t.uv(null),
            t.air(null),
            t.wind(null, WindSpeedUnit.milesPerHour),
            t.humidity(null),
            t.pressure(null),
          ],
        ),
      );
      expect(find.text('—'), findsNWidgets(5));
      for (final e in find.text('—').evaluate()) {
        expect((e.widget as Text).style?.color, MrwTokens.dark.textLo);
      }
      for (final s in ['mph', '%', 'hPa', 'Low', 'Good']) {
        expect(find.text(s), findsNothing, reason: s);
      }
    });
  });

  group('風 (風速の単位)', () {
    for (final (unit, shown, symbol) in const [
      (WindSpeedUnit.metersPerSecond, '3.2', 'm/s'),
      (WindSpeedUnit.kilometersPerHour, '12', 'km/h'),
      (WindSpeedUnit.milesPerHour, '7', 'mph'),
    ]) {
      testWidgets('3.2 m/s → $shown $symbol', (tester) async {
        await _pump(tester, (t) => t.wind(3.2, unit));
        expect(_value(shown), findsOneWidget);
        expect(find.text(symbol), findsOneWidget);
      });
    }
  });

  testWidgets('気温は「22°」で単位を付けない (°F は「72°」)', (tester) async {
    await _pump(
      tester,
      (t) => Column(
        children: [
          t.temperature(22, TemperatureUnit.celsius),
          t.temperature(22, TemperatureUnit.fahrenheit),
        ],
      ),
    );
    expect(_value('22°'), findsOneWidget);
    expect(_value('72°'), findsOneWidget);
    expect(find.text('°C'), findsNothing);
    expect(find.text('°F'), findsNothing);
  });

  group('読み上げ (タイル 1 枚で 1 つ。§3.6)', () {
    for (final (locale, expected) in const [
      (
        Locale('en'),
        [
          'Wind 3.2 meters per second',
          'Pressure 1013 hectopascals',
          'UV 3 Moderate',
          'AIR 120 Unhealthy for sensitive groups',
          'Humidity 58 %',
          'Temperature 22°',
        ]
      ),
      (
        Locale('ja'),
        [
          '風 3.2 メートル毎秒',
          '気圧 1013 ヘクトパスカル',
          'UV 3 中程度',
          '空気質 120 やや悪い',
          '湿度 58 %',
          '気温 22°',
        ]
      ),
    ]) {
      testWidgets('${locale.languageCode}: 記号は読み方に、en の「Poor」は正式名で読む',
          (tester) async {
        final semantics = tester.ensureSemantics();
        await _pump(
          tester,
          (t) => Column(
            children: [
              t.wind(3.2, WindSpeedUnit.metersPerSecond),
              t.pressure(1013),
              t.uv(3),
              t.air(120),
              t.humidity(58),
              t.temperature(22, TemperatureUnit.celsius),
            ],
          ),
          locale: locale,
          width: 600,
        );
        for (final label in expected) {
          expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
        }
        semantics.dispose();
      });
    }

    testWidgets('km/h・mph の読み方', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(
        tester,
        (t) => Column(
          children: [
            t.wind(3.2, WindSpeedUnit.kilometersPerHour),
            t.wind(3.2, WindSpeedUnit.milesPerHour),
          ],
        ),
      );
      expect(
          find.bySemanticsLabel('Wind 12 kilometers per hour'), findsOneWidget);
      expect(find.bySemanticsLabel('Wind 7 miles per hour'), findsOneWidget);
      semantics.dispose();
    });
  });

  testWidgets('en「250 Very unhealthy」は値の下の行へ回り、同じ行の UV も同じ高さ (360dp・×1.0)',
      (tester) async {
    await _pump(
      tester,
      (t) => QuietMetricTileRow(left: t.uv(3), right: t.air(250)),
    );
    final value = tester.getRect(_value('250'));
    final level = tester.getRect(find.text('Very unhealthy'));
    expect(level.top, greaterThanOrEqualTo(value.bottom - 0.5));
    expect(level.left, closeTo(value.left, 0.5));
    final tiles = find.byType(QuietMetricTile);
    final uv = tester.getRect(tiles.at(0));
    final air = tester.getRect(tiles.at(1));
    expect(air.height, greaterThan(72));
    expect(uv.height, closeTo(air.height, 0.01));
    // UV の値の行は下揃えのまま (下余白 10)。
    expect(uv.bottom - tester.getRect(_value('3')).bottom, closeTo(10, 0.5));
    expect(tester.takeException(), isNull);
  });
}
