// lib/presentation/shell/main_shell.dart
//
// アプリのトップレベルシェル (ホーム / 詳細 / 設定 はタブ)。
//   - ボトムナビは Figma v1.3「Bottom Navigation」(3:116 / 24:116 実測) のピル型:
//     地 350×64・角丸 20・navBackground (92%)・1px 枠 9%、選択項目は 86×40・角丸 14 の
//     navActive ピル (1px 枠 6%)、ラベルは mono 10 / 字間 0.6、アイコンなし。
//     ラベルの文字は型スケールの navLabel (status の字間違い)。ピル幅 86 は据え置き。
//   - IndexedStack でタブ本体を保持し、切替時も各タブの状態を失わない。
//   - タブ本体 (HomePage / DetailPage / SettingsPage) は push 遷移ではなく
//     index 切替で即時に入れ替わる (下部ナビは常に残る)。
//   - 設定タブ配下のサブ画面は従来どおり Navigator.push (戻る矢印あり・下部ナビ無し)。
//   - 未訪問タブは SizedBox.shrink のプレースホルダにして遅延構築する。
// v1.2 までのグラス調 NavigationBar (BackdropFilter) は段階 S3 で廃止。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/shell_provider.dart';
import '../detail/detail_page.dart';
import '../home/home_page.dart';
import '../settings/settings_page.dart';
import '../theme/mrw_tokens.dart';
import '../theme/mrw_type.dart';

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  /// 一度でも表示したタブだけ実体を構築する (以後は IndexedStack が状態を保持)。
  final List<bool> _visited = [true, false, false];

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    // タブ index は Provider (Home のヘッダ右上からも設定タブへ切り替える)。
    final index = ref.watch(mainShellTabProvider);
    _visited[index] = true;

    const tabs = <Widget>[HomePage(), DetailPage(), SettingsPage()];

    return Scaffold(
      // 各タブの地をナビ裏まで通す (ナビは浮いたピル)。
      extendBody: true,
      body: IndexedStack(
        index: index,
        children: [
          for (var i = 0; i < tabs.length; i++)
            _visited[i] ? tabs[i] : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          // Figma: 左右 20 / 下 14 (844 − 755 − 64 − 11 = 14)。
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
          child: QuietNavBar(
            selectedIndex: index,
            labels: [t.tabHome, t.tabDetail, t.tabSettings],
            onSelected: (i) =>
                ref.read(mainShellTabProvider.notifier).state = i,
          ),
        ),
      ),
    );
  }
}

/// v1.3 のピル型ボトムナビ (Figma 3:116)。3 項目固定。
class QuietNavBar extends StatelessWidget {
  const QuietNavBar({
    super.key,
    required this.selectedIndex,
    required this.labels,
    required this.onSelected,
  });

  final int selectedIndex;
  final List<String> labels;
  final ValueChanged<int> onSelected;

  static const double height = 64;

  @override
  Widget build(BuildContext context) {
    final tokens = MrwTokens.of(context);
    final nav = MrwType.of(context).navLabel;
    final labelStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
          fontSize: nav.fontSize(10),
          letterSpacing: nav.letterSpacing(0.6),
          height: nav.height(1.2),
        );

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: tokens.navBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(width: 1, color: tokens.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 11),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Semantics(
                button: true,
                selected: i == selectedIndex,
                label: labels[i],
                child: GestureDetector(
                  key: ValueKey('quiet-nav-$i'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSelected(i),
                  child: Center(
                    child: Container(
                      width: 86,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: i == selectedIndex
                          ? BoxDecoration(
                              color: tokens.navActive,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                width: 1,
                                color: tokens.borderSubtle,
                              ),
                            )
                          : null,
                      child: Text(
                        labels[i],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: labelStyle?.copyWith(
                          color: i == selectedIndex
                              ? tokens.textHi
                              : tokens.textMono,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
