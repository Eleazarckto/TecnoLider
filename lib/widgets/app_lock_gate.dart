import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/database.dart';
import 'design_system.dart';
import 'components.dart';

/// Wraps any child widget. If the app is locked AND the user is not the super admin,
/// shows a role-specific lock screen instead of the child.
///
/// Reglas:
///   - Super Admin: nunca ve bloqueo (puede seguir usando la app normalmente)
///   - Admin: ve la razón completa del bloqueo
///   - Motorizado / Operador: mensaje "fuera de servicio"
///   - Empresa: mensaje amistoso "se reanudará en breve"
class AppLockGate extends StatefulWidget {
  final Widget child;
  const AppLockGate({super.key, required this.child});

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> {
  final db = Database.instance;

  @override
  void initState() {
    super.initState();
    db.addListener(_onChange);
  }

  @override
  void dispose() {
    db.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final user = db.currentUser;
    final lock = db.appLock;

    // Si no hay usuario o la app no está bloqueada → mostrar la app normal
    if (user == null || !lock.isLocked) {
      return widget.child;
    }

    // El super admin nunca se ve bloqueado
    if (user.role == UserRole.superAdmin) {
      return widget.child;
    }

    // Para todos los demás → pantalla de bloqueo según rol
    return _LockedScreen(role: user.role, lock: lock, onLogout: _logout);
  }

  Future<void> _logout() async {
    await db.logout();
  }
}

class _LockedScreen extends StatelessWidget {
  final UserRole role;
  final AppLock lock;
  final VoidCallback onLogout;

  const _LockedScreen({
    required this.role,
    required this.lock,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final config = _configFor(role, lock);

    return Scaffold(
      backgroundColor: DS.dark,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(DS.space6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo grande
                  const YjLogo(size: 80, light: false),
                  const SizedBox(height: DS.space6),
                  // Icono grande
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: config.color.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(config.icon, color: config.color, size: 36),
                  ),
                  const SizedBox(height: DS.space5),
                  // Título
                  Text(
                    config.title,
                    textAlign: TextAlign.center,
                    style: DS.display(26,
                        color: Colors.white, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: DS.space3),
                  // Mensaje
                  Text(
                    config.message,
                    textAlign: TextAlign.center,
                    style: DS.ui(15,
                        color: Colors.white.withValues(alpha: 0.7),
                        height: 1.6),
                  ),
                  // Si es admin, mostrar la razón
                  if (config.showReason &&
                      lock.reason != null &&
                      lock.reason!.trim().isNotEmpty) ...[
                    const SizedBox(height: DS.space5),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(DS.space4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(DS.radiusMd),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1),
                            width: 1),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('MOTIVO',
                              style: DS.eyebrow(
                                  color:
                                      Colors.white.withValues(alpha: 0.5))),
                          const SizedBox(height: DS.space2),
                          Text(
                            lock.reason!,
                            style: DS.ui(14,
                                color: Colors.white,
                                weight: FontWeight.w500,
                                height: 1.5),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 48),
                  // Botón de cerrar sesión
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: onLogout,
                      icon: const Icon(Icons.logout_outlined, size: 16),
                      label: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 6),
                        child: Text('Cerrar sesión'),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.3),
                            width: 1),
                      ),
                    ),
                  ),
                  const SizedBox(height: DS.space5),
                  // Estado
                  if (lock.lockedAt != null)
                    Text(
                      'Bloqueada el ${formatDateLong(lock.lockedAt!.toLocal())}',
                      style: DS.ui(11,
                          color: Colors.white.withValues(alpha: 0.4)),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Determina el contenido del bloqueo según el rol
  _LockConfig _configFor(UserRole role, AppLock lock) {
    switch (role) {
      case UserRole.admin:
        return _LockConfig(
          icon: Icons.lock_outline,
          color: DS.warning,
          title: 'Aplicación bloqueada',
          message:
              'El super administrador ha bloqueado la aplicación. Contacta a la administración central para más información.',
          showReason: true,
        );
      case UserRole.operator:
      case UserRole.rider:
        return _LockConfig(
          icon: Icons.engineering_outlined,
          color: DS.brandOrange,
          title: 'Aplicación fuera de servicio',
          message:
              'El servicio está temporalmente fuera de línea. No es posible procesar órdenes en este momento.',
          showReason: false,
        );
      case UserRole.company:
        return _LockConfig(
          icon: Icons.access_time,
          color: DS.brandBlue,
          title: 'Servicio temporalmente pausado',
          message:
              'Estamos realizando mantenimiento. El servicio se reanudará en breve. Disculpa las molestias.',
          showReason: false,
        );
      case UserRole.superAdmin:
        // No debería llegar aquí porque el super admin nunca se bloquea,
        // pero por completitud:
        return _LockConfig(
          icon: Icons.lock_outline,
          color: DS.danger,
          title: 'Aplicación bloqueada',
          message: 'Estado de bloqueo activo.',
          showReason: true,
        );
    }
  }
}

class _LockConfig {
  final IconData icon;
  final Color color;
  final String title;
  final String message;
  final bool showReason;

  _LockConfig({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
    required this.showReason,
  });
}
