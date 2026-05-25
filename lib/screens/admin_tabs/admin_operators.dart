import 'package:flutter/material.dart';
import '../../services/database.dart';
import '../../widgets/design_system.dart';
import '../../widgets/components.dart';
import '_form_helpers.dart';

class AdminOperators extends StatelessWidget {
  const AdminOperators({super.key});

  @override
  Widget build(BuildContext context) {
    final db = Database.instance;
    return ListView(
      padding: const EdgeInsets.all(DS.space6),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                  '${db.operators.length} operador${db.operators.length == 1 ? "" : "es"} registrado${db.operators.length == 1 ? "" : "s"}',
                  style: DS.ui(13, color: DS.inkMuted)),
            ),
            ElevatedButton.icon(
              onPressed: () => _showAdd(context),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Nuevo operador'),
            ),
          ],
        ),
        const SizedBox(height: DS.space5),
        if (db.operators.isEmpty)
          const SizedBox(
            height: 360,
            child: EmptyState(
              icon: Icons.headset_mic_outlined,
              message: 'No hay operadores registrados',
              hint: 'Los operadores reciben las órdenes que llegan a la central y las asignan al motorizado disponible.',
            ),
          )
        else
          ...db.operators.map((o) => Padding(
                padding: const EdgeInsets.only(bottom: DS.space2),
                child: EntityRow(
                  icon: Icons.headset_mic,
                  name: o.name,
                  subtitle: '${o.email}\n${o.phone}',
                  accentColor: DS.accent,
                  onDelete: () async {
                    final ok = await showConfirmDialog(
                      context,
                      title: 'Eliminar operador',
                      message: '¿Eliminar a "${o.name}"?',
                    );
                    if (ok) db.deleteOperator(o.id);
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
    final phone = TextEditingController();
    final pass = TextEditingController();

    showEntityFormSheet(
      context,
      title: 'Nuevo operador',
      subtitle: 'Personal de central que asigna entregas',
      icon: Icons.headset_mic,
      iconColor: DS.accent,
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
        LabeledField(
          label: 'Teléfono',
          controller: phone,
          icon: Icons.phone_outlined,
          keyboardType: TextInputType.phone,
        ),
      ],
      onSave: () {
        db.addOperator(
          name: name.text.trim(),
          email: email.text.trim(),
          phone: phone.text.trim(),
          password: pass.text,
        );
        showSuccessSnack(context, 'Operador "${name.text.trim()}" agregado');
      },
    );
  }
}
