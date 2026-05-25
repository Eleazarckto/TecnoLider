import 'dart:math' as math;

/// Servicio para calcular distancia y tiempo estimado de llegada (ETA).
/// Usa la fórmula Haversine para distancia en línea recta y un promedio
/// de velocidad de 25 km/h para motorizado urbano.
class EtaService {
  EtaService._();

  /// Velocidad promedio del motorizado en km/h (incluye paradas, tráfico).
  /// Yummy y otras apps usan valores similares en zona urbana.
  static const double avgSpeedKmh = 25.0;

  /// Calcula distancia entre dos puntos en kilómetros (Haversine).
  static double distanceKm(double lat1, double lng1, double lat2, double lng2) {
    const earthRadiusKm = 6371.0;

    final dLat = _toRad(lat2 - lat1);
    final dLng = _toRad(lng2 - lng1);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(lat1)) *
            math.cos(_toRad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  /// Calcula ETA en minutos basado en distancia
  static int etaMinutes(double distanceKm) {
    final hours = distanceKm / avgSpeedKmh;
    final minutes = (hours * 60).round();
    return minutes < 1 ? 1 : minutes;
  }

  /// Formatea distancia para mostrar al usuario
  static String formatDistance(double km) {
    if (km < 1) {
      final m = (km * 1000).round();
      return '$m m';
    }
    return '${km.toStringAsFixed(1)} km';
  }

  /// Formatea tiempo en minutos
  static String formatEta(int minutes) {
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (m == 0) return '$h h';
    return '$h h $m min';
  }

  static double _toRad(double deg) => deg * (math.pi / 180.0);
}
