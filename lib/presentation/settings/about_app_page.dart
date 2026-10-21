// lib/presentation/settings/about_app_page.dart
//
// 設定 > About (spec.md §4.4 / Figma v1.3 `Settings — About App` 6:123・
// Light 24:1194・JP 77:1141 実測)。
//
// 構成 (Figma):
//   パネル    リング印 + アプリ名 (Fraunces 24) + 「バージョン x.y.z」mono
//   セクション「関連情報」Inter SemiBold 15
//   行 ×4     オープンソースライセンス / プライバシー / 利用規約 / サポート
//   パネル    データクレジット (Open-Meteo)
//
// **バッジ (codex-fixes_v1.3_unified.md §9.2)**: 「準備中 / Coming soon」バッジは
// **利用規約行にだけ** 置く。実装の実態 (app_links.dart) がバッジの唯一の根拠:
//   privacyPolicyUrl 公開済み → バッジなし / termsOfUseUrl 空 → バッジあり /
//   supportEmail 公開済み → バッジなし。
//
// **状態色 (§4.1)**: この画面に 0 個。
//
// Figma にあって実装しない (理由):
//   - タグライン「Atmosphere, measured.」(6:135): 4 言語の公式訳が無い。
//     勝手訳をアプリ内の恒久コピーにしない (ストア掲載文と食い違う恐れ)。
//
// 文言はすべて AppLocalizations 経由 (ハードコード禁止)。

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/constants/app_links.dart';
import '../../core/utils/external_url.dart';
import '../../l10n/app_localizations.dart';
import '../shared/quiet_controls.dart';
import '../shared/quiet_page.dart';
import '../theme/mrw_tokens.dart';
import 'privacy_page.dart';

/// 行の間隔 (Figma: 311 → 373 = 62 − 52)。
const double _kRowGap = 10;

class AboutAppPage extends StatelessWidget {
  const AboutAppPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final tokens = MrwTokens.of(context);
    final hasTerms = AppLinks.termsOfUseUrl.isNotEmpty;
    final hasSupport = AppLinks.supportEmail.isNotEmpty;

    return QuietPage(
      title: t.settingsTitle,
      headline: t.settingsAboutApp,
      children: [
        // === アプリ名 + バージョン (Figma 6:130) ===
        QuietPanel(
          child: Row(
            children: [
              // Figma 6:131/6:132: 70px のリング印 (無彩色)。
              ExcludeSemantics(
                child: SizedBox(
                  width: 70,
                  height: 70,
                  child: CustomPaint(
                    painter: _AppMarkPainter(
                      track: tokens.textHi.withValues(alpha: 0.14),
                      arc: tokens.textMid,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // アプリ名は 1 行に収まらなければ語間で折り返す
                    // (「Mood-Ring」/「Weather」。24 / 1.1 のまま縮小しない)。
                    QuietDisplayNumber(t.appTitle, size: 24, maxLines: null),
                    const SizedBox(height: 8),
                    QuietLabel(
                      t.aboutVersion(AppLinks.appVersion),
                      small: true,
                      color: tokens.textMono,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 26),

        // === 関連情報 ===
        QuietSectionTitle(t.aboutResourcesSection),
        const SizedBox(height: 10),
        QuietListRow(
          title: t.aboutLicenses,
          chevron: true,
          onTap: () => showLicensePage(
            context: context,
            applicationName: t.appTitle,
            applicationVersion: AppLinks.appVersion,
          ),
        ),
        const SizedBox(height: _kRowGap),
        QuietListRow(
          title: t.settingsPrivacy,
          chevron: true,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const PrivacyPage()),
          ),
        ),
        const SizedBox(height: _kRowGap),
        // 利用規約は URL 未公開のためバッジ付き・操作不可 (§9.2 の唯一のバッジ)。
        QuietListRow(
          title: t.aboutTerms,
          trailing: hasTerms ? null : QuietBadge(t.settingsComingSoon),
          chevron: hasTerms,
          enabled: hasTerms,
          onTap:
              hasTerms ? () => openExternalUrl(AppLinks.termsOfUseUrl) : null,
        ),
        const SizedBox(height: _kRowGap),
        QuietListRow(
          title: t.aboutSupport,
          subtitle: hasSupport ? AppLinks.supportEmail : null,
          chevron: hasSupport,
          enabled: hasSupport,
          onTap: hasSupport
              ? () => openExternalUrl('mailto:${AppLinks.supportEmail}')
              : null,
        ),
        const SizedBox(height: 26),

        // === データクレジット ===
        QuietBodyCard(text: t.aboutDataCredit),
      ],
    );
  }
}

/// アプリ印 (Figma 6:131/6:132): 270° のトラック + 途中で切れた弧。無彩色。
class _AppMarkPainter extends CustomPainter {
  const _AppMarkPainter({required this.track, required this.arc});

  final Color track;
  final Color arc;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.shortestSide * 0.09;
    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: (size.shortestSide - stroke) / 2,
    );
    const start = 3 * math.pi / 4;
    const sweep = 3 * math.pi / 2;
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt
      ..color = track;
    canvas.drawArc(rect, start, sweep, false, base);
    canvas.drawArc(
      rect,
      start,
      sweep * 0.66,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.butt
        ..color = arc,
    );
  }

  @override
  bool shouldRepaint(_AppMarkPainter old) =>
      old.track != track || old.arc != arc;
}
