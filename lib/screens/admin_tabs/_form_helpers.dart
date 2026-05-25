import 'package:flutter/material.dart';
import '../../widgets/design_system.dart';

/// Show a polished bottom-sheet form for creating an entity.
/// Returns true if the user pressed save and validation passed.
Future<bool> showEntityFormSheet(
  BuildContext context, {
  required String title,
  required String subtitle,
  required IconData icon,
  required Color iconColor,
  required List<Widget> Function(StateSetter setSt) buildFields,
  required void Function() onSave,
  String saveLabel = 'Guardar',
}) async {
  final formKey = GlobalKey<FormState>();
  bool saved = false;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: DS.surfaceRaised,
    barrierColor: DS.ink.withValues(alpha: 0.5),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(DS.radiusXl)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSt) => Padding(
        padding: EdgeInsets.only(
          left: DS.space5,
          right: DS.space5,
          top: DS.space5,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + DS.space5,
        ),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: DS.space4),
                  decoration: BoxDecoration(
                    color: DS.inkSubtle,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Header
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(DS.radiusMd),
                    ),
                    child: Icon(icon, color: iconColor, size: 18),
                  ),
                  const SizedBox(width: DS.space3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: DS.display(20, weight: FontWeight.w500)),
                        Text(subtitle,
                            style: DS.ui(12, color: DS.inkMuted)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    color: DS.inkMuted,
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: DS.space5),
              // Fields
              ...buildFields(setSt),
              const SizedBox(height: DS.space6),
              // Actions
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: DS.space3),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () {
                        if (!formKey.currentState!.validate()) return;
                        onSave();
                        saved = true;
                        Navigator.pop(ctx);
                      },
                      child: Text(saveLabel),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );

  return saved;
}

/// Standardized form input field with label above
class LabeledField extends StatelessWidget {
  final String label;
  final String? hint;
  final IconData? icon;
  final bool obscure;
  final TextEditingController controller;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final Widget? suffix;

  const LabeledField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.icon,
    this.obscure = false,
    this.validator,
    this.keyboardType,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DS.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: DS.ui(12, color: DS.ink, weight: FontWeight.w600)),
          const SizedBox(height: DS.space2),
          TextFormField(
            controller: controller,
            obscureText: obscure,
            keyboardType: keyboardType,
            decoration: InputDecoration(
              hintText: hint,
              prefixIcon: icon != null ? Icon(icon, size: 18) : null,
              suffixIcon: suffix,
            ),
            validator: validator,
          ),
        ],
      ),
    );
  }
}

class LabeledDropdown<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  const LabeledDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DS.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: DS.ui(12, color: DS.ink, weight: FontWeight.w600)),
          const SizedBox(height: DS.space2),
          DropdownButtonFormField<T>(
            value: value,
            items: items,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
