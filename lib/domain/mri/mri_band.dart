// lib/domain/mri/mri_band.dart
//
// MRI バンド (docs/mri-spec.md §4 / spec.md §3.3)。
// MRI は「温冷軸つき快適度」: 100 側 = 冷涼(青) / 64 付近 = 快適(緑) /
// 0 側 = 暑熱・不快(赤)。境界は閉区間下端。
//
// 純 Dart (Flutter 非依存)。

enum MriBand {
  /// 80–100: 涼しい・冷感 (青系 200°–240°)
  cool,

  /// 60–79: 快適 (緑系 90°–150°)
  comfortable,

  /// 40–59: やや暑 / 温暖 (黄〜橙 40°–90°)
  warm,

  /// 20–39: 暑い・不快 (橙〜赤 0°–40°)
  hot,

  /// 0–19: ⚠ VERY HOT — HYDRATE (赤 + 警告)
  hotAlert;

  /// 閉区間下端での判定 (mri-spec.md §4):
  /// v ≥ 80 → cool / v ≥ 60 → comfortable / v ≥ 40 → warm /
  /// v ≥ 20 → hot / それ以外 → hotAlert
  static MriBand fromValue(int value) {
    if (value >= 80) return MriBand.cool;
    if (value >= 60) return MriBand.comfortable;
    if (value >= 40) return MriBand.warm;
    if (value >= 20) return MriBand.hot;
    return MriBand.hotAlert;
  }
}
