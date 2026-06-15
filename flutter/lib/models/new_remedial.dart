import 'register_item.dart';

/// A remedial item the inspector is raising against a question in the
/// current inspection (as opposed to [Remedial], which is a read-only item
/// from a *prior* inspection shipped down with the checklist).
///
/// Serialized with the API's lowercase field names so the same JSON shape
/// serves the draft column, the outbox entry, and the
/// `app_completed-inspection` payload.
class NewRemedial {
  final String title;
  final String location;
  final String description;

  /// 'Low' | 'High' — matches the documented `remedialpriority` values.
  final String priority;

  /// Register items this remedial relates to, frozen at selection so a
  /// queued completion stays self-contained across cache wipes.
  final List<RegisterItem> registerItems;

  const NewRemedial({
    this.title = '',
    this.location = '',
    this.description = '',
    this.priority = 'Low',
    this.registerItems = const [],
  });

  /// A remedial with no title is treated as "not raised" — it is never
  /// persisted or submitted.
  bool get isBlank => title.trim().isEmpty;

  Map<String, dynamic> toJson() => {
        'remedialname': title.trim(),
        if (location.trim().isNotEmpty) 'remediallocation': location.trim(),
        if (description.trim().isNotEmpty) 'remedialdesc': description.trim(),
        'remedialpriority': priority,
        if (registerItems.isNotEmpty)
          'registeritems': registerItems.map((r) => r.toJson()).toList(),
      };

  factory NewRemedial.fromJson(Map<String, dynamic> json) {
    final itemsRaw = json['registeritems'];
    final items = itemsRaw is List
        ? itemsRaw
            .whereType<Map<String, dynamic>>()
            .map(RegisterItem.fromJson)
            .toList()
        : <RegisterItem>[];
    return NewRemedial(
      title: json['remedialname'] as String? ?? '',
      location: json['remediallocation'] as String? ?? '',
      description: json['remedialdesc'] as String? ?? '',
      priority: json['remedialpriority'] as String? ?? 'Low',
      registerItems: items,
    );
  }

  NewRemedial copyWith({
    String? title,
    String? location,
    String? description,
    String? priority,
    List<RegisterItem>? registerItems,
  }) {
    return NewRemedial(
      title: title ?? this.title,
      location: location ?? this.location,
      description: description ?? this.description,
      priority: priority ?? this.priority,
      registerItems: registerItems ?? this.registerItems,
    );
  }
}
