import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../services/database.dart';
import '../../widgets/design_system.dart';
import '../../widgets/components.dart';

/// Pantalla de admin para gestionar los métodos de pago.
/// Permite:
///   - Crear/eliminar métodos
///   - Definir qué campos tiene cada uno (banco, cuenta, etc.)
///   - Guardar los valores reales (BBVA, 1234, etc.)
class AdminPaymentMethods extends StatefulWidget {
  const AdminPaymentMethods({super.key});

  @override
  State<AdminPaymentMethods> createState() => _AdminPaymentMethodsState();
}

class _AdminPaymentMethodsState extends State<AdminPaymentMethods> {
  final db = Database.instance;
  int? _selectedId;

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
    final methods = db.paymentMethods;
    final isWide = MediaQuery.of(context).size.width >= 900;

    if (methods.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(DS.space6),
        child: EmptyState(
          icon: Icons.payment,
          message: 'No hay métodos de pago',
          hint: 'Crea el primero para que las empresas puedan pagar.',
          action: ElevatedButton.icon(
            onPressed: _addMethod,
            icon: const Icon(Icons.add, size: 16),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text('Crear método'),
            ),
          ),
        ),
      );
    }

    final selected = _selectedId == null
        ? methods.first
        : methods.firstWhere((m) => m.id == _selectedId,
            orElse: () => methods.first);

    if (isWide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 320,
            child: _MethodsList(
              methods: methods,
              selectedId: selected.id,
              onSelect: (id) => setState(() => _selectedId = id),
              onAdd: _addMethod,
            ),
          ),
          const VerticalDivider(width: 1, color: DS.border),
          Expanded(
            child: _MethodDetail(
              method: selected,
              onDelete: () => _deleteMethod(selected),
            ),
          ),
        ],
      );
    }

    // Mobile: solo lista. Al tocar un item, abre detalle en página nueva.
    return _MethodsList(
      methods: methods,
      selectedId: null,
      onSelect: (id) {
        final m = methods.firstWhere((x) => x.id == id);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => Scaffold(
              appBar: AppBar(
                title: Text(m.name),
                backgroundColor: DS.surfaceRaised,
                foregroundColor: DS.ink,
                elevation: 0,
                shape: const Border(bottom: BorderSide(color: DS.border)),
              ),
              body: _MethodDetail(
                method: m,
                onDelete: () async {
                  await _deleteMethod(m);
                  if (mounted && Navigator.canPop(context)) {
                    Navigator.pop(context);
                  }
                },
              ),
            ),
          ),
        );
      },
      onAdd: _addMethod,
    );
  }

  Future<void> _addMethod() async {
    final result = await showDialog<({String name, String icon})>(
      context: context,
      builder: (ctx) => const _AddMethodDialog(),
    );
    if (result == null) return;

    try {
      await db.addPaymentMethod(name: result.name, icon: result.icon);
      if (mounted) {
        showSuccessSnack(context, 'Método "${result.name}" creado');
      }
    } catch (e) {
      if (mounted) showErrorSnack(context, 'Error: $e');
    }
  }

  Future<void> _deleteMethod(PaymentMethod m) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Eliminar método',
      message:
          '¿Eliminar "${m.name}"? Las órdenes que ya lo usaron seguirán mostrándolo, pero no podrá usarse en órdenes nuevas.',
      confirmLabel: 'Eliminar',
      destructive: true,
    );
    if (!ok) return;
    try {
      await db.deletePaymentMethod(m.id);
      if (mounted) {
        setState(() => _selectedId = null);
        showSuccessSnack(context, 'Método eliminado');
      }
    } catch (e) {
      if (mounted) showErrorSnack(context, 'Error: $e');
    }
  }
}

// ============ LISTA DE MÉTODOS ============
class _MethodsList extends StatelessWidget {
  final List<PaymentMethod> methods;
  final int? selectedId;
  final ValueChanged<int> onSelect;
  final VoidCallback onAdd;

