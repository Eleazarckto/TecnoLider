import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';

/// Servicio para abrir apps externas: teléfono, WhatsApp, Google Maps.
class ExternalApps {
  ExternalApps._();

  /// Abre el marcador del teléfono con el número precargado
  static Future<bool> callPhone(String phone) async {
    final cleaned = _cleanPhone(phone);
    final uri = Uri.parse('tel:$cleaned');
    try {
      return await launchUrl(uri);
    } catch (_) {
      return false;
    }
  }

  /// Abre WhatsApp con el número y mensaje opcional
  static Future<bool> openWhatsApp(String phone, {String? message}) async {
    final cleaned = _cleanPhone(phone);
    final waNumber = cleaned.startsWith('+') ? cleaned.substring(1) : cleaned;
    final encodedMsg = message != null ? Uri.encodeComponent(message) : '';
    final url =
        'https://wa.me/$waNumber${encodedMsg.isNotEmpty ? "?text=$encodedMsg" : ""}';
    try {
      return await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }

  /// Abre la navegación GPS directamente hacia el destino.
  ///
  /// Estrategia (intenta en orden hasta que una funcione):
  ///  1. Android: `google.navigation:` — abre Google Maps DIRECTO en modo
  ///     navegación turn-by-turn con voz (lo más rápido para el motorizado)
  ///  2. iOS: `comgooglemaps://` — abre la app de Google Maps si está instalada
  ///  3. Universal: URL de Google Maps — abre en navegador o app
  ///  4. iOS fallback: Apple Maps
  static Future<bool> navigateTo(double lat, double lng, {String? label}) async {
    // 1. Android: intent nativo de navegación (abre directo con voz)
    if (!kIsWeb && Platform.isAndroid) {
      final navUri = Uri.parse('google.navigation:q=$lat,$lng&mode=d');
      try {
        if (await canLaunchUrl(navUri)) {
          final ok = await launchUrl(
            navUri,
            mode: LaunchMode.externalApplication,
          );
          if (ok) return true;
        }
      } catch (_) {
        // sigue al siguiente intento
      }
    }

    // 2. iOS: app de Google Maps si está instalada
    if (!kIsWeb && Platform.isIOS) {
      final gmapsUri = Uri.parse(
          'comgooglemaps://?daddr=$lat,$lng&directionsmode=driving');
      try {
        if (await canLaunchUrl(gmapsUri)) {
          final ok = await launchUrl(
            gmapsUri,
            mode: LaunchMode.externalApplication,
          );
          if (ok) return true;
        }
      } catch (_) {
        // sigue al siguiente intento
      }
    }

    // 3. Universal: URL de Google Maps (funciona en Android, iOS y web)
    final universalUrl = 'https://www.google.com/maps/dir/?api=1'
        '&destination=$lat,$lng'
        '&travelmode=driving'
        '&dir_action=navigate';
    try {
      final ok = await launchUrl(
        Uri.parse(universalUrl),
        mode: LaunchMode.externalApplication,
      );
      if (ok) return true;
    } catch (_) {
      // sigue al siguiente intento
    }

    // 4. iOS fallback final: Apple Maps
    if (!kIsWeb && Platform.isIOS) {
      final appleUri = Uri.parse('https://maps.apple.com/?daddr=$lat,$lng&dirflg=d');
      try {
        return await launchUrl(
          appleUri,
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {
        return false;
      }
    }

    return false;
  }

  /// Abre Google Maps mostrando solo la ubicación (sin navegación)
  static Future<bool> showLocation(double lat, double lng, {String? label}) async {
    final url = 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
    try {
      return await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }

  /// Limpia un teléfono: quita espacios, paréntesis, guiones
  static String _cleanPhone(String phone) {
    return phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');
  }
}
