class ResponseStruct {
  final String token;
  final String userId;
  final int expires;
  final String? buildings;

  ResponseStruct({
    required this.token,
    required this.userId,
    required this.expires,
    this.buildings,
  });

  factory ResponseStruct.fromJson(Map<String, dynamic> json) {
    return ResponseStruct(
      token: json['token'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      expires: json['expires'] as int? ?? 0,
      buildings: json['buildings'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'token': token,
        'user_id': userId,
        'expires': expires,
        'buildings': buildings,
      };
}