  const _MethodsList({
    required this.methods,
    required this.selectedId,
    required this.onSelect,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: DS.surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(DS.space5),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('MÉTODOS DE PAGO', style: DS.eyebrow()),
                      const SizedBox(height: 2),
                      Text('Configura cómo cobras',
                          style:
                              DS.display(20, weight: FontWeight.w500)),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Nuevo'),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: DS.border),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(DS.space4),
              itemCount: methods.length,
              separatorBuilder: (_, __) => const SizedBox(height: DS.space2),
              itemBuilder: (context, i) {
                final m = methods[i];
                final isSelected = m.id == selectedId;
                final hasValues = m.values.isNotEmpty;
                final missingValues = !m.hasAllRequiredValues;

                return Material(
                  color: isSelected
                      ? DS.brandOrange.withValues(alpha: 0.10)
                      : DS.surfaceRaised,
                  borderRadius: BorderRadius.circular(DS.radiusMd),
                  child: InkWell(
                    onTap: () => onSelect(m.id),
                    borderRadius: BorderRadius.circular(DS.radiusMd),
                    child: Container(
                      padding: const EdgeInsets.all(DS.space3),
                      decoration: BoxDecoration(
                        border: Border.all(
                            color:
                                isSelected ? DS.brandOrange : DS.border,
                            width: 1),
                        borderRadius: BorderRadius.circular(DS.radiusMd),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: DS.brandBlue.withValues(alpha: 0.12),
                              borderRadius:
                                  BorderRadius.circular(DS.radiusSm),
                            ),
                            child: Icon(PaymentMethod.iconFor(m.icon),
                                color: DS.brandBlue, size: 18),
                          ),
                          const SizedBox(width: DS.space3),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(m.name,
                                    style: DS.ui(13,
                                        weight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                Text(
                                  '${m.fields.length} campo${m.fields.length == 1 ? "" : "s"}'
                                  '${hasValues ? " · datos completados" : ""}',
                                  style:
                                      DS.ui(11, color: DS.inkMuted),
                                ),
                              ],
                            ),
                          ),
                          if (missingValues)
                            const Icon(Icons.warning_amber_rounded,
                                color: DS.warning, size: 16)
                          else if (hasValues)
                            const Icon(Icons.check_circle,
                                color: DS.success, size: 16),
                          const SizedBox(width: 4),
                          const Icon(Icons.chevron_right,
                              color: DS.inkMuted, size: 18),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ============ DETALLE DE MÉTODO ============
class _MethodDetail extends StatefulWidget {
  final PaymentMethod method;
  final VoidCallback onDelete;
  const _MethodDetail({required this.method, required this.onDelete});

  @override
  State<_MethodDetail> createState() => _MethodDetailState();
}

class _MethodDetailState extends State<_MethodDetail> {
  late List<PaymentMethodField> _fields;
  late Map<String, TextEditingController> _valueControllers;
  bool _editingFields = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _initFromMethod();
  }

  @override
  void didUpdateWidget(covariant _MethodDetail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.method.id != widget.method.id) {
      _disposeControllers();
      _initFromMethod();
    }
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  void _initFromMethod() {
    _fields = widget.method.fields
        .map((f) => PaymentMethodField(
              id: f.id,
              fieldKey: f.fieldKey,
              label: f.label,
              fieldType: f.fieldType,
              required: f.required,
              sortOrder: f.sortOrder,
            ))
        .toList();
    _valueControllers = {};
    for (final f in widget.method.fields) {
      _valueControllers[f.fieldKey] = TextEditingController(
        text: widget.method.values[f.fieldKey] ?? '',
      );
    }
    _editingFields = false;
  }

  void _disposeControllers() {
    for (final c in _valueControllers.values) {
      c.dispose();
    }
  }

  Future<void> _saveValues() async {
    setState(() => _saving = true);
    final values = <String, String>{};
    _valueControllers.forEach((key, ctrl) {
      values[key] = ctrl.text.trim();
    });
    try {
      await Database.instance
          .savePaymentMethodValues(widget.method.id, values);
      if (mounted) {
        showSuccessSnack(context, 'Datos guardados');
      }
    } catch (e) {
      if (mounted) showErrorSnack(context, 'Error: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveFields() async {
    setState(() => _saving = true);
    try {
      await Database.instance.savePaymentMethodFields(
        widget.method.id,
        _fields,
      );
      if (mounted) {
        setState(() => _editingFields = false);
        showSuccessSnack(context, 'Campos actualizados');
      }
    } catch (e) {
      if (mounted) showErrorSnack(context, 'Error: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addField() async {
    final result = await showDialog<PaymentMethodField>(
      context: context,
      builder: (ctx) => const _FieldEditDialog(),
    );
    if (result == null) return;
    setState(() {
      _fields.add(result);
    });
  }

  Future<void> _editField(int index) async {
    final result = await showDialog<PaymentMethodField>(
      context: context,
      builder: (ctx) => _FieldEditDialog(initial: _fields[index]),
    );
    if (result == null) return;
    setState(() {
      _fields[index] = result;
    });
  }

  void _removeField(int index) {
    setState(() {
      _fields.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(DS.space5),
      children: [
        // Header
        Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: DS.brandBlue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(DS.radiusMd),
              ),
              child: Icon(PaymentMethod.iconFor(widget.method.icon),
                  color: DS.brandBlue, size: 22),
            ),
            const SizedBox(width: DS.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.method.name,
                      style: DS.display(22, weight: FontWeight.w500)),
                  Text(
                    widget.method.active ? 'Activo' : 'Inactivo',
                    style: DS.ui(11,
                        color: widget.method.active
                            ? DS.success
                            : DS.inkMuted,
                        weight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  color: DS.danger, size: 20),
              onPressed: widget.onDelete,
              tooltip: 'Eliminar método',
            ),
          ],
        ),
        const SizedBox(height: DS.space5),

        // ============ SECCIÓN: VALORES ============
        Container(
          padding: const EdgeInsets.all(DS.space4),
          decoration: BoxDecoration(
            color: DS.surfaceRaised,
            borderRadius: BorderRadius.circular(DS.radiusLg),
            border: Border.all(color: DS.border, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('DATOS PARA EL PAGO', style: DS.eyebrow()),
                        const SizedBox(height: 2),
                        Text(
                          'Lo que verá la empresa al pagar',
                          style: DS.ui(12, color: DS.inkMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: DS.space4),
              if (_fields.isEmpty)
                Container(
                  padding: const EdgeInsets.all(DS.space4),
                  decoration: BoxDecoration(
                    color: DS.surfaceMuted,
                    borderRadius: BorderRadius.circular(DS.radiusSm),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline,
                          color: DS.inkMuted, size: 16),
                      const SizedBox(width: DS.space3),
                      Expanded(
                        child: Text(
                          'Este método aún no tiene campos. Agrega los que necesites en la sección de abajo.',
                          style: DS.ui(12,
                              color: DS.inkSecondary, height: 1.5),
                        ),
                      ),
                    ],
                  ),
                )
              else ...[
                for (final f in _fields) ...[
                  _ValueField(
                    field: f,
                    controller: _valueControllers[f.fieldKey] ??=
                        TextEditingController(),
                  ),
                  const SizedBox(height: DS.space3),
                ],
                const SizedBox(height: DS.space2),
                ElevatedButton.icon(
                  onPressed: _saving ? null : _saveValues,
                  icon: _saving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save_outlined, size: 16),
                  label: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child:
                        Text(_saving ? 'Guardando...' : 'Guardar datos'),
                  ),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: DS.space5),

        // ============ SECCIÓN: CAMPOS (estructura) ============
        Container(
          padding: const EdgeInsets.all(DS.space4),
          decoration: BoxDecoration(
            color: DS.surfaceRaised,
            borderRadius: BorderRadius.circular(DS.radiusLg),
            border: Border.all(color: DS.border, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('CAMPOS DEL MÉTODO', style: DS.eyebrow()),
                        const SizedBox(height: 2),
                        Text(
                          'Define qué información pedir',
                          style: DS.ui(12, color: DS.inkMuted),
                        ),
                      ],
                    ),
                  ),
                  if (!_editingFields)
                    TextButton.icon(
                      onPressed: () => setState(() => _editingFields = true),
                      icon: const Icon(Icons.edit_outlined, size: 14),
                      label: const Text('Editar'),
                    ),
                ],
              ),
              const SizedBox(height: DS.space3),
              if (_fields.isEmpty && !_editingFields)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: DS.space4),
                  child: Center(
                    child: TextButton.icon(
                      onPressed: () => setState(() => _editingFields = true),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Definir campos'),
                    ),
                  ),
                )
              else
                for (var i = 0; i < _fields.length; i++) ...[
                  _FieldRow(
                    field: _fields[i],
                    editing: _editingFields,
                    onEdit: () => _editField(i),
                    onRemove: () => _removeField(i),
                  ),
                  if (i < _fields.length - 1)
                    const Divider(height: 1, color: DS.border),
                ],
              if (_editingFields) ...[
                const SizedBox(height: DS.space3),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _addField,
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Agregar campo'),
                      ),
                    ),
                    const SizedBox(width: DS.space2),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _saving ? null : _saveFields,
                        icon: _saving
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white))
                            : const Icon(Icons.check, size: 16),
                        label: Text(_saving ? 'Guardando...' : 'Guardar'),
                      ),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _initFromMethod();
                    });
                  },
                  child: const Text('Cancelar cambios'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ============ FILA DE UN CAMPO ============
class _FieldRow extends StatelessWidget {
  final PaymentMethodField field;
  final bool editing;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  const _FieldRow({
    required this.field,
    required this.editing,
    required this.onEdit,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DS.space3),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: DS.surfaceMuted,
              borderRadius: BorderRadius.circular(DS.radiusSm),
            ),
            child: Icon(
              _iconFor(field.fieldType),
              color: DS.inkMuted,
              size: 14,
            ),
          ),
          const SizedBox(width: DS.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(field.label,
                        style: DS.ui(13, weight: FontWeight.w600)),
                    if (field.required) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: DS.danger.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(DS.radiusSm),
                        ),
                        child: Text('Obligatorio',
                            style: DS.ui(9,
                                color: DS.danger,
                                weight: FontWeight.w700)),
                      ),
                    ],
                  ],
                ),
                Text(
                  '${field.fieldKey} · ${field.fieldType.label}',
                  style: DS.ui(11, color: DS.inkMuted),
                ),
              ],
            ),
          ),
          if (editing) ...[
            IconButton(
              icon: const Icon(Icons.edit_outlined,
                  color: DS.inkMuted, size: 16),
              onPressed: onEdit,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  color: DS.danger, size: 16),
              onPressed: onRemove,
            ),
          ],
        ],
      ),
    );
  }

  IconData _iconFor(PaymentFieldType type) {
    switch (type) {
      case PaymentFieldType.number:
        return Icons.numbers;
      case PaymentFieldType.phone:
        return Icons.phone;
      case PaymentFieldType.text:
        return Icons.short_text;
    }
  }
}

