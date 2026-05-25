import 'package:flutter/material.dart';
import 'database.dart';
import 'external_apps.dart';

/// Servicio de soporte: abre WhatsApp con el número configurado por el admin.
class SupportService {
  SupportService._();

  /// Mensaje por defecto al abrir el chat
  static String _defaultMessage(String userRole, String userName) {
    return 'Hola, soy $userName ($userRole) y necesito ayuda con YJ Delivery.';
  }

  /// Devuelve true si hay un numero de soporte configurado por el admin.
  static bool get isConfigured =>
      Database.instance.config.supportPhone.trim().isNotEmpty;

  /// Abre WhatsApp con el chat de soporte.
  /// El número viene del config del admin (lo configura en su panel).
  static Future<bool> openSupport({
    required BuildContext context,
    required String userRole,
    required String userName,
    String? customMessage,
  }) async {
    final phone = Database.instance.config.supportPhone.trim();

    if (phone.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'El número de soporte aún no está configurado. Contacta al administrador.'),
          ),
        );
      }
      return false;
    }

    final message = customMessage ?? _defaultMessage(userRole, userName);
    final ok = await ExternalApps.openWhatsApp(phone, message: message);

    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'No se pudo abrir WhatsApp. Verifica que esté instalado.'),
        ),
      );
    }
    return ok;
  }
}
