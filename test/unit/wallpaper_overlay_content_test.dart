// ライブ壁紙の重ね描きの中身と、送る / 消す / 待つの判定
// (lib/presentation/wallpaper/wallpaper_overlay_content.dart。
// docs/design-wallpaper-weather-overlay.md、2026-09-30 決裁)。
//   - 2 行目の区分名はホームのリングの下と同じ語 (最適・とても暑い — 水分補給を まで)
//   - 時刻はデータの時刻、端末の 12 / 24 時間制。「時点」の語は付けない
//   - 古い表示の「9/30 10:30 更新」「アプリを開くと更新」
//   - 設定でオフ・既定地点 → 消す。データ待ち → 何もしない

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mood_ring_weather/core/utils/temperature_unit.dart';
import 'package:mood_ring_weather/data/datasources/location_datasource.dart';
import 'package:mood_ring_weather/l10n/app_localizations.dart';
import 'package:mood_ring_weather/presentation/shared/band_label.dart';
import 'package:mood_ring_weather/presentation/shared/quiet_glyphs.dart';
import 'package:mood_ring_weather/presentation/wallpaper/wallpaper_overlay_content.dart';

import '../fixtures/wallpaper_overlay_fixtures.dart';

const _here = GeoPoint(35.68, 139.77);
const _zh = Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans');

WallpaperOverlayRequest? _request({
  bool enabled = true,
  GeoPoint? location = _here,
  bool hasWeather = true,
  int mri = 70,
  Locale locale = const Locale('ja'),
  bool use24HourClock = true,
  double textScale = 1,
  TemperatureUnit unit = TemperatureUnit.celsius,
  int optimalMri = 64,
}) =>
    wallpaperOverlayRequest(
      enabled: enabled,
      location: location,
      snapshot: hasWeather ? overlaySnapshot() : null,
      mri: hasWeather ? overlayMri(mri) : null,
      optimalMri: optimalMri,
      unit: unit,
      l10n: lookupAppLocalizations(locale),
      locale: locale,
      use24HourClock: use24HourClock,
      textScale: textScale,
      pixelRatio: 2.75,
      screenWidth: 392,
    );

WallpaperOverlayContent _content(WallpaperOverlayRequest? request) =>
    (request! as ShowWallpaperOverlay).content;

