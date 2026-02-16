import 'response_struct.dart';

class UserStruct {
  final String status;
  final ResponseStruct? response;
  final int statusCode;
  final String? reason;
  final String? message;

  UserStruct({
    required this.status,
    this.response,
    this.statusCode = 200,
    this.reason,
    this.message,
  });

  factory UserStruct.fromJson(Map<String, dynamic> json) {
    return UserStruct(
      status: json['status'] as String? ?? '',
      response: json['response'] != null
          ? ResponseStruct.fromJson(json['response'] as Map<String, dynamic>)
          : null,
      statusCode: json['statusCode'] as int? ?? 200,
      reason: json['reason'] as String?,
      message: json['message'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'status': status,
        'response': response?.toJson(),
        'statusCode': statusCode,
        'reason': reason,
        'message': message,
      };

  bool get isSuccess => status == 'success';
}
