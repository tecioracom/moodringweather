// lib/presentation/theme/mrw_type.dart
//
// 文字サイズの役割トークン (型スケール)。
//
// 「ホーム・詳細・設定の文字をもう少し大きく」(2026-09-29) を受けて、小さい文字の
// サイズを 3 段階のプリセットで持つ。
//   plus2   … 案2「もう一段」。**既定** (2026-09-29 決裁「案2 でデザインを修正」)
//   current … 旧 v1.3 の実測値 (Figma sthT6fxeWWF33f9vENzFWW)。比較用。
//             各箇所の v1.3 の文字サイズ・寸法をそのまま返す (案2 採用時に入れた
//             レイアウトの修正は全プリセット共通なので、画面は v1.3 と同一ではない)
//   plus1   … 案1「少し」。比較用
// current / plus1 は削除せず、--dart-define=MRW_TYPE_SCALE で選べるまま残す
// (比較画像・回帰の切り分け用)。
// 値は designer の確定表 (2026-09-29、役割トークン 9 種 × 3 プリセット。size /
// 行送り / 字間、px)。差し替えは下の [_kTypeTable] / [_kNavLabel] / [_kPlaceTab] /
// [_kLayout] の行だけでよい。
//
// 変えるのは **サイズ・行送り・字間だけ**。書体の割り当て (Fraunces / Inter /
// IBM Plex Mono / IBM Plex Sans JP)・ウェイト・色 (Quiet Instrument の語彙) は
// 呼び出し側の TextTheme のまま。
//
// 対象外 (display・固定。トークンを通さない): 地名 18・タイル値 17〜18・見出し 28・
// 気温 64・MRI 52・リング内の帯名・記号 (+ ‹ ×)・QuietDisplayNumber・
// Material の既定 (ダイアログ・ピッカー・テーマ既定のボタン文字) とキーボード。
//
// 使い方 (引数はその箇所の **v1.3 の値**。current では引数をそのまま返し、案1 /
// 案2 (既定) では表の値を返す。呼び出し側はプリセットを意識しない):
//   final type = MrwType.of(context);
//   text.bodyMedium?.copyWith(
//     fontSize: type.body.fontSize(13),
//     height: type.body.height(17 / 13),               // 1 行・行タイトル
//     // height: type.caption.height(17 / 12, paragraph: true), // 複数行の段落
//     letterSpacing: type.label.letterSpacing(0.88),   // 字間を持つ mono ラベルだけ
//   )
// 字間 0 (数値・単位・件数など字間なしで組む文字) は案1 / 案2 でも 0 のまま
// (letterSpacing() を通さず 0 を書く)。
//
// プリセットの切り替え (未指定・不明な値は既定の plus2):
//   アプリ    flutter run --dart-define=MRW_TYPE_SCALE=current   (旧 v1.3 と比べる)
//   テスト    flutter test --dart-define=MRW_TYPE_SCALE=plus1
//             または buildAppTheme(..., typeScale: MrwTypeScale.current) /
//             test/golden/golden_harness.dart の goldenApp(typeScale: ...)

import 'package:flutter/material.dart';

/// 型スケールのプリセット。既定は [plus2] ([defaultScale])。
enum MrwTypeScale {
  /// 旧 v1.3 の実測値 (比較用)。各箇所の v1.3 の値をそのまま返す。
  current('現状'),

  /// 案1「少し」(比較用)。
  plus1('案1'),

  /// 案2「もう一段」。既定 (2026-09-29 決裁)。
  plus2('案2');

  const MrwTypeScale(this.displayName);

  /// 既定のプリセット (2026-09-29 決裁で [plus2])。`--dart-define=MRW_TYPE_SCALE`
  /// が未指定・不明な値のときと、テーマに [MrwType] が無いときに使う。
  static const MrwTypeScale defaultScale = MrwTypeScale.plus2;

  /// 比較表・比較画像での呼び名 (current の「現状」は旧 v1.3 の値のこと)。
  final String displayName;

  /// `--dart-define=MRW_TYPE_SCALE=<current|plus1|plus2>` の値。
  static const String environmentValue =
      String.fromEnvironment('MRW_TYPE_SCALE');

  /// ビルド時に指定されたプリセット (未指定・不明な値は [defaultScale] = [plus2])。
  static MrwTypeScale get fromEnvironment => parse(environmentValue);

  /// 名前 (`current` / `plus1` / `plus2`) から。不明な値・空・null は
  /// [defaultScale] ([plus2])。
  static MrwTypeScale parse(String? name) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    return defaultScale;
  }
}

/// 1 プリセットでの 1 トークンの値 (px)。
@immutable
class MrwTypeValue {
  const MrwTypeValue(this.size, this.line, {this.paragraph, this.tracking});

  /// 文字サイズ。
  final double size;

