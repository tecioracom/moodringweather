# Mood-Ring Weather

その日の体感を、気温ではなく1本のリングで見せる天気アプリ。Flutter 製で
iOS と Android に出している。日本語・英語・スペイン語・中国語（簡体）。

## MRI という指標

気温・湿度・風・日射から **MRI（Mood Ring Index）** を出す。0〜100 の1本の軸で、
100 側が冷涼（青）、64 付近が快適（緑）、0 側が暑熱・不快（赤）になる。
「何度か」ではなく「どのくらい過ごしやすいか」を先に出す。

値だけでは足りない場面があって、そこは作りで補っている。MRI は体感 −4 °C 前後で
下げ幅が上限に達し、それより寒いと値が横ばいになる。つまり「快適な冷涼」と
「危険な酷寒」が同じ値になりうる。そこで**値と帯はそのままに、表示する区分名だけ**を
体感温度で決めている（`lib/domain/mri/cold_label.dart`）。
境界は実測から引いた。冬の「気温 − 体感温度」の中央値は東京・札幌の12〜2月、
2016〜2025年で 4.0〜4.6 °C。「気温10 °C 未満＝寒い」を体感に換算して 6.0 °C とした。
「とても寒い」は Environment Canada の風冷指数の moderate risk の下端 −10 °C。

体感には個人差があるので、使っているうちに補正する仕組みも入れてある
（`lib/domain/calibration/`）。寒さに強いと学習した人でも、厳寒のときは
区分名が「とても寒い」に上書きされる。学習が安全側の表示を消さないようにしている。

## 画面の外でも見える

- **ホーム／ロック画面のウィジェット**（iOS・SwiftUI、`ios/MoodRingWidget/`）
- **ライブ壁紙**（Android・Kotlin、`android/app/src/main/kotlin/.../wallpaper/`）

どちらもアプリを開かずにリングの色だけが目に入る。この2つが主で、
アプリ本体はその詳細を見るところ、という組み立てにしている。

## 作り

```
lib/
  domain/      MRI の計算、区分名、補正、場所、通知、熱中症の判定。純 Dart
  data/        気象 API、課金、プッシュ、壁紙、保存
  presentation/ 画面
  providers/   Riverpod
  l10n/        4言語の .arb
workers/       Cloudflare Workers。緊急通知と個人向け通知の cron、課金 Webhook
```

`domain/` は Flutter に依存させていない。計算の部分だけを Dart のテストで
回せるようにするため。テストは102本ある。

気象データは Open-Meteo。状態管理は Riverpod、課金は RevenueCat、
プッシュは Firebase Cloud Messaging。

## 動かす

```bash
flutter pub get
flutter gen-l10n        # lib/l10n/*.arb から AppLocalizations を作る
flutter run
```

```bash
flutter analyze
flutter test
```

`flutter gen-l10n` は必須。生成物をリポジトリに入れていないので、先に走らせないと
`AppLocalizations` が見つからない。翻訳漏れがあるとビルドを止めるようにしてある。

## 入っていないもの

**手元にしか無い値と、アカウントを指す値は置いていない。**

| | |
|---|---|
| Android の署名（`upload-keystore.jks` / `key.properties`） | 漏れると他人がこのアプリの更新に署名できる。雛形だけ `android/key.properties.example` にある |
| Firebase の構成（`google-services.json` / `GoogleService-Info.plist`） | Google API キーとプロジェクト ID を含む |
| Apple Developer の Team ID | `project.pbxproj` の `DEVELOPMENT_TEAM` は空にしてある |
| サービスアカウント鍵・`.p8` | Play の API は `tool/play_api.py` が環境変数 `PLAY_SA_JSON` から読む |
| `local.properties` / `Pods` / `xcuserdata` | 手元の道と個人設定 |
| 生成物 | `flutter gen-l10n` の出力、GeneratedPluginRegistrant、gradle wrapper |

**Firebase の構成ファイルが無くてもアプリは通常どおり起動する。**
`lib/data/push/firebase_push_runtime.dart` が、構成が無い・初期化に失敗した・
匿名認証が無効、のどの場合でもプッシュだけを無効にして先へ進む。
ローカル通知は影響を受けない。自分の Firebase プロジェクトの構成を置けば
プッシュが動く。

`.gitignore` に名前で落とす規則を入れてあり、8種類のファイルを戻して実際に
除外されることを確認してある。

## 同梱フォント

IBM Plex Sans JP / IBM Plex Mono / Inter / Fraunces。すべて SIL Open Font License で、
`assets/fonts/` に OFL の本文を同梱している。`test/unit/font_licenses_test.dart` が
アプリ内の表示を検証する。

---

制作: [Teciora](https://www.teciora.com/)
