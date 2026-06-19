import 'dart:convert';

import 'register_item.dart';

/// Status colour returned by the backend for an asset.
///
/// Maps to the `colour` field in the `app_fetch_all_assets` response.
enum AssetColour {
  red,
  yellow,
  green;

  static AssetColour? fromString(String? value) {
    if (value == null || value.isEmpty) return null;
    return switch (value.toLowerCase().trim()) {
      'red' => AssetColour.red,
      'yellow' => AssetColour.yellow,
      'green' => AssetColour.green,
      _ => null,
    };
  }

  String get displayText => switch (this) {
        red => 'Red',
        yellow => 'Yellow',
        green => 'Green',
      };
}

class Asset {
  final String id;
  final String buildingId;
  final String taskName;
  final String? nickname;
  final String? assetRegisterItems;
  final String? tooltipText;
  final String? tooltipUrls;
  final DateTime? lastCompleted;
  final DateTime? dueDate;
  final String? frequency;
  final AssetColour? colour;
  final String? location;
  final String? floor;
  final DateTime? yellowDate;
  final DateTime? assetLastModified;
  final DateTime? checklistLastModified;

  Asset({
    required this.id,
    required this.buildingId,
    required this.taskName,
    this.nickname,
    this.assetRegisterItems,
    this.tooltipText,
    this.tooltipUrls,
    this.lastCompleted,
    this.dueDate,
    this.frequency,
    this.colour,
    this.location,
    this.floor,
    this.yellowDate,
    this.assetLastModified,
    this.checklistLastModified,
  });

  /// Display name for the asset — nickname if available, otherwise task name.
  String get displayName {
    if (nickname != null && nickname!.isNotEmpty) {
      return '$taskName — $nickname';
    }
    return taskName;
  }

  /// Whether an inspection is overdue.
  bool get isOverdue {
    if (dueDate == null) return false;
    return dueDate!.isBefore(DateTime.now());
  }

  /// Parse from a v2 Bubble JSON object (app_fetch_all_assets / app_fetch_asset_single).
  factory Asset.fromJson(Map<String, dynamic> json) {
    return Asset(
      id: json['assetId'] as String? ?? '',
      buildingId: json['buildingId'] as String? ?? '',
      taskName: json['taskname'] as String? ?? 'Unnamed',
      nickname: _emptyToNull(json['assetnickname'] as String?),
      assetRegisterItems: _blobToString(json['assetregisteritems']),
      tooltipText: _emptyToNull(json['tooltiptext'] as String?),
      tooltipUrls: _blobToString(json['tooltipurls']),
      lastCompleted: _parseDate(json['lastcompleted']),
      dueDate: _parseDate(json['duedate']),
      frequency: _emptyToNull(json['frequency'] as String?),
      colour: AssetColour.fromString(json['colour'] as String?),
      location: _emptyToNull(json['location'] as String?),
      floor: _emptyToNull(json['floor'] as String?),
      yellowDate: _parseDate(json['yellowdate']),
      assetLastModified: _parseDate(json['assetlastmodified']),
      checklistLastModified: _parseDate(json['checklistlastmodified']),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static String? _emptyToNull(String? value) {
    if (value == null || value.isEmpty) return null;
    return value;
  }

  /// Normalise a blob field (`assetregisteritems` / `tooltipurls`) that the v2
  /// API may send either as an already-stringified JSON value or as a real
  /// List/Map. Returns a JSON string the `*List` getters can decode, or null
  /// when empty.
  static String? _blobToString(dynamic value) {
    if (value is String) return value.isEmpty ? null : value;
    if (value is List) return value.isEmpty ? null : jsonEncode(value);
    if (value is Map) return value.isEmpty ? null : jsonEncode(value);
    return null;
  }

  /// Whether the asset has placement info (floor and/or location) to surface.
  /// Drives the Floor / Location lines on the list and detail cards.
  bool get hasPlacementInfo => floor != null || location != null;

  /// Whether the asset has any schedule info (last completed / frequency /
  /// next due) to surface.
  bool get hasScheduleInfo =>
      lastCompleted != null || frequency != null || dueDate != null;

  /// Whether the asset has any tooltip help to surface (explanatory text
  /// and/or source links). Drives the info icon's visibility.
  bool get hasTooltipInfo =>
      (tooltipText?.isNotEmpty ?? false) || tooltipUrlList.isNotEmpty;

  /// Parse the raw v2 `tooltipurls` string into a list of URLs.
  ///
  /// The field is stored as comma-separated JSON objects without array
  /// brackets, e.g. `{"tooltipurl": "..."},{"tooltipurl": "..."}`. Wrap in
  /// `[...]` before decoding.
  List<String> get tooltipUrlList {
    final raw = tooltipUrls;
    if (raw == null || raw.isEmpty) return const [];
    try {
      final wrapped = raw.trim().startsWith('[') ? raw : '[$raw]';
      final decoded = jsonDecode(wrapped);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((m) => m['tooltipurl'])
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Parse the raw v2 `assetregisteritems` string into structured items.
  ///
  /// Same format quirk as [tooltipUrlList]: comma-separated JSON objects
  /// without array brackets, e.g. `{"registeritemref": "..."},{...}`.
  List<RegisterItem> get registerItems {
    final raw = assetRegisterItems;
    if (raw == null || raw.isEmpty) return const [];
    try {
      final wrapped = raw.trim().startsWith('[') ? raw : '[$raw]';
      final decoded = jsonDecode(wrapped);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(RegisterItem.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

}
