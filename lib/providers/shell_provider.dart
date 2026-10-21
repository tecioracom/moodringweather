// lib/providers/shell_provider.dart
//
// MainShell のタブ index。Home のヘッダ右上 (設定アイコン, Figma 3:48) から
// 設定タブへ切り替えるために Provider 化する (0 = ホーム / 1 = 詳細 / 2 = 設定)。

import 'package:flutter_riverpod/flutter_riverpod.dart';

final mainShellTabProvider = StateProvider<int>((ref) => 0);
