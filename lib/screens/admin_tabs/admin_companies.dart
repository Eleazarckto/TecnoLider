import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../services/database.dart';
import '../../widgets/design_system.dart';
import '../../widgets/components.dart';

class AdminCompanies extends StatefulWidget {
  const AdminCompanies({super.key});

  @override
  State<AdminCompanies> createState() => _AdminCompaniesState();
}

class _AdminCompaniesState extends State<AdminCompanies> {
  final db = Database.instance;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    db.addListener(_onChange);
    _search.addListener(_onChange);
  }

  @override
  void dispose() {
    db.removeListener(_onChange);
    _search.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  List<Company> get _filtered {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return db.companies;
    return db.companies
        .where((c) =>
            c.name.toLowerCase().contains(q) ||
            c.email.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final companies = _filtered;
    final payLaterCount =
        db.companies.where((c) => c.payLaterEnabled).length;

    return Column(
      children: [
        // Header con búsqueda y botón nuevo
        Padding(
          padding: const EdgeInsets.fromLTRB(
              DS.space5, DS.space5, DS.space5, DS.space3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _search,
                      decoration: const InputDecoration(
                        hintText: 'Buscar empresa…',
                        prefixIcon: Icon(Icons.search, size: 18),
                      ),
                    ),
                  ),
                  const SizedBox(width: DS.space3),
                  ElevatedButton.icon(
                    onPressed: _addCompany,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Text('Nueva empresa'),
                    ),
                  ),
                ],
              ),
              if (db.companies.isNotEmpty) ...[
                const SizedBox(height: DS.space3),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: DS.space3, vertical: DS.space2),
                  decoration: BoxDecoration(
                    color: DS.brandBlue.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(DS.radiusSm),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline,
                          color: DS.brandBlue, size: 14),
                      const SizedBox(width: DS.space2),
                      Expanded(
                        child: Text(
                          '$payLaterCount de ${db.companies.length} empresas con pago a crédito habilitado',
                          style: DS.ui(11, color: DS.brandBlue),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        // Lista
        Expanded(
          child: companies.isEmpty
              ? const EmptyState(
                  icon: Icons.apartment_outlined,
                  message: 'Sin empresas',
                  hint: 'Crea la primera empresa cliente.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                      DS.space5, 0, DS.space5, DS.space5),
                  itemCount: companies.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: DS.space3),
                  itemBuilder: (context, i) {
                    final c = companies[i];
                    return _CompanyCard(
                      company: c,
                      onTogglePayLater: () => _togglePayLater(c),
                      onSetLimit: () => _setCreditLimit(c),
                      onDelete: () => _deleteCompany(c),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _addCompany() async {
    final result = await showDialog<_CompanyFormResult>(
      context: context,
      builder: (ctx) => const _AddCompanyDialog(),
    );
    if (result == null) return;

    try {
      await db.addCompany(
        name: result.name,
        email: result.email,
        phone: result.phone,
        address: result.address,
        password: result.password,
      );
      if (mounted) {
        showSuccessSnack(context, 'Empresa "${result.name}" creada');
      }
    } catch (e) {
      if (mounted) showErrorSnack(context, 'Error: $e');
    }
  }

  Future<void> _togglePayLater(Company c) async {
    try {
      await db.setCompanyPayLater(c.id, enabled: !c.payLaterEnabled);
      if (mounted) {
        showSuccessSnack(
          context,
          c.payLaterEnabled
              ? '${c.name} ya no puede pagar después'
              : '${c.name} ahora puede pagar después',
        );
      }
    } catch (e) {
      if (mounted) showErrorSnack(context, 'Error: $e');
    }
  }

  Future<void> _setCreditLimit(Company c) async {
    final newLimit = await showDialog<double>(
      context: context,
      builder: (ctx) => _CreditLimitDialog(company: c),
    );
    if (newLimit == null) return;

    try {
      await db.setCompanyPayLater(
        c.id,
        enabled: c.payLaterEnabled,
        creditLimit: newLimit,
      );
      if (mounted) {
        showSuccessSnack(context,
            'Límite de crédito actualizado a ${formatMoney(newLimit)}');
      }
    } catch (e) {
      if (mounted) showErrorSnack(context, 'Error: $e');
    }
  }

  Future<void> _deleteCompany(Company c) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Eliminar empresa',
      message:
          '¿Eliminar "${c.name}"? Sus órdenes existentes se conservarán pero no podrá iniciar sesión.',
      confirmLabel: 'Eliminar',
      destructive: true,
    );
    if (!ok) return;

    try {
      await db.deleteCompany(c.id);
      if (mounted) showSuccessSnack(context, 'Empresa eliminada');
    } catch (e) {
      if (mounted) showErrorSnack(context, 'Error: $e');
    }
  }
}

// ============ COMPANY CARD ============
class _CompanyCard extends StatelessWidget {
  final Company company;
  final VoidCallback onTogglePayLater;
  final VoidCallback onSetLimit;
  final VoidCallback onDelete;

  const _CompanyCard({
    required this.company,
    required this.onTogglePayLater,
    required this.onSetLimit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final db = Database.instance;
    final ordersCount = db.ordersByCompany(company.id).length;
    final debtsCount = db.debtOrders(companyId: company.id).length;
    final debtTotal = db
        .debtOrders(companyId: company.id)
        .fold<double>(0, (s, o) => s + o.amount);

    return Container(
      decoration: BoxDecoration(
        color: DS.surfaceRaised,
        borderRadius: BorderRadius.circular(DS.radiusLg),
        border: Border.all(color: DS.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ----- Header del card -----
          Padding(
            padding: const EdgeInsets.all(DS.space4),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: DS.brandOrange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(DS.radiusMd),
                  ),
                  child: Center(
                    child: Text(
                      company.name.isNotEmpty
                          ? company.name[0].toUpperCase()
                          : '?',
                      style: DS.display(18,
                          color: DS.brandOrangeDeep,
                          weight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: DS.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(company.name,
                          style: DS.display(16, weight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(company.email,
                          style: DS.ui(11, color: DS.inkMuted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      color: DS.danger, size: 18),
                  onPressed: onDelete,
                  tooltip: 'Eliminar empresa',
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: DS.border),

          // ----- Datos generales -----
          Padding(
            padding: const EdgeInsets.all(DS.space4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (company.phone.isNotEmpty)
                  InfoRow(
                      icon: Icons.phone_outlined,
                      label: 'Teléfono',
                      value: company.phone),
                if (company.address.isNotEmpty)
                  InfoRow(
                      icon: Icons.location_on_outlined,
                      label: 'Dirección',
                      value: company.address),
                Row(
                  children: [
                    Expanded(
                      child: _Stat(
                        label: 'Órdenes',
                        value: '$ordersCount',
                        color: DS.brandBlue,
                      ),
                    ),
                    const SizedBox(width: DS.space2),
                    Expanded(
                      child: _Stat(
                        label: 'Deuda activa',
                        value: debtsCount > 0
                            ? formatMoney(debtTotal)
                            : '—',
                        color: debtsCount > 0
                            ? DS.warning
                            : DS.inkMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: DS.border),

          // ----- Sección de Pagar Después -----
          Container(
            padding: const EdgeInsets.all(DS.space4),
            decoration: BoxDecoration(
              color: company.payLaterEnabled
                  ? DS.success.withValues(alpha: 0.05)
                  : DS.surfaceMuted,
              borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(DS.radiusLg)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      company.payLaterEnabled
                          ? Icons.credit_score
                          : Icons.credit_card_off_outlined,
                      color: company.payLaterEnabled
                          ? DS.success
                          : DS.inkMuted,
                      size: 18,
                    ),
                    const SizedBox(width: DS.space3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Pago a crédito',
                              style: DS.ui(13, weight: FontWeight.w600)),
                          Text(
                            company.payLaterEnabled
                                ? 'La empresa puede pagar después'
                                : 'Solo paga al momento',
                            style: DS.ui(11, color: DS.inkMuted),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: company.payLaterEnabled,
                      onChanged: (_) => onTogglePayLater(),
                      activeThumbColor: DS.success,
                    ),
                  ],
                ),
                if (company.payLaterEnabled) ...[
                  const SizedBox(height: DS.space3),
                  Container(
                    padding: const EdgeInsets.all(DS.space3),
                    decoration: BoxDecoration(
                      color: DS.surfaceRaised,
                      borderRadius: BorderRadius.circular(DS.radiusSm),
                      border:
                          Border.all(color: DS.border, width: 1),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.account_balance_wallet_outlined,
                            color: DS.inkMuted, size: 16),
                        const SizedBox(width: DS.space3),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Límite de crédito',
                                  style: DS.ui(11,
                                      color: DS.inkMuted)),
                              Text(
                                company.creditLimit > 0
                                    ? formatMoney(company.creditLimit)
                                    : 'Sin límite',
                                style: DS.numeric(14,
                                    weight: FontWeight.w700,
                                    color: company.creditLimit > 0
                                        ? DS.brandBlue
                                        : DS.inkSecondary),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: onSetLimit,
                          child: const Text('Cambiar'),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Stat(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: DS.space3, vertical: DS.space3),
      decoration: BoxDecoration(
        color: DS.surfaceMuted,
        borderRadius: BorderRadius.circular(DS.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: DS.eyebrow()),
          const SizedBox(height: 2),
          Text(value,
              style: DS.numeric(14,
                  color: color, weight: FontWeight.w700)),
        ],
      ),
    );
  }
}

// ============ DIALOG: NUEVA EMPRESA ============
class _CompanyFormResult {
  final String name;
  final String email;
  final String phone;
  final String address;
  final String password;
  _CompanyFormResult(
      this.name, this.email, this.phone, this.address, this.password);
}

class _AddCompanyDialog extends StatefulWidget {
  const _AddCompanyDialog();

  @override
  State<_AddCompanyDialog> createState() => _AddCompanyDialogState();
}

class _AddCompanyDialogState extends State<_AddCompanyDialog> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _password = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _address.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Nueva empresa', style: DS.display(20)),
      content: Form(
        key: _formKey,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nombre'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: DS.space3),
              TextFormField(
                controller: _email,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Requerido';
                  if (!v.contains('@')) return 'Email inválido';
                  return null;
                },
              ),
              const SizedBox(height: DS.space3),
              TextFormField(
                controller: _phone,
                decoration: const InputDecoration(labelText: 'Teléfono'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: DS.space3),
              TextFormField(
                controller: _address,
                decoration: const InputDecoration(labelText: 'Dirección'),
              ),
              const SizedBox(height: DS.space3),
              TextFormField(
                controller: _password,
                decoration: const InputDecoration(
                  labelText: 'Contraseña inicial',
                  helperText: 'La empresa la usará para iniciar sesión',
                ),
                obscureText: true,
                validator: (v) =>
                    (v == null || v.length < 4) ? 'Mínimo 4 caracteres' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(
                context,
                _CompanyFormResult(
                  _name.text.trim(),
                  _email.text.trim(),
                  _phone.text.trim(),
                  _address.text.trim(),
                  _password.text,
                ),
              );
            }
          },
          child: const Text('Crear'),
        ),
      ],
    );
  }
}

// ============ DIALOG: LÍMITE DE CRÉDITO ============
class _CreditLimitDialog extends StatefulWidget {
  final Company company;
  const _CreditLimitDialog({required this.company});

  @override
  State<_CreditLimitDialog> createState() => _CreditLimitDialogState();
}

class _CreditLimitDialogState extends State<_CreditLimitDialog> {
  late final TextEditingController _amount;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(
      text: widget.company.creditLimit > 0
          ? widget.company.creditLimit.toStringAsFixed(2)
          : '',
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final db = Database.instance;
    return AlertDialog(
      title: Text('Límite de crédito', style: DS.display(20)),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Configura el monto máximo de deuda que puede acumular ${widget.company.name}.',
              style: DS.ui(12, color: DS.inkSecondary, height: 1.5),
            ),
            const SizedBox(height: DS.space4),
            TextFormField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Monto máximo (${db.config.currency})',
                hintText: '0 para sin límite',
                prefixText: '${db.config.currencySymbol} ',
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return null;
                final n = double.tryParse(v);
                if (n == null || n < 0) return 'Monto inválido';
                return null;
              },
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
            if (_formKey.currentState!.validate()) {
              final v = double.tryParse(_amount.text) ?? 0;
              Navigator.pop(context, v);
            }
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
