// lib/domain/mri/mri_trend.dart
//
// 短期の MRI 傾向 (Home の Sparkline Card 右上の語: Figma 3:75 "STABLE" /
// 3:194 "RISK RISES"、JA 77:259 "リスク上昇")。MRI は高いほど快適なので、
// 先の値が今より下がる = 不快側へ振れる = リスク上昇。
// しきい値 ±8 は S4 実装時の暫定値 (weather-science の裁定で調整可)。

enum MriTrend { stable, riskRises, easing }

class MriTrendClassifier {
  const MriTrendClassifier._();

  /// [now] と先の値 [future] (数時間ぶん) を比べて傾向を返す。
  /// 先の最小値が now − [threshold] 以下なら riskRises、
  /// 先の最大値が now + [threshold] 以上なら easing、それ以外は stable。
  /// 両方に該当する場合は安全側 (riskRises) を優先する。
  static MriTrend classify({
    required int now,
    required Iterable<int> future,
    int threshold = 8,
  }) {
    if (future.isEmpty) return MriTrend.stable;
    var min = now;
    var max = now;
    for (final v in future) {
      if (v < min) min = v;
      if (v > max) max = v;
    }
    if (min <= now - threshold) return MriTrend.riskRises;
    if (max >= now + threshold) return MriTrend.easing;
    return MriTrend.stable;
  }
}
