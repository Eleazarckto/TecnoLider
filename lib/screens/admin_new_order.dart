import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/database.dart';
import '../widgets/design_system.dart';
import '../widgets/components.dart';
import 'company_screen.dart' show NewOrderTab;

/// Pantalla para que admin u operador cree orden a nombre de cualquier empresa.
/// Muestra primero un selector de empresa, luego reutiliza el formulario
/// completo de NewOrderTab (con mapa, pickup, dropoff, autocotizacion).
class AdminNewOrderScreen extends StatefulWidget {
  const AdminNewOrderScreen({super.key});

  @override
  State<AdminNewOrderScreen> createState() => _AdminNewOrderScreenState();
}

class _AdminNewOrderScreenState extends State<AdminNewOrderScreen> {
  Company? _selectedCompany;
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedCompany != null) {
      return _buildFormForCompany(_selectedCompany!);
    }
    return _buildCompanySelector();
  }

  Widget _buildCompanySelector() {
    final all = Database.instance.companies
        .where((c) => c.active)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    final query = _searchCtrl.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? all
        : all.where((c) =>
            c.name.toLowerCase().contains(query) ||
            (c.phone).toLowerCase().contains(query)).toList();

    return ListView(
      padding: const EdgeInsets.all(DS.space6),
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(DS.space5),
          decoration: BoxDecoration(
            color: DS.brandBlue.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(DS.radiusLg),
            border: Border.all(
                color: DS.brandBlue.withValues(alpha: 0.2), width: 1),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: DS.brandBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(DS.radiusMd),
                ),
                child: const Icon(Icons.add_business,
                    color: DS.brandBlue, size: 22),
              ),
              const SizedBox(width: DS.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('CREAR ORDEN A NOMBRE DE...',
                        style: DS.eyebrow(color: DS.brandBlue)),
                    const SizedBox(height: 2),
                    Text('Selecciona la empresa para la cual creas la orden',
                        style: DS.ui(13,
                            color: DS.inkSecondary, height: 1.5)),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: DS.space4),

        // Buscador
        TextFormField(
          controller: _searchCtrl,
          decoration: const InputDecoration(
            hintText: 'Buscar empresa por nombre o teléfono...',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (_) => setState(() {}),
        ),

        const SizedBox(height: DS.space4),

        if (filtered.isEmpty)
          Container(
            padding: const EdgeInsets.all(DS.space5),
            decoration: BoxDecoration(
              color: DS.surfaceMuted,
              borderRadius: BorderRadius.circular(DS.radiusMd),
            ),
            child: Column(
              children: [
                const Icon(Icons.business_outlined,
                    color: DS.inkMuted, size: 32),
                const SizedBox(height: DS.space2),
                Text(
                  query.isEmpty
                      ? 'No hay empresas activas'
                      : 'Sin coincidencias para "$query"',
                  style: DS.ui(13, color: DS.inkMuted),
                ),
              ],
            ),
          )
        else
          ...filtered.map((c) => Padding(
                padding: const EdgeInsets.only(bottom: DS.space2),
                child: _CompanyOption(
                  company: c,
                  onTap: () => setState(() => _selectedCompany = c),
                ),
              )),
      ],
    );
  }

  Widget _buildFormForCompany(Company company) {
    return Column(
      children: [
        // Header con la empresa seleccionada + boton cambiar
        Container(
          padding: const EdgeInsets.all(DS.space4),
          decoration: const BoxDecoration(
            color: DS.surfaceRaised,
            border: Border(bottom: BorderSide(color: DS.border, width: 1)),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: DS.brandBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(DS.radiusSm),
                ),
                child: const Icon(Icons.business,
                    color: DS.brandBlue, size: 18),
              ),
              const SizedBox(width: DS.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('CREANDO ORDEN PARA',
                        style: DS.eyebrow(color: DS.brandBlue)),
                    const SizedBox(height: 2),
                    Text(company.name,
                        style: DS.ui(15, weight: FontWeight.w700)),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: () => setState(() => _selectedCompany = null),
                icon: const Icon(Icons.swap_horiz, size: 16),
                label: const Text('Cambiar'),
              ),
            ],
          ),
        ),
        // El formulario completo de nueva orden
        Expanded(child: NewOrderTab(company: company)),
      ],
    );
  }
}

/// Item de empresa en la lista de seleccion
class _CompanyOption extends StatelessWidget {
  final Company company;
  final VoidCallback onTap;

  const _CompanyOption({required this.company, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasLocation = company.hasLocation;

    return Material(
      color: DS.surfaceRaised,
      borderRadius: BorderRadius.circular(DS.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DS.radiusMd),
        child: Container(
          padding: const EdgeInsets.all(DS.space3),
          decoration: BoxDecoration(
            border: Border.all(color: DS.border, width: 1),
            borderRadius: BorderRadius.circular(DS.radiusMd),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: DS.brandBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(DS.radiusSm),
                ),
                child: const Icon(Icons.store,
                    color: DS.brandBlue, size: 18),
              ),
              const SizedBox(width: DS.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(company.name,
                        style: DS.ui(14, weight: FontWeight.w600)),
                    if (company.phone.isNotEmpty)
                      Text(company.phone,
                          style: DS.ui(11, color: DS.inkMuted)),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          hasLocation
                              ? Icons.check_circle
                              : Icons.warning_amber_rounded,
                          size: 12,
                          color:
                              hasLocation ? DS.success : DS.warning,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          hasLocation
                              ? 'Sede configurada'
                              : 'Sin sede (deberás marcarla)',
                          style: DS.ui(10,
                              color: hasLocation ? DS.success : DS.warning,
                              weight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  color: DS.inkMuted, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
