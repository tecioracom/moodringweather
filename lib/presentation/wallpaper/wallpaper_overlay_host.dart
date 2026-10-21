// lib/presentation/wallpaper/wallpaper_overlay_host.dart
//
// アプリの根元 (MaterialApp.builder) に置き、ライブ壁紙の重ね描きを最新に保つ。
// 現在地の天気・MRI・設定 (オン / オフ・°C / °F)・言語・12/24 時間制・文字の倍率が
// 変わるたびに要求を作り、描き終わりの後 (post frame) に WallpaperOverlaySync へ渡す。
// 子 ([child]) はそのまま返す (同じインスタンスなので子は作り直されない)。
//
// 壁紙は現在地のまま (保存地点の表示に切り替えても動かさない。色と同じ)。
// Android だけ (liveWallpaperSupportedProvider)。

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/calibration_provider.dart';
import '../../providers/mri_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/wallpaper_provider.dart';
import '../../providers/weather_provider.dart';
import '../shared/chart_axes.dart';
import 'wallpaper_overlay_content.dart';

/// 文字の倍率を測る基準の大きさ (本文。非線形の倍率でも本文の倍率に合わせる)。
const double _textScaleReference = 14;

class WallpaperOverlayHost extends ConsumerWidget {
  const WallpaperOverlayHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(liveWallpaperSupportedProvider)) return child;
    final request = wallpaperOverlayRequest(
      enabled: ref.watch(wallpaperWeatherProvider),
      location: ref.watch(currentLocationProvider).valueOrNull,
      snapshot: ref.watch(weatherSnapshotProvider).valueOrNull,
      mri: ref.watch(mriProvider).valueOrNull,
      optimalMri: ref.watch(personalProfileProvider).estimatedOptimalMri,
      unit: ref.watch(temperatureUnitProvider),
      l10n: AppLocalizations.of(context),
      locale: Localizations.localeOf(context),
      use24HourClock: uses24HourClock(context),
      textScale: MediaQuery.textScalerOf(context).scale(_textScaleReference) /
          _textScaleReference,
      pixelRatio: MediaQuery.devicePixelRatioOf(context),
      screenWidth: MediaQuery.sizeOf(context).shortestSide,
    );
    if (request != null) {
      final sync = ref.read(wallpaperOverlaySyncProvider);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(sync.update(request)),
      );
    }
    return child;
  }
}
