import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../services/database.dart';
import '../../widgets/design_system.dart';
import '../../widgets/components.dart';

/// Pantalla del super admin para bloquear/desbloquear la aplicación.
/// Solo visible para el super admin. Cuando se bloquea la app, todos los
/// demás usuarios ven una pantalla de bloqueo según su rol.
class AdminAppLock extends StatefulWidget {
  const AdminAppLock({super.key});

  @override
  State<AdminAppLock> createState() => _AdminAppLockState();
}

class _AdminAppLockState extends State<AdminAppLock> {
  final db = Database.instance;
  final _reason = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    db.addListener(_onChange);
    _reason.text = db.appLock.reason ?? '';
  }

  @override
  void dispose() {
    db.removeListener(_onChange);
    _reason.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<void> _lock() async {
    if (_reason.text.trim().isEmpty) {
      showErrorSnack(context,
          'Debes escribir el motivo del bloqueo. Los administradores lo verán.');
      return;
    }

    final ok = await showConfirmDialog(
      context,
      title: '¿Bloquear la aplicación?',
      message:
          'Todos los usuarios excepto tú dejarán de poder usar la app inmediatamente. '
          'Verán un mensaje según su rol. Tú seguirás teniendo acceso completo.',
      confirmLabel: 'Bloquear app',
      destructive: true,
    );
    if (!ok) return;

    setState(() => _saving = true);
    try {
      await db.setAppLock(locked: true, reason: _reason.text.trim());
      if (!mounted) return;
      showSuccessSnack(context, '🔒 Aplicación bloqueada para todos los demás usuarios');
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, 'Error: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _unlock() async {
    final ok = await showConfirmDialog(
      context,
      title: '¿Reanudar el servicio?',
      message:
          'La aplicación volverá a funcionar normalmente para todos los usuarios.',
      confirmLabel: 'Desbloquear',
    );
    if (!ok) return;

    setState(() => _saving = true);
    try {
      await db.setAppLock(locked: false);
      if (!mounted) return;
      showSuccessSnack(context, '✅ Aplicación reactivada');
      _reason.clear();
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, 'Error: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = db.currentUser;
    if (user == null || user.role != UserRole.superAdmin) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(DS.space5),
          child: Text(
            'Esta pantalla es exclusiva del Super Administrador.',
            style: TextStyle(color: DS.inkMuted),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final lock = db.appLock;
    final isLocked = lock.isLocked;

    return ListView(
      padding: const EdgeInsets.all(DS.space5),
      children: [
        // Header explicativo
        Container(
          padding: const EdgeInsets.all(DS.space5),
          decoration: BoxDecoration(
            color: DS.dark,
            borderRadius: BorderRadius.circular(DS.radiusLg),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: DS.brandOrange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(DS.radiusMd),
                ),
                child: const Icon(Icons.shield_outlined,
                    color: DS.brandOrange, size: 22),
              ),
              const SizedBox(width: DS.space4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('CONTROL DE SERVICIO',
                        style: DS.eyebrow(
                            color: Colors.white.withValues(alpha: 0.6))),
                    const SizedBox(height: 4),
                    Text('Bloqueo global',
                        style: DS.display(20,
                            color: Colors.white,
                            weight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(
                      'Tú nunca te ves bloqueado. Esta función impide a todos los demás usuarios usar la app, normalmente por falta de pago.',
                      style: DS.ui(12,
                          color: Colors.white.withValues(alpha: 0.7),
                          height: 1.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: DS.space5),

        // Estado actual + acciones
        Container(
          decoration: BoxDecoration(
            color: DS.surfaceRaised,
            borderRadius: BorderRadius.circular(DS.radiusLg),
            border: Border.all(
              color: isLocked ? DS.danger : DS.success,
              width: 2,
            ),
          ),
          child: Column(
            children: [
              // Status indicator
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: DS.space5, vertical: DS.space4),
                decoration: BoxDecoration(
                  color: isLocked
                      ? DS.danger.withValues(alpha: 0.06)
                      : DS.success.withValues(alpha: 0.06),
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(DS.radiusLg)),
                ),
                child: Row(
                  children: [
                    Icon(
                      isLocked ? Icons.lock : Icons.lock_open,
                      color: isLocked ? DS.danger : DS.success,
                      size: 20,
                    ),
                    const SizedBox(width: DS.space3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isLocked
                                ? 'APLICACIÓN BLOQUEADA'
                                : 'APLICACIÓN ACTIVA',
                            style: DS.eyebrow(
                                color:
                                    isLocked ? DS.danger : DS.success),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isLocked
                                ? 'Los demás usuarios no pueden usar la app'
                                : 'Todos los usuarios pueden trabajar normalmente',
                            style: DS.ui(13,
                                color: DS.ink,
                                weight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Body
              Padding(
                padding: const EdgeInsets.all(DS.space5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (isLocked) ...[
                      // ----- Estado bloqueado -----
                      _InfoBlock(
                        label: 'Motivo registrado',
                        value: lock.reason ?? 'Sin motivo',
                      ),
                      const SizedBox(height: DS.space3),
                      if (lock.lockedAt != null)
                        _InfoBlock(
                          label: 'Bloqueada desde',
                          value: formatDateLong(lock.lockedAt!.toLocal()),
                        ),
                      const SizedBox(height: DS.space5),

                      // Vista previa de mensajes por rol
                      Text('LO QUE VEN LOS USUARIOS', style: DS.eyebrow()),
                      const SizedBox(height: DS.space2),
                      Text(
                        'Cada rol ve un mensaje diferente:',
                        style: DS.ui(12, color: DS.inkMuted),
                      ),
                      const SizedBox(height: DS.space3),
                      _RolePreview(
                        roleLabel: 'Administrador',
                        icon: Icons.shield_outlined,
                        color: DS.warning,
                        title: 'Aplicación bloqueada',
                        message:
                            'Ven el motivo completo que escribiste',
                      ),
                      const SizedBox(height: DS.space2),
                      _RolePreview(
                        roleLabel: 'Motorizado / Operador',
                        icon: Icons.engineering_outlined,
                        color: DS.brandOrange,
                        title: 'Aplicación fuera de servicio',
                        message: 'Mensaje neutral, sin el motivo',
                      ),
                      const SizedBox(height: DS.space2),
                      _RolePreview(
                        roleLabel: 'Empresa cliente',
                        icon: Icons.access_time,
                        color: DS.brandBlue,
                        title: 'Servicio temporalmente pausado',
                        message:
                            'Mensaje amistoso indicando que se reanudará pronto',
                      ),

                      const SizedBox(height: DS.space5),

                      // Botón desbloquear
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _saving ? null : _unlock,
                          icon: _saving
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white))
                              : const Icon(Icons.lock_open, size: 16),
                          label: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Text(_saving
                                ? 'Procesando...'
                                : 'Reanudar servicio'),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: DS.success,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ] else ...[
                      // ----- Estado activo: formulario para bloquear -----
                      Text('MOTIVO DEL BLOQUEO', style: DS.eyebrow()),
                      const SizedBox(height: DS.space2),
                      Text(
                        'Escribe la razón. Los administradores la verán cuando intenten usar la app.',
                        style:
                            DS.ui(12, color: DS.inkMuted, height: 1.5),
                      ),
                      const SizedBox(height: DS.space3),
                      TextField(
                        controller: _reason,
                        maxLines: 3,
                        maxLength: 200,
                        decoration: const InputDecoration(
                          hintText:
                              'Ej: Falta de pago de la mensualidad. Contactar a contabilidad para reanudar el servicio.',
                        ),
                      ),
                      const SizedBox(height: DS.space4),
                      // Sugerencias rápidas
                      Wrap(
                        spacing: DS.space2,
                        runSpacing: DS.space2,
                        children: [
                          _ReasonChip(
                              text:
                                  'Falta de pago de la mensualidad',
                              onTap: () => setState(() {
                                    _reason.text =
                                        'Falta de pago de la mensualidad. Contactar a contabilidad.';
                                  })),
                          _ReasonChip(
                              text: 'Mantenimiento programado',
                              onTap: () => setState(() {
                                    _reason.text =
                                        'Mantenimiento programado. Reanudaremos en breve.';
                                  })),
                          _ReasonChip(
                              text: 'Suspensión administrativa',
                              onTap: () => setState(() {
                                    _reason.text =
                                        'Suspensión administrativa. Contactar a la central.';
                                  })),
                        ],
                      ),
                      const SizedBox(height: DS.space5),

                      // Advertencia
                      Container(
                        padding: const EdgeInsets.all(DS.space3),
                        decoration: BoxDecoration(
                          color: DS.warningBg,
                          borderRadius: BorderRadius.circular(DS.radiusSm),
                          border: Border.all(
                              color: DS.warning.withValues(alpha: 0.2),
                              width: 1),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.warning_amber_rounded,
                                color: DS.warning, size: 16),
                            const SizedBox(width: DS.space2),
                            Expanded(
                              child: Text(
                                'Al bloquear, todos los demás usuarios serán expulsados de sus pantallas activas en máximo 3 segundos. Las órdenes en curso se conservan.',
                                style: DS.ui(11,
                                    color: DS.warning,
                                    weight: FontWeight.w500,
                                    height: 1.5),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: DS.space5),

                      // Botón bloquear
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _saving ? null : _lock,
                          icon: _saving
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white))
                              : const Icon(Icons.lock, size: 16),
                          label: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Text(_saving
                                ? 'Procesando...'
                                : 'Bloquear aplicación'),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: DS.danger,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoBlock extends StatelessWidget {
  final String label;
  final String value;
  const _InfoBlock({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DS.space3),
      decoration: BoxDecoration(
        color: DS.surfaceMuted,
        borderRadius: BorderRadius.circular(DS.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: DS.eyebrow()),
          const SizedBox(height: 4),
          Text(value,
              style: DS.ui(13,
                  weight: FontWeight.w600, height: 1.5)),
        ],
      ),
    );
  }
}

class _RolePreview extends StatelessWidget {
  final String roleLabel;
  final IconData icon;
  final Color color;
  final String title;
  final String message;

  const _RolePreview({
    required this.roleLabel,
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DS.space3),
      decoration: BoxDecoration(
        color: DS.surfaceMuted,
        borderRadius: BorderRadius.circular(DS.radiusSm),
        border: Border.all(color: DS.border, width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(DS.radiusSm),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: DS.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(roleLabel,
                        style: DS.ui(11, color: DS.inkMuted)),
                    const SizedBox(width: 4),
                    const Text('·',
                        style: TextStyle(color: DS.inkMuted)),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(title,
                          style: DS.ui(12,
                              color: color,
                              weight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(message,
                    style: DS.ui(11, color: DS.inkSecondary, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReasonChip extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  const _ReasonChip({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DS.radiusSm),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: DS.space3, vertical: 6),
        decoration: BoxDecoration(
          color: DS.surfaceMuted,
          borderRadius: BorderRadius.circular(DS.radiusSm),
          border: Border.all(color: DS.border, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add, size: 12, color: DS.inkMuted),
            const SizedBox(width: 4),
            Text(text,
                style: DS.ui(11,
                    color: DS.inkSecondary, weight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}
