import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:geolocator/geolocator.dart';

/// Manejador centralizado de permisos del sistema.
/// Usa geolocator para GPS (más confiable que permission_handler para ubicación).
class AppPermissions {
  AppPermissions._();

  /// Pide notificaciones (solo Android 13+/iOS)
  static Future<bool> requestNotification() async {
    if (kIsWeb) return true;
    try {
      var status = await ph.Permission.notification.status;
      if (status.isGranted) return true;
      status = await ph.Permission.notification.request();
      return status.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// Verifica notificaciones
  static Future<bool> hasNotification() async {
    if (kIsWeb) return true;
    try {
      final status = await ph.Permission.notification.status;
      return status.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// Pide permiso de ubicación usando Geolocator (más confiable).
  /// Maneja el caso de servicio GPS desactivado.
  static Future<bool> requestLocation() async {
    if (kIsWeb) return true;

    try {
      // Paso 1: verificar si el servicio de GPS está activo
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        // El GPS del dispositivo está apagado
        // No podemos forzar al usuario a encenderlo desde el código
        return false;
      }

      // Paso 2: verificar permiso actual
      LocationPermission permission = await Geolocator.checkPermission();

      // Paso 3: si está denegado, pedirlo
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      // Paso 4: si quedó denegado para siempre, devolvemos false
      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        return false;
      }

      // whileInUse o always -> concedido
      return permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always;
    } catch (e) {
      return false;
    }
  }

  /// Verifica si hay permiso de ubicación
  static Future<bool> hasLocation() async {
    if (kIsWeb) return true;
    try {
      final permission = await Geolocator.checkPermission();
      return permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always;
    } catch (_) {
      return false;
    }
  }

  /// Verifica si el servicio de GPS del dispositivo está activado
  static Future<bool> isLocationServiceEnabled() async {
    if (kIsWeb) return true;
    try {
      return await Geolocator.isLocationServiceEnabled();
    } catch (_) {
      return false;
    }
  }

  /// Pide ubicación en background (para motorizado).
  /// En Android requiere haber concedido primero whileInUse.
  static Future<bool> requestLocationAlways() async {
    if (kIsWeb) return true;
    try {
      // Primero whileInUse
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        return false;
      }
      // Si ya tiene always, listo
      if (permission == LocationPermission.always) return true;
      // Pedir always (esto puede no aparecer en algunos Android,
      // el usuario tiene que ir a ajustes)
      try {
        final status = await ph.Permission.locationAlways.request();
        return status.isGranted;
      } catch (_) {
        return false;
      }
    } catch (_) {
      return false;
    }
  }

  /// Abre los ajustes del sistema para esta app
  static Future<bool> openAppSettings() async {
    try {
      return await ph.openAppSettings();
    } catch (_) {
      return false;
    }
  }

  /// Abre los ajustes de ubicación del dispositivo (para activar GPS)
  static Future<bool> openLocationSettings() async {
    try {
      return await Geolocator.openLocationSettings();
    } catch (_) {
      return false;
    }
  }

  /// Verifica si el permiso fue denegado permanentemente.
  /// Útil para saber si hay que dirigir al usuario a Ajustes.
  static Future<bool> isLocationDeniedForever() async {
    if (kIsWeb) return false;
    try {
      final permission = await Geolocator.checkPermission();
      return permission == LocationPermission.deniedForever;
    } catch (_) {
      return false;
    }
  }
}