void main() {
  setUpAll(initializeDateFormatting);

  group('送る / 消す / 待つ', () {
    test('設定でオフなら、データがあっても消す', () {
      expect(
        _request(enabled: false),
        const ClearWallpaperOverlay(WallpaperOverlayClearReason.disabled),
      );
      expect(
        (_request(enabled: false)! as ClearWallpaperOverlay).reason,
        WallpaperOverlayClearReason.disabled,
      );
    });

    test('現在地が分からず既定地点 (東京) のときは消す', () {
      final request = _request(location: LocationDataSource.fallback);
      expect(request, isA<ClearWallpaperOverlay>());
      expect(
        (request! as ClearWallpaperOverlay).reason,
        WallpaperOverlayClearReason.fallbackLocation,
      );
    });

    test('現在地の取得中・天気や MRI が無いときは何もしない (前回の重ね描きを残す)', () {
      expect(_request(location: null), isNull);
      expect(_request(hasWeather: false), isNull);
    });

    test('現在地の天気があれば描いて渡す', () {
      expect(_request(), isA<ShowWallpaperOverlay>());
    });

    test('消す要求どうしは理由によらず同じ (続けて送らない)', () {
      expect(
        const ClearWallpaperOverlay(WallpaperOverlayClearReason.disabled),
        const ClearWallpaperOverlay(
          WallpaperOverlayClearReason.fallbackLocation,
        ),
      );
    });
  });

  group('JA', () {
    test('1 行目はグリフと気温、2 行目は「区分名 · 時刻」(「時点」は付けない)', () {
      final c = _content(_request());
      expect(c.glyph, QuietGlyph.partly);
      expect(c.temperature, '22°');
      expect(c.bandLabel, '快適');
      expect(c.time, '13:15');
      expect(c.bandAndTime, '快適 · 13:15');
      expect(c.bandAndTime, isNot(contains('時点')));
      expect(c.japanese, isTrue);
      expect(c.asOf, kOverlayAsOf);
    });

    test('古い表示は「9/30 13:15 更新」「アプリを開くと更新」', () {
      final c = _content(_request());
      expect(c.staleTitle, '9/30 13:15 更新');
      expect(c.staleHint, 'アプリを開くと更新');
    });

    test('区分名はホームのリングの下と同じ語 (最適も「最適」)', () {
      final t = lookupAppLocalizations(const Locale('ja'));
      for (final value in [95, 80, 79, 68, 64, 60, 59, 40, 39, 20, 19, 0]) {
        final c = _content(_request(mri: value));
        expect(
          c.bandLabel,
          mriBandLabel(t, overlayMri(value), optimalMri: 64),
          reason: 'MRI $value',
        );
      }
      expect(_content(_request(mri: 64)).bandAndTime, '最適 · 13:15');
      expect(_content(_request(mri: 68)).bandLabel, '最適');
      expect(_content(_request(mri: 69)).bandLabel, '快適');
      // 学習して推定最適が動けば、ホームと同じく最適の範囲も動く
      expect(_content(_request(mri: 70, optimalMri: 72)).bandLabel, '最適');
    });

    test('とても暑いは「— 水分補給を」まで、グリフは Heat', () {
      final c = _content(_request(mri: 10));
      expect(c.bandAndTime, 'とても暑い — 水分補給を · 13:15');
      expect(c.glyph, QuietGlyph.heat);
      expect(_content(_request(mri: 20)).glyph, QuietGlyph.partly);
    });

    test('°F の設定では華氏', () {
      expect(
        _content(_request(unit: TemperatureUnit.fahrenheit)).temperature,
        '72°',
      );
    });
  });

  group('EN / ES / ZH', () {
    test('EN は大文字、12 時間制なら「1:15 PM」', () {
      final c = _content(
        _request(locale: const Locale('en'), use24HourClock: false),
      );
      expect(c.bandAndTime, 'COMFORTABLE · 1:15\u202FPM');
      expect(c.bandLabel, 'COMFORTABLE');
      expect(c.time, '1:15\u202FPM');
      expect(c.staleTitle, 'Updated Sep\u00A030, 1:15\u202FPM');
      expect(c.staleHint, 'Open the app to refresh');
      expect(c.japanese, isFalse);
    });

    test('EN の 24 時間表示・最適・とても暑い', () {
      const en = Locale('en');
      expect(_content(_request(locale: en)).bandAndTime, 'COMFORTABLE · 13:15');
      expect(
        _content(_request(locale: en, mri: 64)).bandAndTime,
        'OPTIMAL · 13:15',
      );
      expect(
        _content(_request(locale: en, mri: 5)).bandAndTime,
        'VERY HOT — HYDRATE · 13:15',
      );
    });

    test('ES は月の略称、ZH は数字の月/日', () {
      final es = _content(_request(locale: const Locale('es')));
      expect(es.bandAndTime, 'AGRADABLE · 13:15');
      expect(es.staleTitle, 'Actualizado 30\u00A0sept, 13:15');
      final zh = _content(_request(locale: _zh));
      expect(zh.bandAndTime, '舒适 · 13:15');
      expect(zh.staleTitle, '9/30 13:15 更新');
      expect(zh.japanese, isFalse);
    });

    test('古い表示の日付と時刻の中では改行しない (改行は文言の語の間か日付と時刻の間)', () {
      final c = _content(
        _request(locale: const Locale('en'), use24HourClock: false),
      );
      final date = c.staleTitle.substring(
        'Updated '.length,
        c.staleTitle.indexOf(','),
      );
      expect(date, isNot(contains(' ')));
      expect(c.staleTitle.substring(c.staleTitle.indexOf(',') + 2),
          isNot(contains(' ')));
    });
  });

  group('倍率・解像度・幅', () {
    test('文字の倍率は 1.3 倍まで (下は 0.85 まで)', () {
      expect(_content(_request(textScale: 2)).textScale, 1.3);
      expect(_content(_request(textScale: 1.15)).textScale, 1.15);
      expect(_content(_request(textScale: 0.5)).textScale, 0.85);
    });

    test('解像度はそのまま、幅の上限は画面の幅の半分', () {
      final c = _content(_request());
      expect(c.pixelRatio, 2.75);
      expect(c.maxWidth, 196);
    });
  });

  group('送り直しの判定 (等しさ)', () {
    test('同じ入力なら等しい', () {
      expect(_request(), _request());
      expect(_request().hashCode, _request().hashCode);
    });

    test('単位・言語・12/24 時間制・倍率・区分名 (最適) が変われば等しくない', () {
      final base = _request();
      expect(_request(unit: TemperatureUnit.fahrenheit), isNot(base));
      expect(_request(locale: const Locale('en')), isNot(base));
      expect(
        _request(locale: const Locale('en'), use24HourClock: false),
        isNot(_request(locale: const Locale('en'))),
      );
      expect(_request(textScale: 1.3), isNot(base));
      expect(_request(optimalMri: 70), isNot(base)); // 快適 → 最適
    });

    test('データの時刻が変われば等しくない (古さの基準が変わる)', () {
      final l10n = lookupAppLocalizations(const Locale('ja'));
      WallpaperOverlayContent at(DateTime time) => wallpaperOverlayContent(
            snapshot: overlaySnapshot(timestamp: time),
            mri: overlayMri(70),
            optimalMri: 64,
            unit: TemperatureUnit.celsius,
            l10n: l10n,
            locale: const Locale('ja'),
            use24HourClock: true,
            textScale: 1,
            pixelRatio: 3,
            screenWidth: 360,
          );
      expect(at(kOverlayAsOf), at(kOverlayAsOf));
      expect(
        at(kOverlayAsOf.add(const Duration(minutes: 15))),
        isNot(at(kOverlayAsOf)),
      );
    });
  });
}
