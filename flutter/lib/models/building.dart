class Building {
  final String id;
  final String name;
  final int assetCount;

  Building({
    required this.id,
    required this.name,
    this.assetCount = 0,
  });

  /// Parse from a Bubble JSON object.
  ///
  /// Field names are best-guess from Bubble conventions — adjust once
  /// a real response is observed.
  factory Building.fromJson(Map<String, dynamic> json) {
    final assets = json['List of assets'];
    final assetCount = assets is List ? assets.length : 0;

    return Building(
      id: json['id'] as String? ?? json['_id'] as String? ?? '',
      name: json['name'] as String? ?? json['Name'] as String? ?? 'Unnamed',
      assetCount: assetCount,
    );
  }

  Map<String, dynamic> toJson() => {
        '_id': id,
        'Name': name,
      };
}
