// test/unit/calibration_engine_test.dart
//
// パーソナルキャリブレーション (docs/mri-spec.md §6) のユニットテスト。
// 期待値は mri-spec.md §8.4 のキャリブレーション・テスト要件に 1:1 対応:
//   1. 「暑すぎ」1 件の更新値 (δT/λ_heat/β_humid) + n<5 はデフォルト表示
//   2. 連投でもクランプで発散しない
//   3. 「ちょうど」10 件で M_opt が収束 (≈69.4 → 69)
//   4. リセットで既定値・デフォルト計算と一致
//   5. プロパティテスト |MRI_personal − MRI_default| ≤ 15
//   6. 学習データはローカルストレージ (SharedPreferences) のみに保存
// 加えて §6.3 の各ガード (学習率減衰・忘却・同日重複) を検証する。

import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/data/models/personal_profile.dart';
import 'package:mood_ring_weather/data/models/pollen_level.dart';
import 'package:mood_ring_weather/data/models/weather_snapshot.dart';
import 'package:mood_ring_weather/domain/calibration/calibration_engine.dart';
import 'package:mood_ring_weather/domain/calibration/calibration_feedback.dart';
import 'package:mood_ring_weather/domain/calibration/calibration_insights.dart';
import 'package:mood_ring_weather/domain/mri/mri_calculator.dart';
import 'package:mood_ring_weather/presentation/locale/locale_controller.dart';
import 'package:mood_ring_weather/providers/calibration_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

