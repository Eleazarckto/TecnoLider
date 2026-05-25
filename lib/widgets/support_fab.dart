import 'package:flutter/material.dart';
import '../services/support_service.dart';
import '../services/database.dart';
import '../models/models.dart';
import 'design_system.dart';

/// Botón flotante de ayuda/soporte por WhatsApp.
/// Se puede agregar a cualquier pantalla con Stack o como floatingActionButton.
class SupportFab extends StatelessWidget {
  /// Si false, no muestra texto, solo el icono
  final bool extended;

  const SupportFab({super.key, this.extended = false});

  @override
  Widget build(BuildContext context) {
    final user = Database.instance.currentUser;
    if (user == null) return const SizedBox.shrink();

    if (extended) {
      return FloatingActionButton.extended(
        onPressed: () => SupportService.openSupport(
          context: context,
          userRole: user.role.label,
          userName: user.name,
        ),
        icon: const Icon(Icons.support_agent),
        label: const Text('Ayuda'),
        backgroundColor: DS.success,
        foregroundColor: Colors.white,
        elevation: 6,
        tooltip: 'Contactar soporte por WhatsApp',
      );
    }

    return FloatingActionButton(
      onPressed: () => SupportService.openSupport(
        context: context,
        userRole: user.role.label,
        userName: user.name,
      ),
      backgroundColor: DS.success,
      foregroundColor: Colors.white,
      elevation: 6,
      tooltip: 'Soporte por WhatsApp',
      child: const Icon(Icons.support_agent),
    );
  }
}

/// Item de menú "Contactar soporte"
class SupportMenuItem extends StatelessWidget {
  const SupportMenuItem({super.key});

  @override
  Widget build(BuildContext context) {
    final user = Database.instance.currentUser;
    if (user == null) return const SizedBox.shrink();

    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: DS.success.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.support_agent, color: DS.success, size: 20),
      ),
      title: const Text('Contactar soporte'),
      subtitle: Text(
        'Chat directo por WhatsApp',
        style: DS.ui(11, color: DS.inkMuted),
      ),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: () => SupportService.openSupport(
        context: context,
        userRole: user.role.label,
        userName: user.name,
      ),
    );
  }
}
