/// One physical item on an asset's register (e.g. a call point or wallbox).
///
/// Maps to the objects inside the asset's `assetregisteritems` field —
/// a string of comma-separated JSON objects without array brackets (see
/// `Asset.registerItems` for the parsing quirk).
class RegisterItem {
  final String? ref;
  final String? floor;
  final String? location;

  const RegisterItem({this.ref, this.floor, this.location});

  factory RegisterItem.fromJson(Map<String, dynamic> json) {
    return RegisterItem(
      ref: _emptyToNull(json['registeritemref'] as String?),
      floor: _emptyToNull(json['registeritemfloor'] as String?),
      location: _emptyToNull(json['registeritemlocation'] as String?),
    );
  }

  Map<String, dynamic> toJson() => {
        if (ref != null) 'registeritemref': ref,
        if (floor != null) 'registeritemfloor': floor,
        if (location != null) 'registeritemlocation': location,
      };

  /// Serialize for the `app_completed-inspection` submission payload, using the
  /// snake_case wire keys. Distinct from [toJson] (which keeps the asset's
  /// inbound `assetregisteritems` key names for local persistence + parsing).
  Map<String, dynamic> toApiJson() => {
        if (ref != null) 'register_item_ref': ref,
        if (floor != null) 'register_item_floor': floor,
        if (location != null) 'register_item_location': location,
      };

  /// Display label, e.g. "Wallbox1 — 1st, Landing".
  String get displayLabel {
    final detail = [floor, location].whereType<String>().join(', ');
    if (ref == null) return detail;
    return detail.isEmpty ? ref! : '$ref — $detail';
  }

  static String? _emptyToNull(String? value) {
    if (value == null || value.isEmpty) return null;
    return value;
  }
}
