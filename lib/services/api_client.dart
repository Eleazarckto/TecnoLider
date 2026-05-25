import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
 
/// Centralized HTTP client for the YJ Delivery backend.
/// Handles base URL detection, JWT storage, and error parsing.
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();
 
  /// Determines the right base URL depending on the platform.
  /// You can override this in production by setting [overrideBaseUrl].
  static String? overrideBaseUrl;
 
  /// URL del servidor XAMPP donde corre el API PHP.
  /// Cambia esta IP si tu PC tiene otra dirección en la red local.
  /// Para emulador Android usa la IP real de tu PC (no 'localhost').
  // ============ BASE URL ============
  // URL de PRODUCCION - apunta al hosting real
  static const String _serverUrl = 'https://sistemasceccato.com/Yjdelivery/yj_api';
 
  static String get baseUrl {
    if (overrideBaseUrl != null) return overrideBaseUrl!;
    return _serverUrl;
  }
 
  String? _token;
  Map<String, dynamic>? _currentUser;
 
  String? get token => _token;
  Map<String, dynamic>? get currentUser => _currentUser;
  bool get isAuthenticated => _token != null;
 
  static const _tokenKey = 'yj_auth_token';
  static const _userKey = 'yj_auth_user';
 
  /// Load token & user from disk on app startup.
  Future<void> loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_tokenKey);
    final userJson = prefs.getString(_userKey);
    if (userJson != null) {
      try {
        _currentUser = jsonDecode(userJson) as Map<String, dynamic>;
      } catch (e) {
        // Storage corrupto - limpiar y continuar sin sesion
        debugPrint('ApiClient: storage de usuario corrupto, limpiando: $e');
        _currentUser = null;
        _token = null;
        await prefs.remove(_tokenKey);
        await prefs.remove(_userKey);
      }
    }
  }
 
  Future<void> _saveToStorage() async {
    final prefs = await SharedPreferences.getInstance();
    if (_token != null) {
      await prefs.setString(_tokenKey, _token!);
    } else {
      await prefs.remove(_tokenKey);
    }
    if (_currentUser != null) {
      await prefs.setString(_userKey, jsonEncode(_currentUser));
    } else {
      await prefs.remove(_userKey);
    }
  }
 
  Map<String, String> get _headers {
    final h = <String, String>{'Content-Type': 'application/json'};
    if (_token != null) h['Authorization'] = 'Bearer $_token';
    return h;
  }
 
  /// Builds the full URL for a path. Strips a leading "/api" if present
  /// so older code (using /api/auth/login etc.) still works against
  /// the XAMPP backend whose base is .../yj_api/.
  Uri _uri(String path) {
    if (path.startsWith('/api/')) {
      path = path.substring(4); // remove leading "/api"
    } else if (path == '/api') {
      path = '/';
    }
    return Uri.parse('$baseUrl$path');
  }
 
  Future<dynamic> _handle(http.Response r) async {
    dynamic body;
    if (r.body.isNotEmpty) {
      try {
        body = jsonDecode(r.body);
      } catch (e) {
        // Respuesta no es JSON valido (ej. error HTML de Apache)
        body = null;
      }
    }

    if (r.statusCode >= 200 && r.statusCode < 300) {
      return body;
    }
    // Auto-logout on 401
    if (r.statusCode == 401) {
      await logout();
    }
    // Construir mensaje de error util
    String message;
    if (body is Map && body['error'] is String) {
      message = body['error'] as String;
    } else if (r.statusCode == 0) {
      message = 'Sin respuesta del servidor';
    } else if (r.statusCode >= 500) {
      message = 'Error del servidor (${r.statusCode})';
    } else if (r.statusCode == 404) {
      message = 'Recurso no encontrado';
    } else if (r.statusCode == 403) {
      message = 'No tienes permisos para esto';
    } else {
      message = 'Error ${r.statusCode}';
    }
    throw ApiException(message, statusCode: r.statusCode);
  }

  /// Convierte excepciones de red en mensajes amigables para el usuario.
  ApiException _networkError(Object error) {
    if (error is TimeoutException) {
      return ApiException('Tardó demasiado, verifica tu conexión',
          statusCode: 0);
    }
    if (error is SocketException) {
      return ApiException(
          'Sin conexión al servidor. Verifica tu red.',
          statusCode: 0);
    }
    if (error is HandshakeException || error is HttpException) {
      return ApiException('Error de conexión: ${error.toString()}',
          statusCode: 0);
    }
    if (error is FormatException) {
      return ApiException('Respuesta inesperada del servidor',
          statusCode: 0);
    }
    return ApiException(error.toString(), statusCode: 0);
  }
 
  // ============ AUTH ============
  Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final r = await http
          .post(_uri('/auth/login'),
              headers: _headers,
              body: jsonEncode({'email': email, 'password': password}))
          .timeout(const Duration(seconds: 15));
      final data = await _handle(r) as Map<String, dynamic>;
      _token = data['token'] as String;
      _currentUser = data['user'] as Map<String, dynamic>;
      await _saveToStorage();
      return _currentUser!;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw _networkError(e);
    }
  }
 
  Future<void> logout() async {
    _token = null;
    _currentUser = null;
    await _saveToStorage();
  }
 
  // ============ Generic verbs ============
  /// GET con reintentos automaticos en errores de red.
  /// Las lecturas son seguras de reintentar (idempotentes).
  Future<dynamic> get(String path) async {
    Object? lastError;
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        final r = await http
            .get(_uri(path), headers: _headers)
            .timeout(const Duration(seconds: 15));
        return _handle(r);
      } on ApiException {
        rethrow; // errores del servidor no se reintentan
      } catch (e) {
        lastError = e;
        // Solo reintentar errores de red (timeout, socket, etc)
        if (attempt < 3) {
          await Future.delayed(Duration(milliseconds: 500 * attempt));
        }
      }
    }
    throw _networkError(lastError!);
  }
 
  Future<dynamic> post(String path, [Map<String, dynamic>? body]) async {
    try {
      final r = await http
          .post(_uri(path),
              headers: _headers, body: body != null ? jsonEncode(body) : null)
          .timeout(const Duration(seconds: 15));
      return _handle(r);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw _networkError(e);
    }
  }
 
  Future<dynamic> put(String path, [Map<String, dynamic>? body]) async {
    try {
      final r = await http
          .put(_uri(path),
              headers: _headers, body: body != null ? jsonEncode(body) : null)
          .timeout(const Duration(seconds: 15));
      return _handle(r);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw _networkError(e);
    }
  }
 
  Future<dynamic> patch(String path, [Map<String, dynamic>? body]) async {
    try {
      final r = await http
          .patch(_uri(path),
              headers: _headers, body: body != null ? jsonEncode(body) : null)
          .timeout(const Duration(seconds: 15));
      return _handle(r);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw _networkError(e);
    }
  }
 
  Future<void> delete(String path) async {
    try {
      final r = await http
          .delete(_uri(path), headers: _headers)
          .timeout(const Duration(seconds: 15));
      await _handle(r);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw _networkError(e);
    }
  }
}
 
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, {this.statusCode});
  @override
  String toString() => message;
}