  /// 行送り (1 行の文字・行タイトル・見出し)。
  final double line;

  /// 段落 (複数行の本文) の行送り。null は [line] と同じ。
  final double? paragraph;

  /// 字間。null は字間を持たないトークン (Inter / Plex Sans JP の本文系)。
  final double? tracking;

  @override
  bool operator ==(Object other) =>
      other is MrwTypeValue &&
      other.size == size &&
      other.line == line &&
      other.paragraph == paragraph &&
      other.tracking == tracking;

  @override
  int get hashCode => Object.hash(size, line, paragraph, tracking);

  @override
  String toString() => [
        '${_n(size)}/${_n(line)}',
        if (paragraph != null) '段落 ${_n(paragraph!)}',
        if (tracking != null) '字間 ${_n(tracking!)}',
      ].join(' ');

  static String _n(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}

/// 現状 / 案1 / 案2 の 1 行。
typedef MrwTypeRow = ({
  MrwTypeValue current,
  MrwTypeValue plus1,
  MrwTypeValue plus2,
});

/// 文字の役割 (designer 確定の 9 種)。
enum MrwTypeRole {
  /// 時刻軸・上限 / 下限 (Calibration の時刻 9 を統合)。EN / JA とも IBM Plex Mono
  /// (axisLabelStyle)。天気レールは書体 Inter / Plex Sans JP Medium (読み値) のまま、
  /// サイズだけ axis を借りる (レール 8.5 を統合)。
  axis,

  /// バッジ・保存地点タグ・出典行・行の「MRI nn」・件数・注記・チップ。
  tag,

  /// 傾向語 (STABLE)・詳細の NOW・Plus ラベル・パネル内の小ラベル (CURRENT 等)。
  /// 下部ナビは字間だけ違う ([MrwType.navLabel])。
  status,

  /// MOOD RING INDEX・HOURLY MRI・MRI TREND・FACTORS・タイル見出し・FEELS・
  /// 設定の区画ラベル・セグメント切替 (mono 大文字)。
  label,

  /// 説明カード本文・候補の地域・注意書き・取得中の文言。
  meta,

  /// 導入文・行の副題・リンク・単位・本文カード・取得失敗・鮮度切れ。
  caption,

  /// 行タイトル・地点タブ ([MrwType.placeTab])・ボタン・トースト・現在地行・
  /// アラートバナー・ドットカード見出し。
  body,

  /// Plus カード題・Paywall の特典名 / プラン名。
  bodyLg,

  /// 設定行の題・節題・画面名 (サブ画面ヘッダ)・入力欄・概況・シートの題。
  section,
}

// ── 確定表 (designer 2026-09-29) ───────────────────────────────────────────
// 1 列目 (current) は designer が整理した v1.3 の値。current プリセットの描画には
// 使わない (各箇所の v1.3 の値をそのまま返す)。案1 / 案2 のサイズ比の基準にだけ使う。
const Map<MrwTypeRole, MrwTypeRow> _kTypeTable = {
  MrwTypeRole.axis: (
    current: MrwTypeValue(10, 12, tracking: 0),
    plus1: MrwTypeValue(11, 13, tracking: 0),
    plus2: MrwTypeValue(12, 14, tracking: 0),
  ),
  MrwTypeRole.tag: (
    current: MrwTypeValue(10, 13, tracking: 0.4),
    plus1: MrwTypeValue(11, 14, tracking: 0.4),
    plus2: MrwTypeValue(12, 16, tracking: 0.4),
  ),
  MrwTypeRole.status: (
    current: MrwTypeValue(10, 12, tracking: 0.7),
    plus1: MrwTypeValue(11, 13, tracking: 0.66),
    plus2: MrwTypeValue(12, 14, tracking: 0.6),
  ),
  MrwTypeRole.label: (
    current: MrwTypeValue(11, 14, tracking: 0.88),
    plus1: MrwTypeValue(12, 15, tracking: 0.84),
    plus2: MrwTypeValue(13, 16, tracking: 0.78),
  ),
  MrwTypeRole.meta: (
    current: MrwTypeValue(11, 16),
    plus1: MrwTypeValue(12, 16, paragraph: 17),
    plus2: MrwTypeValue(13, 17, paragraph: 18),
  ),
  MrwTypeRole.caption: (
    current: MrwTypeValue(12, 16, paragraph: 17),
    plus1: MrwTypeValue(13, 17, paragraph: 18),
    plus2: MrwTypeValue(14, 18, paragraph: 20),
  ),
  MrwTypeRole.body: (
    current: MrwTypeValue(13, 17, paragraph: 18),
    plus1: MrwTypeValue(14, 18, paragraph: 20),
    plus2: MrwTypeValue(15, 20),
  ),
  MrwTypeRole.bodyLg: (
    current: MrwTypeValue(14, 18),
    plus1: MrwTypeValue(15, 20),
    plus2: MrwTypeValue(16, 21),
  ),
  MrwTypeRole.section: (
    current: MrwTypeValue(15, 20),
    plus1: MrwTypeValue(16, 21),
    plus2: MrwTypeValue(17, 22),
  ),
};

/// 下部ナビ (status と同じサイズ・行送りで、字間だけ 0.6 / 0.55 / 0.5)。
const MrwTypeRow _kNavLabel = (
  current: MrwTypeValue(10, 12, tracking: 0.6),
  plus1: MrwTypeValue(11, 13, tracking: 0.55),
  plus2: MrwTypeValue(12, 14, tracking: 0.5),
);

/// 地点タブ (body。案2 だけ 14 で止める)。
const MrwTypeRow _kPlaceTab = (
  current: MrwTypeValue(13, 17, paragraph: 18),
  plus1: MrwTypeValue(14, 18, paragraph: 20),
  plus2: MrwTypeValue(14, 18),
);

/// 文字の大きさに合わせて変える寸法 (designer 確定。current は v1.3 の値)。
@immutable
class MrwTypeLayout {
  const MrwTypeLayout({
    required this.valueAxisWidth,
    required this.feelsColumnWidth,
    required this.homeLabelToRingGap,
    required this.homeRingBottomGap,
    required this.placeTabBottomGap,
    required this.detailTileLabelMaxLines,
  });

