import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../services/database.dart';
import '../../widgets/design_system.dart';
import '../../widgets/components.dart';
import '_form_helpers.dart';

class AdminRiders extends StatelessWidget {
  const AdminRiders({super.key});

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
                  '${db.riders.length} motorizado${db.riders.length == 1 ? "" : "s"} registrado${db.riders.length == 1 ? "" : "s"}',
                  style: DS.ui(13, color: DS.inkMuted)),
            ),
            ElevatedButton.icon(
              onPressed: () => _showAddRider(context),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Nuevo motorizado'),
            ),
          ],
        ),
        const SizedBox(height: DS.space5),
        if (db.riders.isEmpty)
          const SizedBox(
            height: 360,
            child: EmptyState(
              icon: Icons.two_wheeler_outlined,
              message: 'Aún no hay motorizados registrados',
              hint: 'Los motorizados podrán entrar con su correo, ver órdenes asignadas y registrar sus ganancias.',
            ),
          )
        else
          ...db.riders.map((r) {
            final stats = db.riderStats(r.id);
            return Padding(
              padding: const EdgeInsets.only(bottom: DS.space2),
              child: EntityRow(
                icon: Icons.two_wheeler,
                name: r.name,
                subtitle: '${r.email}\n${r.vehicle.label} · ${r.plate} · ${r.phone}',
                accentColor: DS.brandOrange,
                metaChips: [
                  MetaChip(
                      icon: Icons.local_shipping_outlined,
                      label: '${stats['delivered']} entregas'),
                  MetaChip(
                      icon: Icons.payments_outlined,
                      label: formatMoney(stats['earned']),
                      color: DS.success),
                  if ((stats['active'] as int) > 0)
                    MetaChip(
                        icon: Icons.directions_run,
                        label: '${stats['active']} activas',
                        color: DS.accent),
                ],
                onDelete: () async {
                  final ok = await showConfirmDialog(
                    context,
                    title: 'Eliminar motorizado',
                    message: '¿Eliminar a "${r.name}"? Sus entregas históricas se mantendrán.',
                  );
                  if (ok) db.deleteRider(r.id);
                },
              ),
            );
          }),
      ],
    );
  }

  void _showAddRider(BuildContext context) {
    final db = Database.instance;
    final name = TextEditingController();
    final email = TextEditingController();
    final phone = TextEditingController();
    final plate = TextEditingController();
    final pass = TextEditingController();
    VehicleType vehicle = VehicleType.motorcycle;

    showEntityFormSheet(
      context,
      title: 'Nuevo motorizado',
      subtitle: 'Repartidor que ejecuta entregas',
      icon: Icons.two_wheeler,
      iconColor: DS.brandOrange,
      buildFields: (setSt) => [
        LabeledField(
          label: 'Nombre completo',
          controller: name,
          hint: 'Ej. Carlos Méndez',
          icon: Icons.person_outline,
          validator: (v) => v?.trim().isEmpty == true ? 'Requerido' : null,
        ),
        LabeledField(
          label: 'Correo electrónico',
          controller: email,
          hint: 'carlos@ejemplo.com',
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
        LabeledDropdown<VehicleType>(
          label: 'Tipo de vehículo',
          value: vehicle,
          items: VehicleType.values
              .map((v) => DropdownMenuItem(value: v, child: Text(v.label)))
              .toList(),
          onChanged: (v) => setSt(() => vehicle = v!),
        ),
        LabeledField(
          label: 'Placa / Identificación',
          controller: plate,
          hint: 'ABC-123',
          icon: Icons.confirmation_num_outlined,
        ),
      ],
      onSave: () {
        db.addRider(
          name: name.text.trim(),
          email: email.text.trim(),
          phone: phone.text.trim(),
          vehicle: vehicle,
          plate: plate.text.trim(),
          password: pass.text,
        );
        showSuccessSnack(context, 'Motorizado "${name.text.trim()}" agregado');
      },
    );
  }
}
