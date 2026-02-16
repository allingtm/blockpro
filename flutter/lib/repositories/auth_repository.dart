import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/config/api_config.dart';
import '../models/user_struct.dart';
import '../auth/bubble_auth_user.dart';
import '../utils/string_utils.dart';

class AuthRepository {
  // ── In-memory auth state ──────────────────────────────
  String? _authenticationToken;
  String? _refreshToken;
  DateTime? _tokenExpiration;
  String? _uid;
  UserStruct? _userData;

  // ── Reactive auth stream ──────────────────────────────
  final _authUserSubject = BehaviorSubject<BubbleAuthUser>.seeded(
    BubbleAuthUser(loggedIn: false),
  );

  Stream<BubbleAuthUser> get authUserStream => _authUserSubject.stream;
  BubbleAuthUser get currentAuthUser => _authUserSubject.value;

  // ── Public accessors ──────────────────────────────────
  String? get authenticationToken => _authenticationToken;
  String? get refreshToken => _refreshToken;
  DateTime? get tokenExpiration => _tokenExpiration;
  String? get uid => _uid;
  UserStruct? get userData => _userData;
  bool get isAuthenticated => currentAuthUser.loggedIn;

  // ── SharedPreferences keys ────────────────────────────
  static const _keyToken = '_auth_authentication_token_';
  static const _keyRefreshToken = '_auth_refresh_token_';
  static const _keyTokenExpiration = '_auth_token_expiration_';
  static const _keyUid = '_auth_uid_';
  static const _keyUserData = '_auth_user_data_';

  // ── Initialization (called on app startup) ────────────
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();

    _authenticationToken = prefs.getString(_keyToken);
    _refreshToken = prefs.getString(_keyRefreshToken);
    _uid = prefs.getString(_keyUid);

    final expirationMs = prefs.getInt(_keyTokenExpiration);
    if (expirationMs != null) {
      _tokenExpiration = DateTime.fromMillisecondsSinceEpoch(expirationMs);
    }

    final userDataJson = prefs.getString(_keyUserData);
    if (userDataJson != null) {
      _userData = UserStruct.fromJson(jsonDecode(userDataJson));
    }

    // Check if token exists and is not expired
    final tokenExists = _authenticationToken != null;
    final tokenExpired = _tokenExpiration != null &&
        _tokenExpiration!.isBefore(DateTime.now());

    if (tokenExists && !tokenExpired) {
      _authUserSubject.add(BubbleAuthUser(
        loggedIn: true,
        uid: _uid,
        userData: _userData,
      ));
    } else {
      // Token expired or missing — clear state
      await _clearAuthState();
    }
  }

  // ── Login ─────────────────────────────────────────────
  Future<UserStruct> login({
    required String email,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}applogin'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': escapeStringForJson(email),
        'password': escapeStringForJson(password),
      }),
    );

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final userStruct = UserStruct.fromJson(data);

    if (!userStruct.isSuccess || userStruct.response == null) {
      throw Exception(userStruct.message ??
          'Failed to login. Please check your email and password.');
    }

    // Calculate token expiry
    final expiresInSeconds = userStruct.response!.expires;
    final expiryTime =
        DateTime.now().add(Duration(seconds: expiresInSeconds));

    // Store auth state
    _authenticationToken = userStruct.response!.token;
    _tokenExpiration = expiryTime;
    _uid = userStruct.response!.userId;
    _userData = userStruct;

    // Persist to SharedPreferences
    await _persistAuthData();

    // Emit new auth state
    _authUserSubject.add(BubbleAuthUser(
      loggedIn: true,
      uid: _uid,
      userData: _userData,
    ));

    return userStruct;
  }

  // ── Logout ────────────────────────────────────────────
  Future<void> signOut() async {
    await _clearAuthState();
  }

  // ── Persistence ───────────────────────────────────────
  Future<void> _persistAuthData() async {
    final prefs = await SharedPreferences.getInstance();

    if (_authenticationToken != null) {
      await prefs.setString(_keyToken, _authenticationToken!);
    } else {
      await prefs.remove(_keyToken);
    }

    if (_refreshToken != null) {
      await prefs.setString(_keyRefreshToken, _refreshToken!);
    } else {
      await prefs.remove(_keyRefreshToken);
    }

    if (_tokenExpiration != null) {
      await prefs.setInt(
          _keyTokenExpiration, _tokenExpiration!.millisecondsSinceEpoch);
    } else {
      await prefs.remove(_keyTokenExpiration);
    }

    if (_uid != null) {
      await prefs.setString(_keyUid, _uid!);
    } else {
      await prefs.remove(_keyUid);
    }

    if (_userData != null) {
      await prefs.setString(_keyUserData, jsonEncode(_userData!.toJson()));
    } else {
      await prefs.remove(_keyUserData);
    }
  }

  Future<void> _clearAuthState() async {
    _authenticationToken = null;
    _refreshToken = null;
    _tokenExpiration = null;
    _uid = null;
    _userData = null;

    await _persistAuthData();

    _authUserSubject.add(BubbleAuthUser(loggedIn: false));
  }

  /// Check if the current token is expired.
  bool get isTokenExpired {
    if (_tokenExpiration == null) return true;
    return _tokenExpiration!.isBefore(DateTime.now());
  }
}