// ============ INPUT DE UN VALOR ============
class _ValueField extends StatelessWidget {
  final PaymentMethodField field;
  final TextEditingController controller;
  const _ValueField({required this.field, required this.controller});

  @override
  Widget build(BuildContext context) {
    TextInputType keyboard;
    switch (field.fieldType) {
      case PaymentFieldType.number:
        keyboard = const TextInputType.numberWithOptions(decimal: true);
        break;
      case PaymentFieldType.phone:
        keyboard = TextInputType.phone;
        break;
      case PaymentFieldType.text:
        keyboard = TextInputType.text;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              Text(field.label,
                  style: DS.ui(12, weight: FontWeight.w600)),
              if (field.required) ...[
                const SizedBox(width: 4),
                Text('*',
                    style: DS.ui(12,
                        color: DS.danger, weight: FontWeight.w700)),
              ],
            ],
          ),
        ),
        TextField(
          controller: controller,
          keyboardType: keyboard,
          decoration: InputDecoration(
            hintText: field.label,
          ),
        ),
      ],
    );
  }
}

// ============ DIALOG: AGREGAR MÉTODO ============
class _AddMethodDialog extends StatefulWidget {
  const _AddMethodDialog();

  @override
  State<_AddMethodDialog> createState() => _AddMethodDialogState();
}

