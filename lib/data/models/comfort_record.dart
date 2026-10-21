// lib/data/models/comfort_record.dart
//
// Comfort-Twin のオンデバイス記録 (spec: 今日の体感 / 思い出の日 /
// お気に入りの場所) と、Plus 多地点の「保存地点」。純 Dart。SharedPreferences に
// JSON 配列で保存し、サーバーへは一切送信しない (spec.md §13)。
//
// 保存地点 (type = place) の後方互換:
//   - v1.3.0 以前の記録は `location` / `addedAt` を持たない (座標なし扱い)。
//     Comfort-Twin 由来 (`place-{cityId}`) は同梱カタログから座標を補う
//     (domain/places/saved_place_rules.dart の resolveSavedPlaces)。
//   - 地名検索で追加した地点 (`place-geo-{geonamesId}`) は保存時点の天気を
//     持たないため `mri` が null。

import 'place_location.dart';

/// 記録の種類。
enum ComfortRecordType {
  /// 「今日の体感」(その日の自分の MRI を記録)。
  day,

  /// 「保存地点」(Compare 画面の「この場所を保存」/ 地名検索で追加)。
  place;

  static ComfortRecordType parse(String? tag) {
    for (final t in ComfortRecordType.values) {
      if (t.name == tag) return t;
    }
    return ComfortRecordType.day;
  }
}

class ComfortRecord {
  const ComfortRecord({
    required this.id,
    required this.type,
    required this.mri,
    required this.savedAt,
    this.label,
    this.emoji,
    this.location,
    this.addedAt,
  });

  /// 一意 ID (保存時刻ミリ秒など)。削除・重複排除キー。
  /// 保存地点は Comfort-Twin 由来が `place-{cityId}`、地名検索由来が
  /// `place-geo-{geonamesId}`。
  final String id;

  final ComfortRecordType type;

  /// 記録した MRI 値 (Comfort-Twin 検索のターゲットとして再利用する)。
  /// 地名検索で追加した保存地点は天気を取得する前に保存するので null。
  final int? mri;

  /// 最後に保存 (更新) した時刻。
  final DateTime savedAt;

  /// 表示ラベル (place: 都市名。day: null → UI 側で日付を整形表示)。
  final String? label;

  /// 絵文字 (place: 国旗など)。
  final String? emoji;

  /// 保存地点の位置と地域情報。旧記録・day は null。
  final PlaceLocation? location;

  /// 保存地点を最初に追加した時刻 (並び順 = 追加順の基準)。再保存
  /// (更新) では変えない。旧記録は null → [savedAt] で代用する。
  final DateTime? addedAt;

  ComfortRecord copyWith({
    int? mri,
    DateTime? savedAt,
    String? label,
    String? emoji,
    PlaceLocation? location,
    DateTime? addedAt,
  }) =>
      ComfortRecord(
        id: id,
        type: type,
        mri: mri ?? this.mri,
        savedAt: savedAt ?? this.savedAt,
        label: label ?? this.label,
        emoji: emoji ?? this.emoji,
        location: location ?? this.location,
        addedAt: addedAt ?? this.addedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'mri': mri,
        'savedAt': savedAt.toIso8601String(),
        'label': label,
        'emoji': emoji,
        if (location != null) 'location': location!.toJson(),
        if (addedAt != null) 'addedAt': addedAt!.toIso8601String(),
      };

  factory ComfortRecord.fromJson(Map<String, dynamic> json) {
    final addedAt = json['addedAt'];
    return ComfortRecord(
      id: json['id'] as String,
      type: ComfortRecordType.parse(json['type'] as String?),
      mri: (json['mri'] as num?)?.toInt(),
      savedAt: DateTime.parse(json['savedAt'] as String),
      label: json['label'] as String?,
      emoji: json['emoji'] as String?,
      location: PlaceLocation.tryParse(json['location']),
      addedAt: addedAt is String ? DateTime.tryParse(addedAt) : null,
    );
  }

  /// 壊れた 1 件だけを捨てるための寛容な復元 (必須項目が欠ければ null)。
  static ComfortRecord? tryParse(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    try {
      return ComfortRecord.fromJson(json);
    } catch (_) {
      return null;
    }
  }
}
