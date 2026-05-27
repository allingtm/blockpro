import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../core/config/api_config.dart';
import '../providers/auth_provider.dart';
import '../providers/connectivity_provider.dart';
import '../services/connectivity_service.dart';
import 'auth_repository.dart';

String _tokenPreview(String token) =>
    token.length < 12 ? token : '${token.substring(0, 8)}...(${token.length})';

final apiRepositoryProvider = Provider<ApiRepository>((ref) {
  final authRepo = ref.watch(authRepositoryProvider);
  final connectivityService = ref.watch(connectivityServiceProvider);
  return ApiRepository(authRepo, connectivityService);
});

class ApiRepository {
  final AuthRepository _authRepo;
  final ConnectivityService _connectivityService;

  ApiRepository(this._authRepo, this._connectivityService);

  /// Make an authenticated GET request to a Bubble API endpoint.
  Future<Map<String, dynamic>> authenticatedGet(String endpoint,
      {Map<String, String>? queryParams}) async {
    final token = _authRepo.authenticationToken;
    if (token == null || token.isEmpty) {
      debugPrint('AUTH ERROR: no token when calling $endpoint');
      throw Exception('Not authenticated');
    }

    final uri = Uri.parse('${ApiConfig.baseUrl}$endpoint')
        .replace(queryParameters: queryParams);
    debugPrint('── GET $endpoint (token: ${_tokenPreview(token)}) ──');

    try {
      final response = await http.get(uri, headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      });

      if (response.statusCode != 200) {
        debugPrint(
            'GET $endpoint → ${response.statusCode}: ${response.body}');
        throw Exception('API error: ${response.statusCode}');
      }

      _connectivityService.reportApiSuccess();
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on SocketException {
      _connectivityService.reportApiFailure();
      rethrow;
    } on http.ClientException {
      _connectivityService.reportApiFailure();
      rethrow;
    }
  }

  /// Make an authenticated GET request that may return any JSON type
  /// (array or object). Use this for Bubble endpoints that return a raw list.
  Future<dynamic> authenticatedGetRaw(String endpoint,
      {Map<String, String>? queryParams}) async {
    final token = _authRepo.authenticationToken;
    if (token == null || token.isEmpty) {
      debugPrint('AUTH ERROR: no token when calling $endpoint');
      throw Exception('Not authenticated');
    }

    final uri = Uri.parse('${ApiConfig.baseUrl}$endpoint')
        .replace(queryParameters: queryParams);
    debugPrint('── GET $endpoint (token: ${_tokenPreview(token)}) ──');

    try {
      final response = await http.get(uri, headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      });

      if (response.statusCode != 200) {
        debugPrint(
            'GET $endpoint → ${response.statusCode}: ${response.body}');
        throw Exception('API error: ${response.statusCode}');
      }

      _connectivityService.reportApiSuccess();
      return jsonDecode(response.body);
    } on SocketException {
      _connectivityService.reportApiFailure();
      rethrow;
    } on http.ClientException {
      _connectivityService.reportApiFailure();
      rethrow;
    }
  }

  /// Make an authenticated POST request to a Bubble API endpoint.
  Future<Map<String, dynamic>> authenticatedPost(String endpoint,
      {Map<String, dynamic>? body}) async {
    final token = _authRepo.authenticationToken;
    if (token == null || token.isEmpty) {
      debugPrint('AUTH ERROR: no token when calling $endpoint');
      throw Exception('Not authenticated');
    }
    debugPrint('── POST $endpoint (token: ${_tokenPreview(token)}) ──');

    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}$endpoint'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: body != null ? jsonEncode(body) : null,
      );

      if (response.statusCode != 200) {
        debugPrint(
            'POST $endpoint → ${response.statusCode}: ${response.body}');
        throw Exception('API error: ${response.statusCode}');
      }

      _connectivityService.reportApiSuccess();
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on SocketException {
      _connectivityService.reportApiFailure();
      rethrow;
    } on http.ClientException {
      _connectivityService.reportApiFailure();
      rethrow;
    }
  }
}
