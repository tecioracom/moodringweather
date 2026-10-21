// lib/providers/calibration_provider.dart
//
// パーソナルキャリブレーション (感受性ベクトル θ) の状態管理。
// settings_provider と同じ流儀: StateNotifier + SharedPreferences の
// JSON 1 キーでオンデバイス永続化する。
//
// プライバシー (mri-spec.md §0 / spec.md §9.4): 学習データはオンデバイス
// 完結。サーバー・Firestore へは一切送信しない。リセット可能。

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/personal_profile.dart';
import '../data/models/weather_snapshot.dart';
import '../domain/calibration/calibration_engine.dart';
import '../domain/calibration/calibration_feedback.dart';
import '../presentation/locale/locale_controller.dart'
    show sharedPreferencesProvider;

/// 永続化キー (settings_provider の単純キー方針に合わせる)。
const String kPrefKeyPersonalProfile = 'calibration_personal_profile';

class PersonalProfileController extends StateNotifier<PersonalProfile> {
  PersonalProfileController(this._prefs) : super(_load(_prefs));

  final SharedPreferences _prefs;

  /// フィードバック 1 件を学習する (mri-spec.md §6.2)。
  /// 同日重複ガード (§6.3-5) に弾かれた場合は false を返し、状態は不変。
  Future<bool> submitFeedback({
    required CalibrationFeedback feedback,
    required WeatherSnapshot snapshot,
    required int currentMri,
    DateTime? now,
  }) async {
    final update = CalibrationEngine.applyFeedback(
      profile: state,
      feedback: feedback,
      snapshot: snapshot,
      currentMri: currentMri,
      now: now ?? DateTime.now(),
    );
    if (!update.accepted) return false;
    state = update.profile;
    await _persist();
    return true;
  }

  /// 体感プロファイル画面からの手動調整。クランプ (§6.1) を通したうえで
  /// manualOverride を立て、ランプインを介さず全量適用する。
  Future<void> adjustManually(
    PersonalProfile Function(PersonalProfile current) change,
  ) async {
    state = change(state).clamped().copyWith(manualOverride: true);
    await _persist();
  }

  /// θ を全初期化 (mri-spec.md §6.3-6: 設定からワンタップでリセット)。
  Future<void> reset() async {
    state = PersonalProfile.initial();
    await _prefs.remove(kPrefKeyPersonalProfile);
  }

  Future<void> _persist() =>
      _prefs.setString(kPrefKeyPersonalProfile, jsonEncode(state.toJson()));

  static PersonalProfile _load(SharedPreferences prefs) {
    final raw = prefs.getString(kPrefKeyPersonalProfile);
    if (raw == null) return PersonalProfile.initial();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return PersonalProfile.fromJson(decoded);
      }
    } on FormatException {
      // 壊れた保存値は未学習へフォールバック (再学習で上書きされる)。
    }
    return PersonalProfile.initial();
  }
}

final personalProfileProvider =
    StateNotifierProvider<PersonalProfileController, PersonalProfile>((ref) {
  return PersonalProfileController(ref.watch(sharedPreferencesProvider));
});
