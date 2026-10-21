import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Firebase: google-services.json を読み込み Firebase SDK を構成する。
    id("com.google.gms.google-services")
}

// key.properties(Git 管理外)からアップロード鍵情報を読む。
// ファイルが無い環境(CI の PR ビルド等)では release 署名をスキップして
// debug 署名にフォールバックし、`flutter run --release` を壊さない。
// 手順の正本: docs/release-setup.md §2, §4
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    // applicationId は Play 入稿後に変更不可。docs/release-setup.md §1.2 で確定済み。
    namespace = "com.teciora.moodringweather"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications が要求する core library desugaring を有効化
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.teciora.moodringweather"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Firebase Auth / Cloud Firestore は minSdk 23 以上が必要。
        // Flutter 既定がそれ未満でも 23 に引き上げる。
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // key.properties があればアップロード鍵で署名(Play App Signing 前提)。
            // 無ければ debug 署名にフォールバック(CI / 開発環境用)。
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // flutter_local_notifications の core library desugaring 用ライブラリ
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // JVM のユニットテスト (src/test。ライブ壁紙の区分と配色の表)。APK / AAB には入らない。
    // 実行: cd android && ./gradlew :app:testDebugUnitTest
    testImplementation("junit:junit:4.13.2")
}
