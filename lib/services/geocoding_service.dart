import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;
import 'package:http/http.dart' as http;

/// Resultado de una búsqueda de dirección
class GeocodingResult {
  final String displayName;
  final double latitude;
  final double longitude;
  final String? type;
  final String? category;

  GeocodingResult({
    required this.displayName,
    required this.latitude,
    required this.longitude,
    this.type,
    this.category,
  });

  factory GeocodingResult.fromNominatim(Map<String, dynamic> j) =>
      GeocodingResult(
        displayName: j['display_name']?.toString() ?? '',
        latitude: double.tryParse(j['lat']?.toString() ?? '0') ?? 0,
        longitude: double.tryParse(j['lon']?.toString() ?? '0') ?? 0,
        type: j['type']?.toString(),
        category: j['class']?.toString(),
      );

  factory GeocodingResult.fromGoogle(Map<String, dynamic> j) {
    final loc = (j['geometry']?['location']) as Map<String, dynamic>?;
    return GeocodingResult(
      displayName: j['formatted_address']?.toString() ?? '',
      latitude: (loc?['lat'] as num?)?.toDouble() ?? 0,
      longitude: (loc?['lng'] as num?)?.toDouble() ?? 0,
      type: (j['types'] is List && (j['types'] as List).isNotEmpty)
          ? (j['types'] as List).first.toString()
          : null,
      category: 'google',
    );
  }

  String get shortName {
    final parts = displayName.split(',').map((s) => s.trim()).toList();
    if (parts.length <= 2) return displayName;
    return '${parts[0]}, ${parts[1]}';
  }
}

enum GeocodingState { idle, searching, results, empty, error }

class GeocodingResponse {
  final GeocodingState state;
  final List<GeocodingResult> results;
  final String? errorMessage;

  GeocodingResponse({
    required this.state,
    this.results = const [],
    this.errorMessage,
  });
}

/// Servicio de búsqueda de direcciones.
///
/// Usa Google Geocoding/Places si hay API key configurada (mejor cobertura).
/// Si no hay key, usa Nominatim (OpenStreetMap) gratis pero con cobertura
/// limitada en Venezuela.
class GeocodingService {
  GeocodingService._();
  static final GeocodingService instance = GeocodingService._();

  static const String _nominatimUrl = 'https://nominatim.openstreetmap.org';
  static const String _googleUrl =
      'https://maps.googleapis.com/maps/api/geocode/json';
  static const Duration _minDelay = Duration(milliseconds: 1100);

  String _googleApiKey = '';
  DateTime _lastRequest = DateTime(2000);
  Timer? _debounceTimer;

  /// Configurar la API key de Google. Llamar al iniciar sesion.
  void setGoogleApiKey(String key) {
    _googleApiKey = key.trim();
  }

  bool get hasGoogleKey => _googleApiKey.length > 10;

  /// Buscar direcciones. Usa Google si esta configurado, sino Nominatim.
  Future<GeocodingResponse> search(
    String query, {
    String? preferCountryCode = 've',
    int limit = 10,
  }) async {
    if (query.trim().length < 2) {
      return GeocodingResponse(state: GeocodingState.idle);
    }

    if (hasGoogleKey) {
      final result = await _searchGoogle(query, preferCountryCode, limit);
      // Si Google no devolvio nada o fallo, intentar con Nominatim como fallback
      if (result.state == GeocodingState.empty ||
          result.state == GeocodingState.error) {
        final fallback = await _searchNominatim(query, preferCountryCode, limit);
        // Si el fallback encuentra algo, usar ese resultado
        if (fallback.state == GeocodingState.results) return fallback;
      }
      return result;
    }
    return _searchNominatim(query, preferCountryCode, limit);
  }

  /// Geocoding inverso (lat/lng -> direccion legible)
  Future<String?> reverseGeocode(double lat, double lng) async {
    if (hasGoogleKey) {
      final result = await _reverseGoogle(lat, lng);
      if (result != null) return result;
    }
    return _reverseNominatim(lat, lng);
  }