WeatherSnapshot _snapshot({
  double temperature = 22,
  double? apparent,
  double humidity = 50,
  double uv = 3,
  int aqi = 42,
  PollenLevel pollen = PollenLevel.low,
  double wind = 2,
  double pressureChange6h = 0,
  DateTime? timestamp,
}) {
  return WeatherSnapshot(
    timestamp: timestamp ?? DateTime(2026, 7, 1, 13),
    latitude: 35.66,
    longitude: 139.70,
    temperature: temperature,
    apparentTemperature: apparent ?? temperature,
    humidity: humidity,
    pressure: 1013,
    pressureChange6h: pressureChange6h,
    windSpeed: wind,
    uvIndex: uv,
    aqi: aqi,
    pollen: pollen,
    condition: 'sunny',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('学習率 η_n (mri-spec §6.2 / §6.3-2)', () {
    test('n=0: 0.6 → n=20: 0.3 → n=100: 0.1 と単調減衰する', () {
      expect(CalibrationEngine.learningRate(0), closeTo(0.6, 1e-12));
      expect(CalibrationEngine.learningRate(20), closeTo(0.3, 1e-12));
      expect(CalibrationEngine.learningRate(100), closeTo(0.1, 1e-12));
      // §6.3-7: n=247 で η ≈ 0.045 (実用収束目安)
      expect(CalibrationEngine.learningRate(247), closeTo(0.045, 0.001));
    });
  });

  group('§8.4-1: 「暑すぎ」1 件 (T_app=30, H=70)', () {
    test('δT=−0.6 / λ_heat=1.05 / β_humid=+0.0735 (0.075 × 0.98)', () {
      final snapshot = _snapshot(temperature: 30, humidity: 70, uv: 2, aqi: 40);
      final update = CalibrationEngine.applyFeedback(
        profile: PersonalProfile.initial(),
        feedback: CalibrationFeedback.tooHot,
        snapshot: snapshot,
        currentMri: 40,
      );

      expect(update.accepted, isTrue);
      final p = update.profile;
      expect(p.deltaT, closeTo(-0.6, 1e-9));
      expect(p.lambdaHeat, closeTo(1.05, 1e-9));
      expect(p.betaHumid, closeTo(0.0735, 1e-9));
      // 帰責なしの要素 (UV2/AQI40/花粉low) は e=0 → β は 0 のまま
      expect(p.betaUv, closeTo(0, 1e-9));
      expect(p.betaAqi, closeTo(0, 1e-9));
      expect(p.betaPollen, closeTo(0, 1e-9));
      expect(p.feedbackCount, 1);
    });

    test('n<5 (ランプイン §6.3-1): 表示 MRI はデフォルトと完全一致', () {
      final snapshot = _snapshot(temperature: 30, humidity: 70);
      var profile = PersonalProfile.initial();
      for (var i = 0; i < 4; i++) {
        profile = CalibrationEngine.applyFeedback(
          profile: profile,
          feedback: CalibrationFeedback.tooHot,
          snapshot: snapshot,
          currentMri: 40,
          enforceDailyGuard: false,
        ).profile;
      }
      expect(profile.feedbackCount, 4);
      expect(profile.rampScale, 0.0);

      final byDefault = MriCalculator.calculate(snapshot);
      final personal = MriCalculator.calculate(snapshot, profile: profile);
      expect(personal.value, byDefault.value);
      expect(personal.isPersonalized, isFalse);
    });
  });

  group('§8.4-2: 連投クランプ (§6.3-3)', () {
    test('「暑すぎ」30 件連投 (ガード無効) でも δT は −3.0 で止まり発散しない', () {
      final snapshot = _snapshot(temperature: 33, humidity: 80, uv: 8);
      var profile = PersonalProfile.initial();
      for (var i = 0; i < 30; i++) {
        profile = CalibrationEngine.applyFeedback(
          profile: profile,
          feedback: CalibrationFeedback.tooHot,
          snapshot: snapshot,
          currentMri: 30,
          enforceDailyGuard: false,
        ).profile;
      }
      expect(profile.deltaT, PersonalProfile.deltaTMin); // = −3.0
      expect(profile.lambdaHeat, lessThanOrEqualTo(PersonalProfile.lambdaMax));
      expect(profile.betaHumid, lessThanOrEqualTo(PersonalProfile.betaMax));
      expect(profile.betaUv, lessThanOrEqualTo(PersonalProfile.betaMax));
      expect(profile.feedbackCount, 30);
    });

    test('「寒すぎ」60 件連投でも δT は +3.0 / λ_cool は 1.5 で止まる', () {
      final snapshot = _snapshot(temperature: 5, humidity: 40);
      var profile = PersonalProfile.initial();
      for (var i = 0; i < 60; i++) {
        profile = CalibrationEngine.applyFeedback(
          profile: profile,
          feedback: CalibrationFeedback.tooCold,
          snapshot: snapshot,
          currentMri: 85,
          enforceDailyGuard: false,
        ).profile;
      }
      expect(profile.deltaT, PersonalProfile.deltaTMax); // = +3.0
      expect(profile.lambdaCool, lessThanOrEqualTo(PersonalProfile.lambdaMax));
    });
  });

  group('§8.4-3: 「ちょうど」と M_opt', () {
    test('MRI=70 で 10 件 → M_opt ≈ 69.4、estimatedOptimalMRI = 69', () {
      final snapshot = _snapshot(); // T_app = 22 → δT はほぼ動かない
      var profile = PersonalProfile.initial();
      for (var i = 0; i < 10; i++) {
        profile = CalibrationEngine.applyFeedback(
          profile: profile,
          feedback: CalibrationFeedback.justRight,
          snapshot: snapshot,
          currentMri: 70,
          enforceDailyGuard: false,
        ).profile;
      }
      final expected = 64 * pow(0.8, 10) + 70 * (1 - pow(0.8, 10));
      expect(profile.mOpt, closeTo(expected.toDouble(), 1e-9));
      expect(profile.mOpt, closeTo(69.4, 0.05));
      expect(profile.estimatedOptimalMri, 69);
      expect(profile.deltaT, closeTo(0, 1e-9)); // T_app=22 → 引き寄せ先は 0
    });

    test('M_opt はクランプ範囲 [50, 85] を出ない', () {
      final snapshot = _snapshot();
      var high = PersonalProfile.initial();
      var low = PersonalProfile.initial();
      for (var i = 0; i < 50; i++) {
        high = CalibrationEngine.applyFeedback(
          profile: high,
          feedback: CalibrationFeedback.justRight,
          snapshot: snapshot,
          currentMri: 100,
          enforceDailyGuard: false,
        ).profile;
        low = CalibrationEngine.applyFeedback(
          profile: low,
          feedback: CalibrationFeedback.justRight,
          snapshot: snapshot,
          currentMri: 0,
          enforceDailyGuard: false,
        ).profile;
      }
      expect(high.mOpt, lessThanOrEqualTo(PersonalProfile.mOptMax));
      expect(low.mOpt, greaterThanOrEqualTo(PersonalProfile.mOptMin));
    });
  });

  group('§8.4-4: リセット', () {
    test('PersonalProfile.initial() は §6.1 の既定値で、MRI はデフォルトと一致', () {
      final reset = PersonalProfile.initial();
      expect(reset.deltaT, 0.0);
      expect(reset.lambdaHeat, 1.0);
      expect(reset.lambdaCool, 1.0);
      expect(reset.betaHumid, 0.0);
      expect(reset.betaUv, 0.0);
      expect(reset.betaAqi, 0.0);
      expect(reset.betaPollen, 0.0);
      expect(reset.mOpt, 64.0);
      expect(reset.estimatedOptimalMri, 64);
      expect(reset.feedbackCount, 0);
      expect(reset.isNeutral, isTrue);

      final snapshot = _snapshot(temperature: 33, humidity: 65, uv: 8);
      expect(
        MriCalculator.calculate(snapshot, profile: reset).value,
        MriCalculator.calculate(snapshot).value,
      );
    });
  });

  group('§8.4-5: プロパティテスト |MRI_personal − MRI_default| ≤ 15 (§6.4)', () {
    test('クランプ範囲内の任意の θ × ランダム気象 300 通りで成立する', () {
      final random = Random(42);
      for (var i = 0; i < 300; i++) {
        final theta = PersonalProfile(
          deltaT: -3 + random.nextDouble() * 6,
          lambdaHeat: 0.7 + random.nextDouble() * 0.8,
          lambdaCool: 0.7 + random.nextDouble() * 0.8,
          betaHumid: -0.5 + random.nextDouble(),
          betaUv: -0.5 + random.nextDouble(),
          betaAqi: -0.5 + random.nextDouble(),
          betaPollen: -0.5 + random.nextDouble(),
          manualOverride: true, // ランプインを介さず全量適用
        );
        final snapshot = _snapshot(
          temperature: -10 + random.nextDouble() * 50,
          apparent: -15 + random.nextDouble() * 65,
          humidity: random.nextDouble() * 100,
          uv: random.nextDouble() * 12,
          aqi: random.nextInt(350),
          pollen: PollenLevel.values[random.nextInt(PollenLevel.values.length)],
          wind: random.nextDouble() * 15,
          pressureChange6h: -10 + random.nextDouble() * 20,
        );
        final byDefault = MriCalculator.calculate(snapshot);
        final personal = MriCalculator.calculate(snapshot, profile: theta);
        expect(
          (personal.value - byDefault.value).abs(),
          lessThanOrEqualTo(15),
          reason: 'iteration $i: default=${byDefault.value} '
              'personal=${personal.value} theta=${theta.toJson()}',
        );
      }
    });
  });

  group('§8.4-6: ローカルストレージのみに保存 (provider)', () {
    Future<ProviderContainer> container(
        {Map<String, Object> initial = const {}}) async {
      SharedPreferences.setMockInitialValues(initial);
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('submitFeedback で SharedPreferences に JSON 保存 → 別コンテナで復元', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final c1 = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(c1.dispose);

      final accepted =
          await c1.read(personalProfileProvider.notifier).submitFeedback(
                feedback: CalibrationFeedback.tooHot,
                snapshot: _snapshot(temperature: 30, humidity: 70),
                currentMri: 40,
                now: DateTime(2026, 7, 1, 13),
              );
      expect(accepted, isTrue);
      expect(prefs.getString(kPrefKeyPersonalProfile), isNotNull);

      // 「再起動」(別コンテナ・同じストレージ) で θ が復元される
      final c2 = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(c2.dispose);
      final restored = c2.read(personalProfileProvider);
      expect(restored.feedbackCount, 1);
      expect(restored.deltaT, closeTo(-0.6, 1e-9));
    });

    test('reset でストレージからも消える', () async {
      final c = await container();
      final notifier = c.read(personalProfileProvider.notifier);
      await notifier.submitFeedback(
        feedback: CalibrationFeedback.justRight,
        snapshot: _snapshot(),
        currentMri: 64,
        now: DateTime(2026, 7, 1, 13),
      );
      await notifier.reset();
      expect(c.read(personalProfileProvider).isNeutral, isTrue);
      expect(c.read(personalProfileProvider).feedbackCount, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kPrefKeyPersonalProfile), isNull);
    });

    test('手動調整はクランプされ、ランプインを介さず全量適用される', () async {
      final c = await container();
      final notifier = c.read(personalProfileProvider.notifier);
      await notifier.adjustManually(
        (p) => p.copyWith(deltaT: -99.0, lambdaHeat: 9.0),
      );
      final p = c.read(personalProfileProvider);
      expect(p.deltaT, PersonalProfile.deltaTMin);
      expect(p.lambdaHeat, PersonalProfile.lambdaMax);
      expect(p.manualOverride, isTrue);
      expect(p.rampScale, 1.0);
    });
  });

  group('§6.3-5: 同日重複ガード', () {
    test('同一カレンダー日の同方向 2 件目は無効 (やや暑も同方向)', () {
      final snapshot = _snapshot(temperature: 30, humidity: 70);
      final day1 = DateTime(2026, 7, 1, 9);
      final first = CalibrationEngine.applyFeedback(
        profile: PersonalProfile.initial(),
        feedback: CalibrationFeedback.tooHot,
        snapshot: snapshot,
        currentMri: 40,
        now: day1,
      );
      expect(first.accepted, isTrue);

      final sameDay = CalibrationEngine.applyFeedback(
        profile: first.profile,
        feedback: CalibrationFeedback.slightlyHot, // 同方向 (y=+1)
        snapshot: snapshot,
        currentMri: 40,
        now: DateTime(2026, 7, 1, 18),
      );
      expect(sameDay.accepted, isFalse);
      expect(sameDay.profile.feedbackCount, 1); // 不変

      // 別方向は同日でも有効
      final otherDirection = CalibrationEngine.applyFeedback(
        profile: first.profile,
        feedback: CalibrationFeedback.justRight,
        snapshot: snapshot,
        currentMri: 60,
        now: DateTime(2026, 7, 1, 20),
      );
      expect(otherDirection.accepted, isTrue);

      // 翌日は同方向でも有効
      final nextDay = CalibrationEngine.applyFeedback(
        profile: first.profile,
        feedback: CalibrationFeedback.tooHot,
        snapshot: snapshot,
        currentMri: 40,
        now: DateTime(2026, 7, 2, 9),
      );
      expect(nextDay.accepted, isTrue);
      expect(nextDay.profile.feedbackCount, 2);
    });
  });

  group('§6.2: 更新則の方向・条件', () {
    test('「寒すぎ」(T_app=10): δT=+0.6 / λ_cool=1.05', () {
      final update = CalibrationEngine.applyFeedback(
        profile: PersonalProfile.initial(),
        feedback: CalibrationFeedback.tooCold,
        snapshot: _snapshot(temperature: 10),
        currentMri: 85,
      );
      expect(update.profile.deltaT, closeTo(0.6, 1e-9));
      expect(update.profile.lambdaCool, closeTo(1.05, 1e-9));
      expect(update.profile.lambdaHeat, closeTo(1.0, 1e-9));
    });

    test('体感温度が方向と不一致なら λ は更新しない (暑すぎ at T_app=20)', () {
      final update = CalibrationEngine.applyFeedback(
        profile: PersonalProfile.initial(),
        feedback: CalibrationFeedback.tooHot,
        snapshot: _snapshot(temperature: 20, humidity: 50),
        currentMri: 60,
      );
      expect(update.profile.deltaT, closeTo(-0.6, 1e-9));
      expect(update.profile.lambdaHeat, closeTo(1.0, 1e-9));
    });

    test('「やや暑」は intensity 0.5 で半分だけ学習する', () {
      final update = CalibrationEngine.applyFeedback(
        profile: PersonalProfile.initial(),
        feedback: CalibrationFeedback.slightlyHot,
        snapshot: _snapshot(temperature: 30, humidity: 70),
        currentMri: 45,
      );
      expect(update.profile.deltaT, closeTo(-0.3, 1e-9));
      expect(update.profile.lambdaHeat, closeTo(1.025, 1e-9));
      expect(update.profile.betaHumid, closeTo(0.075 * 0.5 * 0.98, 1e-9));
    });

    test('花粉 high/veryHigh の「暑すぎ」で β_pollen に帰責される', () {
      final update = CalibrationEngine.applyFeedback(
        profile: PersonalProfile.initial(),
        feedback: CalibrationFeedback.tooHot,
        snapshot: _snapshot(
          temperature: 28,
          humidity: 40,
          pollen: PollenLevel.veryHigh,
        ),
        currentMri: 50,
      );
      // e_pollen = 1 → 0.25 × 0.6 × 1 = 0.15 → ×0.98 = 0.147
      expect(update.profile.betaPollen, closeTo(0.147, 1e-9));
    });

    test('忘却 (§6.3-4): フィードバックごとに β が 0.98 倍へ縮小する', () {
      final hot = CalibrationEngine.applyFeedback(
        profile: PersonalProfile.initial(),
        feedback: CalibrationFeedback.tooHot,
        snapshot: _snapshot(temperature: 30, humidity: 70),
        currentMri: 40,
        now: DateTime(2026, 7, 1),
      ).profile;
      expect(hot.betaHumid, closeTo(0.0735, 1e-9));

      // 帰責の起きない「ちょうど」でも β は縮小される
      final after = CalibrationEngine.applyFeedback(
        profile: hot,
        feedback: CalibrationFeedback.justRight,
        snapshot: _snapshot(),
        currentMri: 64,
        now: DateTime(2026, 7, 2),
      ).profile;
      expect(after.betaHumid, closeTo(0.0735 * 0.98, 1e-9));
    });
  });

  group('§6.3-1: ランプイン', () {
    test('n=5 で 0、n=12 で 7/15、n=20 で 1.0 にスケールする', () {
      const theta = PersonalProfile(deltaT: -3.0, lambdaHeat: 1.5);
      expect(theta.copyWith(feedbackCount: 4).rampScale, 0.0);
      expect(theta.copyWith(feedbackCount: 5).rampScale, 0.0);
      expect(
          theta.copyWith(feedbackCount: 12).rampScale, closeTo(7 / 15, 1e-12));
      expect(theta.copyWith(feedbackCount: 20).rampScale, 1.0);

      final mid = theta.copyWith(feedbackCount: 12).rampScaled();
      expect(mid.deltaT, closeTo(-3.0 * 7 / 15, 1e-12));
      expect(mid.lambdaHeat, closeTo(1.0 + 0.5 * 7 / 15, 1e-12));
    });

    test('5 ≤ n < 20 では部分適用 (デフォルトと全量適用の間)', () {
      final snapshot = _snapshot(temperature: 33, apparent: 40, humidity: 65);
      const theta = PersonalProfile(deltaT: -2.0, lambdaHeat: 1.4);
      final byDefault = MriCalculator.calculate(snapshot).value;
      final full = MriCalculator.calculate(
        snapshot,
        profile: theta.copyWith(feedbackCount: 20),
      ).value;
      final partial = MriCalculator.calculate(
        snapshot,
        profile: theta.copyWith(feedbackCount: 12),
      ).value;
      expect(full, lessThan(byDefault)); // 暑がり補正で MRI は下がる
      expect(partial, lessThanOrEqualTo(byDefault));
      expect(partial, greaterThanOrEqualTo(full));
    });
  });

  group('MriCalculator のパーソナル補正 (§6.1)', () {
    test('δT < 0 (暑がり) は涼しい日の MRI を押し上げる', () {
      final snapshot = _snapshot(temperature: 19);
      const theta = PersonalProfile(
        deltaT: -3.0,
        feedbackCount: 20,
      );
      final byDefault = MriCalculator.calculate(snapshot);
      final personal = MriCalculator.calculate(snapshot, profile: theta);
      // T_opt = 19 → temp score 100 (デフォルトは 89.5)
      expect(personal.value, greaterThan(byDefault.value));
      expect(personal.isPersonalized, isTrue);
    });

    test('λ_heat > 1 は猛暑日の MRI をさらに押し下げる', () {
      final snapshot = _snapshot(temperature: 33, apparent: 40, humidity: 65);
      const theta = PersonalProfile(lambdaHeat: 1.5, feedbackCount: 20);
      final byDefault = MriCalculator.calculate(snapshot);
      final personal = MriCalculator.calculate(snapshot, profile: theta);
      expect(personal.value, lessThan(byDefault.value));
    });

    test('β_humid > 0 は多湿日の重みを増やし MRI を押し下げる', () {
      final snapshot = _snapshot(temperature: 30, humidity: 85);
      const theta = PersonalProfile(betaHumid: 0.5, feedbackCount: 20);
      final byDefault = MriCalculator.calculate(snapshot);
      final personal = MriCalculator.calculate(snapshot, profile: theta);
      expect(personal.value, lessThan(byDefault.value));
    });

    test('重み補正後も factorContributions の合計重みは 1.0 (正規化)', () {
      final snapshot = _snapshot();
      const theta = PersonalProfile(
        betaHumid: 0.5,
        betaUv: -0.5,
        betaAqi: 0.3,
        betaPollen: -0.2,
        feedbackCount: 20,
      );
      final personal = MriCalculator.calculate(snapshot, profile: theta);
      final scores = MriCalculator.computeFactorScores(snapshot);
      // 寄与/スコア = 実効重み。合計が 1.0 に正規化されていること。
      var weightSum = 0.0;
      personal.factorContributions.forEach((key, contribution) {
        weightSum += contribution / scores[key]!;
      });
      expect(weightSum, closeTo(1.0, 1e-9));
    });
  });

  group('PersonalProfile JSON (オンデバイス永続化)', () {
    test('toJson → fromJson でロスレスに復元できる', () {
      var profile = PersonalProfile.initial();
      profile = CalibrationEngine.applyFeedback(
        profile: profile,
        feedback: CalibrationFeedback.tooHot,
        snapshot: _snapshot(temperature: 31, humidity: 75, uv: 8),
        currentMri: 35,
        now: DateTime(2026, 7, 1, 13),
      ).profile;
      profile = CalibrationEngine.applyFeedback(
        profile: profile,
        feedback: CalibrationFeedback.justRight,
        snapshot: _snapshot(),
        currentMri: 66,
        now: DateTime(2026, 7, 2, 13),
      ).profile;

      final round = PersonalProfile.fromJson(profile.toJson());
      expect(round.deltaT, closeTo(profile.deltaT, 1e-12));
      expect(round.lambdaHeat, closeTo(profile.lambdaHeat, 1e-12));
      expect(round.lambdaCool, closeTo(profile.lambdaCool, 1e-12));
      expect(round.betaHumid, closeTo(profile.betaHumid, 1e-12));
      expect(round.betaUv, closeTo(profile.betaUv, 1e-12));
      expect(round.betaAqi, closeTo(profile.betaAqi, 1e-12));
      expect(round.betaPollen, closeTo(profile.betaPollen, 1e-12));
      expect(round.mOpt, closeTo(profile.mOpt, 1e-12));
      expect(round.feedbackCount, profile.feedbackCount);
      expect(round.manualOverride, profile.manualOverride);
      expect(
        round.lastFeedbackDayByDirection,
        profile.lastFeedbackDayByDirection,
      );
    });

    test('壊れた JSON 値はクランプ済み既定値へフォールバックする', () {
      final p = PersonalProfile.fromJson({
        'deltaT': 99,
        'lambdaHeat': 'broken',
        'mOpt': -5,
        'feedbackCount': 3.0,
      });
      expect(p.deltaT, PersonalProfile.deltaTMax);
      expect(p.lambdaHeat, 1.0);
      expect(p.mOpt, PersonalProfile.mOptMin);
      expect(p.feedbackCount, 3);
    });
  });

  group('CalibrationInsights (わかってきたこと)', () {
    test('未学習では空、θ が動くと対応する洞察が出る', () {
      expect(CalibrationInsights.derive(PersonalProfile.initial()), isEmpty);
      const learned = PersonalProfile(
        deltaT: -1.2,
        lambdaHeat: 1.2,
        betaHumid: 0.15,
      );
      final insights = CalibrationInsights.derive(learned);
      expect(insights, contains(CalibrationInsight.prefersCooler));
      expect(insights, contains(CalibrationInsight.heatSensitive));
      expect(insights, contains(CalibrationInsight.humiditySensitive));
      expect(insights, isNot(contains(CalibrationInsight.coldSensitive)));
    });
  });
}
