// lib/domain/calibration/calibration_engine.dart
//
// パーソナルキャリブレーションの更新則 (docs/mri-spec.md §6.2)。
// 「暑すぎ/やや暑/ちょうど/やや寒/寒すぎ」のフィードバックから
// 感受性ベクトル θ (PersonalProfile) を更新する。
//
// 過学習防止 4 重ガード (mri-spec.md §6.3):
//   1. ランプイン       … PersonalProfile.rampScale (適用側)
//   2. 学習率減衰       … η_n = 0.6 / (1 + n / 20)
//   3. クランプ         … 全パラメータにハードレンジ
//   4. 忘却 (縮小)      … β ← β × 0.98 (毎回)
//   5. 同日重複ガード   … 同一カレンダー日・同方向は 1 件のみ有効
//
// 純 Dart (Flutter 非依存)。ユニットテスト:
// test/unit/calibration_engine_test.dart (mri-spec.md §8.4 準拠)。

import '../../data/models/personal_profile.dart';
import '../../data/models/pollen_level.dart';
import '../../data/models/weather_snapshot.dart';
import 'calibration_feedback.dart';

/// applyFeedback の結果。同日重複ガードに弾かれた場合 accepted = false で
/// profile は入力のまま返る。
class CalibrationUpdate {
  const CalibrationUpdate({required this.profile, required this.accepted});

  final PersonalProfile profile;
  final bool accepted;
}

class CalibrationEngine {
  CalibrationEngine._();

  /// β の毎回縮小係数 (mri-spec.md §6.3-4 忘却)。
  static const double forgettingFactor = 0.98;

  /// M_opt の指数移動平均係数 (mri-spec.md §6.2 y=0)。
  static const double mOptAlpha = 0.2;

  /// 学習率 (減衰): η_n = 0.6 / (1 + n / 20)。n はこれまでの有効
  /// フィードバック数 (n=0: 0.6 → n=20: 0.3 → n=100: 0.1)。
  static double learningRate(int n) => 0.6 / (1 + n / 20.0);