  /// グラフ右端の上限 / 下限の列幅 (「100」が入る幅)。
  final double valueAxisWidth;

  /// ホーム気温の右列 (FEELS + 概況) の幅 (×1.3 で溢れないように)。
  final double feelsColumnWidth;

  /// ホームの MOOD RING INDEX ラベルとリングの間。
  final double homeLabelToRingGap;

  /// ホームのリングの下 (現在地を表示中)。
  final double homeRingBottomGap;

  /// 地点タブの下線の下。
  final double placeTabBottomGap;

  /// 詳細タイルの見出し (TEMPERATURE 等) の最大行数。全プリセット 1 行
  /// (2 行にすると語中で折れる「TEMPERATUR / A」。収まらないときはタイル側で縮小)。
  final int detailTileLabelMaxLines;
}

const ({
  MrwTypeLayout current,
  MrwTypeLayout plus1,
  MrwTypeLayout plus2
}) _kLayout = (
  current: MrwTypeLayout(
    valueAxisWidth: 18,
    feelsColumnWidth: 130,
    homeLabelToRingGap: 18,
    homeRingBottomGap: 28,
    placeTabBottomGap: 12,
    detailTileLabelMaxLines: 1,
  ),
  plus1: MrwTypeLayout(
    valueAxisWidth: 20,
    feelsColumnWidth: 150,
    homeLabelToRingGap: 18,
    homeRingBottomGap: 28,
    placeTabBottomGap: 12,
    detailTileLabelMaxLines: 1,
  ),
  // 案2 はホームの縦が 4px 足りない → リング下 28→20 / ラベル下 18→16 /
  // タブ下 12→9 で吸収。
  plus2: MrwTypeLayout(
    valueAxisWidth: 22,
    feelsColumnWidth: 150,
    homeLabelToRingGap: 16,
    homeRingBottomGap: 20,
    placeTabBottomGap: 9,
    detailTileLabelMaxLines: 1,
  ),
);

/// 1 つの役割の、あるプリセットでの値。呼び出し側は **その箇所の v1.3 の値** を渡し、
/// current プリセットではそれがそのまま返る (v1.3 と同一の描画)。案1 / 案2 (既定) は
/// 表の値を返す。
@immutable
class MrwTypeSpec {
  const MrwTypeSpec({
    required this.scale,
    required this.value,
    required this.base,
  });

  final MrwTypeScale scale;

  /// このプリセットの値。
  final MrwTypeValue value;

  /// 確定表の現状値 (案1 / 案2 のサイズ比の基準)。
  final MrwTypeValue base;

  bool get _keepsCurrent => scale == MrwTypeScale.current;

  /// TextStyle.fontSize。[current] はその箇所の v1.3 のサイズ。
  double fontSize(double current) => _keepsCurrent ? current : value.size;

  /// TextStyle.height。[current] はその箇所の v1.3 の比 (null = テーマの行高を継承)。
  /// 案1 / 案2 はトークンの行送り ([paragraph] で段落の行送り) の比。
  double? height(double? current, {bool paragraph = false}) =>
      _keepsCurrent ? current : _line(paragraph) / value.size;

  /// 行送り (px)。[current] はその箇所の v1.3 の行送り。
  double lineHeight(double current, {bool paragraph = false}) =>
      _keepsCurrent ? current : _line(paragraph);

