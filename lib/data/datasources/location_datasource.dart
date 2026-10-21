// lib/data/datasources/location_datasource.dart
//
// 現在地の取得。プライバシー方針 (agents.md / spec §13):
//   - 精度は COARSE のみ (LocationAccuracy.low ≈ 数百 m〜数 km)
//   - 取得するのは現在地 1 点のみ。履歴は保持・送信しない
//   - 失敗時は東京駅周辺へフォールバック (アプリを使用不能にしない)

import 'package:geolocator/geolocator.dart';

import '../../core/errors/app_exception.dart';
import '../../core/permissions/permission_request_queue.dart';
import '../../core/permissions/unanswered_permission_request.dart';

class GeoPoint {
  const GeoPoint(this.latitude, this.longitude, {this.isFallback = false});

  final double latitude;
  final double longitude;

  /// 位置情報が使えず既定地点 (東京) を返した場合 true。
  final bool isFallback;
}

class LocationDataSource {
  const LocationDataSource({
    this.permissionGiveUpAfter = kPermissionGiveUpAfter,
  });

  /// 既定フォールバック地点 (東京駅周辺。COARSE 精度相当の代表点)。
  static const fallback = GeoPoint(35.681, 139.767, isFallback: true);

  /// 許可の要求に回答が無いまま、アプリが前面で続けてこの時間たったら見切る
  /// (unanswered_permission_request.dart)。テストで短くする。
  final Duration permissionGiveUpAfter;

  /// COARSE 精度で現在地を 1 回だけ取得する。
  ///
  /// 権限拒否・サービス無効は [AppException] (日本語 userMessage) を投げる。
  /// 呼び出し側 (provider) が fallback を使うか UI に出すかを決める。
  ///
  /// 許可ダイアログへの回答を待ちきれずに見切ったあと (拒否として扱う)、
  /// 遅れて許可が届いたら [onLateGrant] を呼ぶ。呼び出し側は取り直す。
  Future<GeoPoint> getCurrentPosition({void Function()? onLateGrant}) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const AppException(
        '位置情報サービスが無効です。端末の設定でオンにしてください。',
        'Location services disabled',
        ErrorType.location,
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      // 通知など他の権限ダイアログと重ねない (重なると要求が取り消され、
      // requestPermission が終わらない。permission_request_queue.dart)。
      permission = await runPermissionRequest<LocationPermission>(() async {
        // 待っている間に別の要求で決まっていれば、それを使う (二重に聞かない)。
        final current = await Geolocator.checkPermission();
        if (current != LocationPermission.denied) return current;
        // 要求が取り消されると geolocator は応答しない。ダイアログが出ないまま
        // 回答も無ければ見切って今の許可状態で進め、キューを空ける (QA-17)。
        return requestPermissionOrGiveUp<LocationPermission>(
          request: Geolocator.requestPermission,
          check: Geolocator.checkPermission,
          giveUpAfter: permissionGiveUpAfter,
          onLateAnswer: (answer) {
            if (answer == LocationPermission.whileInUse ||
                answer == LocationPermission.always) {
              onLateGrant?.call();
            }
          },
        );
      });
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const AppException(
        '位置情報の利用を許可してください(設定 > プライバシー)。',
        'Location permission denied',
        ErrorType.permissionDenied,
      );
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          // COARSE のみ。Android は ACCESS_COARSE_LOCATION のみ宣言、
          // iOS は NSLocationDefaultAccuracyReduced=true と対応。
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return GeoPoint(position.latitude, position.longitude);
    } catch (e) {
      throw AppException(
        '現在地を取得できませんでした。電波の良い場所でお試しください。',
        'getCurrentPosition failed: $e',
        ErrorType.location,
      );
    }
  }
}