class _AddMethodDialogState extends State<_AddMethodDialog> {
  final _name = TextEditingController();
  String _icon = 'payment';

  static const _icons = [
    ('payment', 'Pago genérico', Icons.payment),
    ('payments', 'Efectivo', Icons.payments),
    ('account_balance', 'Banco', Icons.account_balance),
    ('phone_android', 'Móvil', Icons.phone_android),
    ('credit_card', 'Tarjeta', Icons.credit_card),
    ('attach_money', 'Dólar', Icons.attach_money),
    ('qr_code', 'QR', Icons.qr_code),
  ];

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Nuevo método de pago', style: DS.display(20)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Nombre', style: DS.ui(12, weight: FontWeight.w600)),
          const SizedBox(height: 4),
          TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Ej: Pago móvil, Zelle, Bs',
            ),
          ),
          const SizedBox(height: DS.space3),
          Text('Icono', style: DS.ui(12, weight: FontWeight.w600)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _icons.map((tuple) {
              final key = tuple.$1;
              final icon = tuple.$3;
              final isSelected = _icon == key;
              return InkWell(
                onTap: () => setState(() => _icon = key),
                borderRadius: BorderRadius.circular(DS.radiusSm),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? DS.brandOrange.withValues(alpha: 0.15)
                        : DS.surfaceMuted,
                    border: Border.all(
                      color: isSelected ? DS.brandOrange : DS.border,
                      width: isSelected ? 1.5 : 1,
                    ),
                    borderRadius: BorderRadius.circular(DS.radiusSm),
                  ),
                  child: Icon(icon,
                      color: isSelected ? DS.brandOrange : DS.inkMuted,
                      size: 18),
                ),
              );
            }).toList(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () {
            final n = _name.text.trim();
            if (n.isEmpty) return;
            Navigator.pop(context, (name: n, icon: _icon));
          },
          child: const Text('Crear'),
        ),
      ],
    );
  }
}