  /// TextStyle.letterSpacing。[current] はその箇所の v1.3 の字間。字間を持たない
  /// トークン (本文系) は案1 / 案2 でも [current] のまま。
  double letterSpacing(double current) =>
      _keepsCurrent ? current : (value.tracking ?? current);

  /// 文字幅に連動する寸法 (px)。[current] は v1.3 の値。案1 / 案2 はサイズ比で伸ばす
  /// (例: 地点タブの最大幅 104 = 13px で 8 字 → 14px で 112)。
  double scaled(double current) =>
      _keepsCurrent ? current : current * value.size / base.size;

  double _line(bool paragraph) =>
      paragraph ? (value.paragraph ?? value.line) : value.line;

  @override
  bool operator ==(Object other) =>
      other is MrwTypeSpec &&
      other.scale == scale &&
      other.value == value &&
      other.base == base;

  @override
  int get hashCode => Object.hash(scale, value, base);

  @override
  String toString() => 'MrwTypeSpec(${scale.name}: $value)';
}

MrwTypeValue _pick(MrwTypeRow row, MrwTypeScale scale) => switch (scale) {
      MrwTypeScale.current => row.current,
      MrwTypeScale.plus1 => row.plus1,
      MrwTypeScale.plus2 => row.plus2,
    };

/// 型スケール (ThemeExtension)。`MrwType.of(context)` で役割のトークンを引く。
@immutable
class MrwType extends ThemeExtension<MrwType> {
  const MrwType._(this.scale);

  /// プリセットのトークン。
  factory MrwType.forScale(MrwTypeScale scale) => switch (scale) {
        MrwTypeScale.current => current,
        MrwTypeScale.plus1 => plus1,
        MrwTypeScale.plus2 => plus2,
      };

  static const MrwType current = MrwType._(MrwTypeScale.current);
  static const MrwType plus1 = MrwType._(MrwTypeScale.plus1);
  static const MrwType plus2 = MrwType._(MrwTypeScale.plus2);

  final MrwTypeScale scale;

  /// 現在のテーマの型スケール。テーマに無ければ `--dart-define` の指定 (未指定・
  /// 不明な値は既定の plus2。buildAppTheme を通さないウィジェットテストも案2 になる)。
  static MrwType of(BuildContext context) =>
      Theme.of(context).extension<MrwType>() ??
      MrwType.forScale(MrwTypeScale.fromEnvironment);

  /// 確定表の 1 行 (比較表の出力用)。
  static MrwTypeRow row(MrwTypeRole role) => _kTypeTable[role]!;

  /// 下部ナビ・地点タブの行 (確定表の注記ぶん)。
  static MrwTypeRow get navLabelRow => _kNavLabel;
  static MrwTypeRow get placeTabRow => _kPlaceTab;

  MrwTypeSpec _spec(MrwTypeRow row) => MrwTypeSpec(
        scale: scale,
        value: _pick(row, scale),
        base: row.current,
      );

  /// 役割のトークン。
  MrwTypeSpec spec(MrwTypeRole role) => _spec(_kTypeTable[role]!);

  MrwTypeSpec get axis => spec(MrwTypeRole.axis);
  MrwTypeSpec get tag => spec(MrwTypeRole.tag);
  MrwTypeSpec get status => spec(MrwTypeRole.status);
  MrwTypeSpec get label => spec(MrwTypeRole.label);
  MrwTypeSpec get meta => spec(MrwTypeRole.meta);
  MrwTypeSpec get caption => spec(MrwTypeRole.caption);
  MrwTypeSpec get body => spec(MrwTypeRole.body);
  MrwTypeSpec get bodyLg => spec(MrwTypeRole.bodyLg);
  MrwTypeSpec get section => spec(MrwTypeRole.section);

  /// 下部ナビのラベル (status の字間違い)。
  MrwTypeSpec get navLabel => _spec(_kNavLabel);

  /// 地点タブ (body。案2 は 14 で止める)。
  MrwTypeSpec get placeTab => _spec(_kPlaceTab);

  /// 文字の大きさに合わせて変える寸法。
  MrwTypeLayout get layout => switch (scale) {
        MrwTypeScale.current => _kLayout.current,
        MrwTypeScale.plus1 => _kLayout.plus1,
        MrwTypeScale.plus2 => _kLayout.plus2,
      };

  @override
  MrwType copyWith({MrwTypeScale? scale}) =>
      scale == null ? this : MrwType.forScale(scale);

  /// 段階的に補間しない (テーマ切替のアニメーション中も表の値のまま)。
  @override
  MrwType lerp(ThemeExtension<MrwType>? other, double t) {
    if (other is! MrwType) return this;
    return t < 0.5 ? this : other;
  }

  @override
  bool operator ==(Object other) => other is MrwType && other.scale == scale;

  @override
  int get hashCode => scale.hashCode;
}
