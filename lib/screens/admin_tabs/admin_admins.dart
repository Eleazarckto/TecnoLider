import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../services/database.dart';
import '../../widgets/design_system.dart';
import '../../widgets/components.dart';
import '_form_helpers.dart';

class AdminAdmins extends StatelessWidget {
  const AdminAdmins({super.key});

  @override
  Widget build(BuildContext context) {
    final db = Database.instance;
    final admins = db.users.where((u) => u.role == UserRole.admin).toList();

    return ListView(
      padding: const EdgeInsets.all(DS.space6),
      children: [
        Container(
          padding: const EdgeInsets.all(DS.space4),
          decoration: BoxDecoration(
            color: DS.warningBg,
            borderRadius: BorderRadius.circular(DS.radiusMd),
            border: Border.all(color: DS.warning.withValues(alpha: 0.2), width: 1),
          ),
          child: Row(
            children: [
              const Icon(Icons.shield_outlined, size: 18, color: DS.warning),
              const SizedBox(width: DS.space3),
              Expanded(
                child: Text(
                  'Los administradores tienen acceso completo a la plataforma. Otórgalos solo a personal de máxima confianza.',
                  style: DS.ui(12, color: DS.warning, height: 1.5),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: DS.space5),
        Row(
          children: [
            Expanded(
              child: Text(
                  '${admins.length} administrador${admins.length == 1 ? "" : "es"} adicional${admins.length == 1 ? "" : "es"}',
                  style: DS.ui(13, color: DS.inkMuted)),
            ),
            ElevatedButton.icon(
              onPressed: () => _showAdd(context),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Nuevo admin'),
            ),
          ],
        ),
        const SizedBox(height: DS.space5),
        if (admins.isEmpty)
          const SizedBox(
            height: 280,
            child: EmptyState(
              icon: Icons.shield_outlined,
              message: 'No hay administradores adicionales',
              hint: 'Solo el super administrador tiene acceso. Puedes agregar más administradores cuando lo necesites.',
            ),
          )
        else
          ...admins.map((a) => Padding(
                padding: const EdgeInsets.only(bottom: DS.space2),
                child: EntityRow(
                  icon: Icons.shield,
                  name: a.name,
                  subtitle: a.email,
                  accentColor: DS.danger,
                  onDelete: () async {
                    final ok = await showConfirmDialog(
                      context,
                      title: 'Eliminar administrador',
                      message: '¿Eliminar el acceso de "${a.name}"? Perderá acceso al panel inmediatamente.',
                    );
                    if (ok) db.deleteUser(a.id);
                  },
                ),
              )),
      ],
    );
  }

  void _showAdd(BuildContext context) {
    final db = Database.instance;
    final name = TextEditingController();
    final email = TextEditingController();
    final pass = TextEditingController();

    showEntityFormSheet(
      context,
      title: 'Nuevo administrador',
      subtitle: 'Acceso completo al panel',
      icon: Icons.shield,
      iconColor: DS.danger,
      buildFields: (setSt) => [
        LabeledField(
          label: 'Nombre completo',
          controller: name,
          icon: Icons.person_outline,
          validator: (v) => v?.trim().isEmpty == true ? 'Requerido' : null,
        ),
        LabeledField(
          label: 'Correo electrónico',
          controller: email,
          icon: Icons.alternate_email,
          keyboardType: TextInputType.emailAddress,
          validator: (v) {
            if (v?.trim().isEmpty == true) return 'Requerido';
            if (db.emailExists(v!)) return 'Este email ya está en uso';
            return null;
          },
        ),
        LabeledField(
          label: 'Contraseña',
          controller: pass,
          icon: Icons.lock_outline,
          obscure: true,
          validator: (v) => (v?.length ?? 0) < 4 ? 'Mínimo 4 caracteres' : null,
        ),
      ],
      onSave: () {
        db.addAdmin(
          name: name.text.trim(),
          email: email.text.trim(),
          password: pass.text,
        );
        showSuccessSnack(context, 'Administrador "${name.text.trim()}" agregado');
      },
    );
  }
}
