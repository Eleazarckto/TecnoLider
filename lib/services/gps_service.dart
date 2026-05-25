import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'api_client.dart';
import 'permissions.dart';

/// Servicio de GPS y Heartbeat — versión robusta.
///
/// CLAVE: El heartbeat ("estar en línea") es INDEPENDIENTE del GPS.
/// Un motorizado está "en línea" mientras tenga la app abierta y sesión
/// activa, aunque su GPS no tenga señal o esté desactivado.
///
/// - Heartbeat cada 5 segundos (mantiene "en línea") — SIEMPRE
/// - Reporte de ubicación cada 1 segundo — solo si hay señal GPS
class GpsService extends ChangeNotifier {
  GpsService._();
  static final GpsService instance = GpsService._();

  final ApiClient _api = ApiClient.instance;

  Position? _lastPosition;
  Position? get lastPosition => _lastPosition;

  StreamSubscription<Position>? _stream;
  Timer? _reportTimer;
  Timer? _heartbeatTimer;

  bool _isTracking = false;
  bool get isTracking => _isTracking;

  bool _hasGpsSignal = false;
  bool get hasGpsSignal => _hasGpsSignal;

  bool _isOnline = false;
  bool get isOnline => _isOnline;

  String? _lastError;
  String? get lastError => _lastError;

  String? _gpsStatusMessage;
  String? get gpsStatusMessage => _gpsStatusMessage;

  /// Inicia el sistema completo: heartbeat (siempre) + GPS (si se puede).
  /// Devuelve true si al menos el heartbeat arrancó.
  Future<bool> startTracking() async {
    if (_isTracking) return true;

    _isTracking = true;
    _lastError = null;

    // 1. HEARTBEAT — arranca SIEMPRE, sin importar el estado del GPS.
    //    Esto garantiza que el motorizado aparezca "en línea".
    _startHeartbeat();

    // 2. GPS — intenta arrancar, pero si falla no detiene el heartbeat.
    await _tryStartGps();

    notifyListeners();
    return true;
  }

  /// Arranca el heartbeat: marca al motorizado "en línea" en el servidor.
  void _startHeartbeat() {
    // Enviar heartbeat inmediatamente
    _sendHeartbeat();

    // Y repetir cada 30 segundos (antes 5s - era exagerado y gastaba bateria)
    // El servidor considera online por 60s sin heartbeat, asi que con 30s
    // hay margen para que un heartbeat falle por internet y el siguiente pase.
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _sendHeartbeat();
    });
  }

  /// Intenta arrancar el GPS. Si no se puede, el heartbeat sigue corriendo.
  Future<void> _tryStartGps() async {
    if (kIsWeb) {
      _gpsStatusMessage = 'GPS no disponible en web';
      _hasGpsSignal = false;
      return;
    }

    // Verificar permiso
    final hasPermission = await AppPermissions.requestLocation();
    if (!hasPermission) {
      _gpsStatusMessage =
          'Permiso de ubicación denegado — apareces en línea pero sin mapa';
      _hasGpsSignal = false;
      notifyListeners();
      return;
    }

    // Verificar que el servicio GPS esté activo
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _gpsStatusMessage =
          'GPS del dispositivo apagado — apareces en línea pero sin mapa';
      _hasGpsSignal = false;
      notifyListeners();
      return;
    }

    // Todo OK: arrancar el stream de ubicación
    _gpsStatusMessage = 'GPS activo';
    _stream?.cancel();
    _stream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 3,
      ),
    ).listen(
      (pos) {
        _lastPosition = pos;
        _hasGpsSignal = true;
        _gpsStatusMessage = 'GPS activo';
        notifyListeners();
      },
      onError: (e) {
        _hasGpsSignal = false;
        _gpsStatusMessage = 'Error de GPS: $e';
        notifyListeners();
      },
    );

    // Reporte de ubicación al servidor cada 1 segundo
    _reportTimer?.cancel();
    _reportTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _reportLocation();
    });

    // Primera lectura inmediata
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      _lastPosition = pos;
      _hasGpsSignal = true;
      _reportLocation();
      notifyListeners();
    } catch (e) {
      // No pasa nada: el stream eventualmente dará posición
      _gpsStatusMessage = 'Buscando señal GPS...';
      notifyListeners();
    }
  }

  /// Detiene todo: GPS + heartbeat. Marca offline en el servidor.
  Future<void> stopTracking() async {
    _isTracking = false;
    _hasGpsSignal = false;
    _isOnline = false;

    await _stream?.cancel();
    _stream = null;

    _reportTimer?.cancel();
    _reportTimer = null;

    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    // Marcar offline en el servidor
    await _markOffline();

    notifyListeners();
  }

  /// Obtiene la posición actual una sola vez (para selectores de mapa, etc.)
  Future<Position?> getCurrentPosition() async {
    if (kIsWeb) return null;

    final hasPermission = await AppPermissions.requestLocation();
    if (!hasPermission) {
      _lastError = 'Permiso de ubicación denegado';
      return null;
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _lastError = 'El GPS del dispositivo está desactivado';
      return null;
    }

    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      _lastPosition = pos;
      _lastError = null;
      notifyListeners();
      return pos;
    } catch (e) {
      _lastError = 'No se pudo obtener la ubicación: $e';
      notifyListeners();
      return null;
    }
  }

  /// Reporta la ubicación actual al servidor
  Future<void> _reportLocation() async {
    final pos = _lastPosition;
    if (pos == null) return;
    if (!_api.isAuthenticated) return;

    try {
      await _api.put('/api/me/location', {
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'accuracy': pos.accuracy,
        'speed': pos.speed >= 0 ? pos.speed : 0,
        'heading': pos.heading >= 0 ? pos.heading : 0,
      });
    } catch (_) {
      // Silencioso: el siguiente intento puede funcionar
    }
  }

  /// Envía heartbeat: "sigo en línea"
  /// Reintenta hasta 3 veces con un pequeño delay si falla por red.
  Future<void> _sendHeartbeat() async {
    if (!_api.isAuthenticated) {
      _isOnline = false;
      notifyListeners();
      return;
    }
    // Intentar hasta 3 veces con backoff
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        await _api.put('/api/me/heartbeat', {});
        _isOnline = true;
        notifyListeners();
        return;
      } catch (_) {
        // Si no fue el ultimo intento, esperar antes de reintentar
        if (attempt < 3) {
          await Future.delayed(Duration(seconds: attempt * 2));
        }
      }
    }
    // Si llegamos aqui, fallaron los 3 intentos
    _isOnline = false;
    notifyListeners();
  }

  /// Marca offline en el servidor (al cerrar sesión)
  Future<void> _markOffline() async {
    if (!_api.isAuthenticated) return;
    try {
      await _api.post('/api/me/offline');
    } catch (_) {}
  }

  /// Reintenta arrancar el GPS (útil si el usuario activó el GPS después)
  Future<void> retryGps() async {
    if (!_isTracking) return;
    await _tryStartGps();
  }

  @override
  void dispose() {
    stopTracking();
    super.dispose();
  }
}