  // ============ GOOGLE ============
  Future<GeocodingResponse> _searchGoogle(
      String query, String? countryCode, int limit) async {
    try {
      final params = {
        'address': query,
        'key': _googleApiKey,
        'language': 'es',
      };
      if (countryCode != null) {
        params['components'] = 'country:$countryCode';
      }

      final uri = Uri.parse(_googleUrl).replace(queryParameters: params);
      final response = await http
          .get(uri)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return GeocodingResponse(
          state: GeocodingState.error,
          errorMessage: 'Google respondió ${response.statusCode}',
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final status = data['status']?.toString() ?? '';

      if (status == 'ZERO_RESULTS') {
        return GeocodingResponse(state: GeocodingState.empty);
      }
      if (status != 'OK') {
        return GeocodingResponse(
          state: GeocodingState.error,
          errorMessage: 'Google: $status',
        );
      }

      final list = data['results'] as List<dynamic>? ?? [];
      final results = list
          .take(limit)
          .map((j) => GeocodingResult.fromGoogle(j as Map<String, dynamic>))
          .where((r) => r.latitude != 0 && r.longitude != 0)
          .toList();

      if (results.isEmpty) {
        return GeocodingResponse(state: GeocodingState.empty);
      }
      return GeocodingResponse(
          state: GeocodingState.results, results: results);
    } on TimeoutException {
      return GeocodingResponse(
          state: GeocodingState.error,
          errorMessage: 'Google tardó demasiado');
    } on SocketException {
      return GeocodingResponse(
          state: GeocodingState.error,
          errorMessage: 'Sin conexión');
    } catch (e) {
      return GeocodingResponse(
          state: GeocodingState.error,
          errorMessage: 'Error: $e');
    }
  }

  Future<String?> _reverseGoogle(double lat, double lng) async {
    try {
      final uri = Uri.parse(_googleUrl).replace(queryParameters: {
        'latlng': '$lat,$lng',
        'key': _googleApiKey,
        'language': 'es',
      });
      final response = await http
          .get(uri)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final list = data['results'] as List<dynamic>? ?? [];
      if (list.isEmpty) return null;
      return list.first['formatted_address']?.toString();
    } catch (_) {
      return null;
    }
  }

  // ============ NOMINATIM ============
  Future<GeocodingResponse> _searchNominatim(
      String query, String? preferCountryCode, int limit) async {
    await _waitForRateLimit();

    try {
      final params = <String, String>{
        'q': query,
        'format': 'json',
        'addressdetails': '1',
        'limit': limit.toString(),
        'accept-language': 'es',
        'dedupe': '1',
      };

      if (preferCountryCode == 've') {
        params['countrycodes'] = 've';
        params['viewbox'] = '-73.378,12.199,-59.802,0.626';
        params['bounded'] = '0';
      }

      final uri =
          Uri.parse('$_nominatimUrl/search').replace(queryParameters: params);

      final response = await http.get(
        uri,
        headers: {'User-Agent': 'YJ Delivery App/1.0'},
      ).timeout(const Duration(seconds: 15));

      _lastRequest = DateTime.now();

      if (response.statusCode != 200) {
        return GeocodingResponse(
          state: GeocodingState.error,
          errorMessage: 'El servidor respondió ${response.statusCode}',
        );
      }

      final List<dynamic> data = jsonDecode(response.body);
      var results = data
          .map((j) => GeocodingResult.fromNominatim(j as Map<String, dynamic>))
          .where((r) => r.latitude != 0 && r.longitude != 0)
          .toList();

      // Si VE no devolvio, intentar sin restriccion
      if (results.isEmpty && preferCountryCode == 've') {
        await _waitForRateLimit();
        final fallbackParams = Map<String, String>.from(params);
        fallbackParams.remove('countrycodes');
        final fallbackUri = Uri.parse('$_nominatimUrl/search')
            .replace(queryParameters: fallbackParams);
        final fallbackResponse = await http.get(
          fallbackUri,
          headers: {'User-Agent': 'YJ Delivery App/1.0'},
        ).timeout(const Duration(seconds: 15));
        _lastRequest = DateTime.now();
        if (fallbackResponse.statusCode == 200) {
          final List<dynamic> fallbackData =
              jsonDecode(fallbackResponse.body);
          results = fallbackData
              .map((j) => GeocodingResult.fromNominatim(j as Map<String, dynamic>))
              .where((r) => r.latitude != 0 && r.longitude != 0)
              .toList();
        }
      }

      if (results.isEmpty) {
        return GeocodingResponse(state: GeocodingState.empty);
      }
      return GeocodingResponse(
          state: GeocodingState.results, results: results);
    } on TimeoutException {
      return GeocodingResponse(
        state: GeocodingState.error,
        errorMessage: 'La búsqueda tardó demasiado. Revisa tu conexión.',
      );
    } on SocketException {
      return GeocodingResponse(
        state: GeocodingState.error,
        errorMessage: 'Sin conexión a internet',
      );
    } catch (e) {
      return GeocodingResponse(
        state: GeocodingState.error,
        errorMessage: 'Error inesperado: $e',
      );
    }
  }

  Future<String?> _reverseNominatim(double lat, double lng) async {
    await _waitForRateLimit();
    try {
      final uri = Uri.parse('$_nominatimUrl/reverse').replace(queryParameters: {
        'lat': lat.toString(),
        'lon': lng.toString(),
        'format': 'json',
        'accept-language': 'es',
      });
      final response = await http.get(
        uri,
        headers: {'User-Agent': 'YJ Delivery App/1.0'},
      ).timeout(const Duration(seconds: 10));
      _lastRequest = DateTime.now();
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['display_name']?.toString();
    } catch (_) {
      return null;
    }
  }

  Future<void> _waitForRateLimit() async {
    final elapsed = DateTime.now().difference(_lastRequest);
    if (elapsed < _minDelay) {
      await Future.delayed(_minDelay - elapsed);
    }
  }

  /// Busqueda con debounce de 500ms - ideal para usar mientras el usuario tipea.
  /// Se cancela automaticamente la busqueda anterior si llega otra antes del delay.
  void searchWithDebounce(
    String query,
    void Function(GeocodingResponse) onResult, {
    String? preferCountryCode = 've',
    int limit = 10,
    Duration debounce = const Duration(milliseconds: 500),
  }) {
    _debounceTimer?.cancel();

    // Si es muy corto, devolver idle inmediatamente
    if (query.trim().length < 2) {
      onResult(GeocodingResponse(state: GeocodingState.idle));
      return;
    }

    // Mostrar "buscando" inmediatamente
    onResult(GeocodingResponse(state: GeocodingState.searching));

    _debounceTimer = Timer(debounce, () async {
      final result = await search(
        query,
        preferCountryCode: preferCountryCode,
        limit: limit,
      );
      onResult(result);
    });
  }

  /// Cancela cualquier debounce activo (para limpiar al cerrar pantallas)
  void cancelDebounce() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }

  /// Alias para compatibilidad
  void dispose() => cancelDebounce();
}