// ============ DIALOG: AGREGAR/EDITAR CAMPO ============
class _FieldEditDialog extends StatefulWidget {
  final PaymentMethodField? initial;
  const _FieldEditDialog({this.initial});

  @override
  State<_FieldEditDialog> createState() => _FieldEditDialogState();
}

class _FieldEditDialogState extends State<_FieldEditDialog> {
  late final TextEditingController _label;
  late final TextEditingController _key;
  PaymentFieldType _type = PaymentFieldType.text;
  bool _required = true;
  bool _isNew = false;

  @override
  void initState() {
    super.initState();
    _isNew = widget.initial == null;
    _label = TextEditingController(text: widget.initial?.label ?? '');
    _key = TextEditingController(text: widget.initial?.fieldKey ?? '');
    _type = widget.initial?.fieldType ?? PaymentFieldType.text;
    _required = widget.initial?.required ?? true;
  }

  @override
  void dispose() {
    _label.dispose();
    _key.dispose();
    super.dispose();
  }

  String _slug(String label) {
    final lc = label.toLowerCase().trim();
    final clean = lc
        .replaceAll(RegExp(r'[áàä]'), 'a')
        .replaceAll(RegExp(r'[éèë]'), 'e')
        .replaceAll(RegExp(r'[íìï]'), 'i')
        .replaceAll(RegExp(r'[óòö]'), 'o')
        .replaceAll(RegExp(r'[úùü]'), 'u')
        .replaceAll(RegExp(r'[ñ]'), 'n')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return clean.isEmpty ? 'campo' : clean;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isNew ? 'Nuevo campo' : 'Editar campo',
          style: DS.display(20)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Etiqueta', style: DS.ui(12, weight: FontWeight.w600)),
            const SizedBox(height: 4),
            TextField(
              controller: _label,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Ej: Banco, Cédula, Número de cuenta',
              ),
              onChanged: (v) {
                if (_isNew) {
                  _key.text = _slug(v);
                }
              },
            ),
            const SizedBox(height: DS.space3),
            Text('Identificador interno (sin espacios)',
                style: DS.ui(12, weight: FontWeight.w600)),
            const SizedBox(height: 4),
            TextField(
              controller: _key,
              enabled: _isNew,
              decoration: const InputDecoration(hintText: 'banco, cuenta...'),
            ),
            const SizedBox(height: DS.space3),
            Text('Tipo de dato', style: DS.ui(12, weight: FontWeight.w600)),
            const SizedBox(height: 4),
            DropdownButtonFormField<PaymentFieldType>(
              initialValue: _type,
              items: PaymentFieldType.values
                  .map((t) => DropdownMenuItem(
                        value: t,
                        child: Text(t.label),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _type = v);
              },
            ),
            const SizedBox(height: DS.space2),
            CheckboxListTile(
              value: _required,
              title: Text('Obligatorio',
                  style: DS.ui(13, weight: FontWeight.w500)),
              subtitle: Text(
                'La empresa debe ver este dato siempre',
                style: DS.ui(11, color: DS.inkMuted),
              ),
              onChanged: (v) => setState(() => _required = v ?? true),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () {
            final label = _label.text.trim();
            final key = _key.text.trim();
            if (label.isEmpty || key.isEmpty) return;
            Navigator.pop(
              context,
              PaymentMethodField(
                id: widget.initial?.id ?? 0,
                fieldKey: key,
                label: label,
                fieldType: _type,
                required: _required,
                sortOrder: widget.initial?.sortOrder ?? 0,
              ),
            );
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
