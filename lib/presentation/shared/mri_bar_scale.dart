// lib/presentation/shared/mri_bar_scale.dart
//
// capsule bar 列の縦スケール (Home 3:73 / Detail 3:287 共通)。
//
// 固定レンジ 0–100 だと MRI 1 点あたりの高さが Home で 0.24px しかなく、
// 傾向語のしきい値 ±8 点 (mri_trend.dart) でも差は 1.9px = 事実上平坦。
// 「リスク上昇」と出ているのにバーが動かない自己矛盾になる
// (docs/home-sparkline-decisions.md F1 / F2)。そこで表示範囲を実データへ寄せる。
//
// 自動スケールは軸ラベル (MriValueAxis の hi / lo) と必ず同時に出すこと (決定 ①)。
// 軸が無いと拡大率が読めず、3 点の揺れを大きな変化と誤読させる。
//
// 純 Dart (Flutter 非依存)。ユニットテスト: test/unit/mri_bar_scale_test.dart

/// 参照バンド (決定 ④「代替A」) の値域 = MriBand.comfortable (60–79)。
/// 上端は cool の下端 80 に取る。バーの上端がこの帯の中なら快適、上へ抜ければ
/// 涼しすぎ、下なら暑い側 — 状態色を使わずに快適さが読める。
///
/// 帯はニュートラル (inkMid 8%) なので指示書 §4.1 (状態色は弧・帯ドット・
/// MRI 数値のみ) に触れない。5 色バンドは項目9の裁定を破るため不採用。
/// mri_band.dart の境界とずれないことを test/unit/mri_bar_scale_test.dart で担保。
const double kComfortBandMin = 60;
const double kComfortBandMax = 80;

class MriBarScale {
  const MriBarScale({required this.lo, required this.hi});

  /// 有効な値が 1 つも無いときの既定 (Figma 3:287 の例示値 30 / 80)。
  static const MriBarScale fallback = MriBarScale(lo: 30, hi: 80);

  /// 下端と上端が保つ最小の幅。これより狭いと僅差が劇的に見える。
  static const double minSpan = 20;

  final double lo;
  final double hi;

  /// 表示する標本 (null = データなし) から下端・上端を決める。
  /// 下端は 10 刻みで切り捨て、上端は 10 刻みで切り上げ、幅が [minSpan] 未満なら
  /// 上下へ 10 ずつ広げる。0–100 の外へは出さない。
  factory MriBarScale.forSamples(Iterable<double?> samples) {
    double? min;
    double? max;
    for (final v in samples) {
      if (v == null) continue;
      if (min == null || v < min) min = v;
      if (max == null || v > max) max = v;
    }
    if (min == null || max == null) return fallback;
    var lo = (min / 10).floor() * 10.0;
    var hi = (max / 10).ceil() * 10.0;
    while (hi - lo < minSpan && (lo > 0 || hi < 100)) {
      lo = (lo - 10).clamp(0, 100).toDouble();
      hi = (hi + 10).clamp(0, 100).toDouble();
    }
    return MriBarScale(lo: lo, hi: hi);
  }

  double get span => hi - lo;
}
