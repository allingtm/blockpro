import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/config/api_config.dart';
import 'auth_repository.dart';

class ApiRepository {
  final AuthRepository _authRepo;

  ApiRepository(this._authRepo);

  /// Make an authenticated GET request to a Bubble API endpoint.
  Future<Map<String, dynamic>> authenticatedGet(String endpoint,
      {Map<String, String>? queryParams}) async {
    final token = _authRepo.authenticationToken;
    if (token == null) throw Exception('Not authenticated');

    final uri = Uri.parse('${ApiConfig.baseUrl}$endpoint')
        .replace(queryParameters: queryParams);

    final response = await http.get(uri, headers: {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    });

    if (response.statusCode != 200) {
      throw Exception('API error: ${response.statusCode}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Make an authenticated POST request to a Bubble API endpoint.
  Future<Map<String, dynamic>> authenticatedPost(String endpoint,
      {Map<String, dynamic>? body}) async {
    final token = _authRepo.authenticationToken;
    if (token == null) throw Exception('Not authenticated');

    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}$endpoint'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: body != null ? jsonEncode(body) : null,
    );

    if (response.statusCode != 200) {
      throw Exception('API error: ${response.statusCode}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}