  /// フィードバック 1 件で θ を更新する (mri-spec.md §6.2)。
  ///
  /// - [snapshot]: その時点の気象 (体感温度欠測時は気温で代用)。
  /// - [currentMri]: その時点の計算済み MRI (M_opt 更新に使用)。
  /// - [now]: 同日重複ガードの基準時刻 (省略時は snapshot.timestamp)。
  /// - [enforceDailyGuard]: テストモードでは false にしてガードを無効化できる
  ///   (mri-spec.md §8.4-2)。
  static CalibrationUpdate applyFeedback({
    required PersonalProfile profile,
    required CalibrationFeedback feedback,
    required WeatherSnapshot snapshot,
    required int currentMri,
    DateTime? now,
    bool enforceDailyGuard = true,
  }) {
    // === ガード 5: 同日重複 (同一カレンダー日・同方向は 1 件のみ) ===
    final when = now ?? snapshot.timestamp;
    final dayKey = _dayKey(when);
    final dirKey = _directionKey(feedback.direction);
    if (enforceDailyGuard &&
        profile.lastFeedbackDayByDirection[dirKey] == dayKey) {
      return CalibrationUpdate(profile: profile, accepted: false);
    }

    final n = profile.feedbackCount;
    final eta = learningRate(n);
    final tApp = snapshot.apparentTemperature ?? snapshot.temperature;

    var deltaT = profile.deltaT;
    var lambdaHeat = profile.lambdaHeat;
    var lambdaCool = profile.lambdaCool;
    var betaHumid = profile.betaHumid;
    var betaUv = profile.betaUv;
    var betaAqi = profile.betaAqi;
    var betaPollen = profile.betaPollen;
    var mOpt = profile.mOpt;

    final y = feedback.direction;
    if (y != 0) {
      // === y = ±1 (暑すぎ/寒すぎ。やや暑/やや寒は intensity 0.5) ===
      final etaEff = eta * feedback.intensity;

      // 1. δT ← clamp(δT − y × η, −3, +3)
      //    (暑すぎ → 本人の最適温度はより低い)
      deltaT = (deltaT - y * etaEff)
          .clamp(PersonalProfile.deltaTMin, PersonalProfile.deltaTMax);

      // 2. λ 更新 (体感温度が方向と一致する場合のみ)
      if (y > 0 && tApp > 25) {
        lambdaHeat = (lambdaHeat + 0.05 * etaEff / 0.6)
            .clamp(PersonalProfile.lambdaMin, PersonalProfile.lambdaMax);
      }
      if (y < 0 && tApp < 18) {
        lambdaCool = (lambdaCool + 0.05 * etaEff / 0.6)
            .clamp(PersonalProfile.lambdaMin, PersonalProfile.lambdaMax);
      }

      // 3. 要素帰責 (y = +1 のみ。「暑すぎ」の犯人探し)。欠測要素は e = 0。
      if (y > 0) {
        final h = snapshot.humidity;
        final uv = snapshot.uvIndex;
        final aqi = snapshot.aqi;
        final eHumid =
            h == null ? 0.0 : ((h - 55) / 30).clamp(0.0, 1.0).toDouble();
        final eUv =
            uv == null ? 0.0 : ((uv - 4) / 6).clamp(0.0, 1.0).toDouble();
        final eAqi =
            aqi == null ? 0.0 : ((aqi - 80) / 100).clamp(0.0, 1.0).toDouble();
        final ePollen = snapshot.pollen == PollenLevel.high ||
                snapshot.pollen == PollenLevel.veryHigh
            ? 1.0
            : 0.0;
        double bump(double beta, double e) => (beta + 0.25 * etaEff * e)
            .clamp(PersonalProfile.betaMin, PersonalProfile.betaMax);
        betaHumid = bump(betaHumid, eHumid);
        betaUv = bump(betaUv, eUv);
        betaAqi = bump(betaAqi, eAqi);
        betaPollen = bump(betaPollen, ePollen);
      }
    } else {
      // === y = 0 (ちょうど) ===
      // 1. M_opt ← clamp((1−α) M_opt + α MRI_now, 50, 85)
      mOpt = ((1 - mOptAlpha) * mOpt + mOptAlpha * currentMri)
          .clamp(PersonalProfile.mOptMin, PersonalProfile.mOptMax);
      // 2. δT を「ちょうど」の体感温度へ弱く引き寄せる
      deltaT = 0.9 * deltaT +
          0.1 *
              (tApp - 22.0)
                  .clamp(PersonalProfile.deltaTMin, PersonalProfile.deltaTMax);
    }

    // === 毎回 (y によらず): 忘却 β ← β × 0.98、n ← n + 1 ===
    betaHumid *= forgettingFactor;
    betaUv *= forgettingFactor;
    betaAqi *= forgettingFactor;
    betaPollen *= forgettingFactor;

    final updated = profile.copyWith(
      deltaT: deltaT,
      lambdaHeat: lambdaHeat,
      lambdaCool: lambdaCool,
      betaHumid: betaHumid,
      betaUv: betaUv,
      betaAqi: betaAqi,
      betaPollen: betaPollen,
      mOpt: mOpt,
      feedbackCount: n + 1,
      lastFeedbackDayByDirection: {
        ...profile.lastFeedbackDayByDirection,
        dirKey: dayKey,
      },
    );
    return CalibrationUpdate(profile: updated, accepted: true);
  }

  static String _dayKey(DateTime t) {
    final local = t.toLocal();
    final mm = local.month.toString().padLeft(2, '0');
    final dd = local.day.toString().padLeft(2, '0');
    return '${local.year}-$mm-$dd';
  }

  static String _directionKey(int direction) {
    if (direction > 0) return 'hot';
    if (direction < 0) return 'cold';
    return 'neutral';
  }
}
