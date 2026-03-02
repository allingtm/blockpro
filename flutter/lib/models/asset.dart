class Asset {
  final String id;
  final String name;
  final DateTime? nextInspection;
  final DateTime? previousInspection;
  final int? intervalDays;

  Asset({
    required this.id,
    required this.name,
    this.nextInspection,
    this.previousInspection,
    this.intervalDays,
  });

  /// Parse from a Bubble JSON object.
  ///
  /// Field names are best-guess from Bubble conventions — adjust once
  /// a real response is observed.
  factory Asset.fromJson(Map<String, dynamic> json) {
    return Asset(
      id: json['assetId'] as String? ?? json['id'] as String? ?? '',
      name: json['assetName'] as String? ?? json['name'] as String? ?? 'Unnamed',
      nextInspection: _parseDate(json['date_of_next_inspection'] ?? json['Date of next inspection']),
      previousInspection: _parseDate(json['date_of_previous_inspection'] ?? json['Date of previous inspection']),
      intervalDays: json['interval_number_of_days'] as int? ?? json['Interval (number of days)'] as int?,
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  /// Whether an inspection is overdue.
  bool get isOverdue {
    if (nextInspection == null) return false;
    return nextInspection!.isBefore(DateTime.now());
  }
}
