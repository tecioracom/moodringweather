// lib/providers/current_alert_provider.dart
//
// 現在地の緊急アラートを「画面に出すため」だけに読む provider (保存地点の出荷条件 G4)。
//
// 保存地点を表示中でも、現在地が注意 / 危険ならホーム最上段にバナーを出す。
// 判定は通知と同じ EmergencyAdvisor を現在地の天気 (weatherSnapshotProvider) に
// 当てるだけで、**通知の経路 (EmergencyAlertController の発火・de-dup・push) は
// 呼ばない・変えない**。保存地点の天気は一切見ない (現在地だけ)。

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/safety/emergency_advisor.dart';
import 'weather_provider.dart';

/// 現在地の緊急アラート (0〜3 件)。現在地の天気が未取得なら空。
final currentEmergencyAlertsProvider = Provider<List<EmergencyAlert>>((ref) {
  final snapshot = ref.watch(weatherSnapshotProvider).valueOrNull;
  if (snapshot == null) return const [];
  return const EmergencyAdvisor().evaluate(snapshot);
});

/// バナーに出す 1 件 (危険 > 注意、同じ深刻度なら 熱中症 > 暴風 > 大雪)。無ければ null。
final currentTopEmergencyAlertProvider = Provider<EmergencyAlert?>((ref) {
  final alerts = [...ref.watch(currentEmergencyAlertsProvider)];
  if (alerts.isEmpty) return null;
  alerts.sort((a, b) {
    final bySeverity = b.severity.index.compareTo(a.severity.index);
    return bySeverity != 0 ? bySeverity : a.kind.index.compareTo(b.kind.index);
  });
  return alerts.first;
});
