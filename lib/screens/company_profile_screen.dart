import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../models/models.dart';
import '../services/database.dart';
import '../widgets/design_system.dart';
import '../widgets/components.dart';
import '../widgets/order_map.dart';
import '../widgets/location_picker.dart';

/// Pantalla del perfil de la empresa.
/// Permite configurar la ubicación de la sede que se usará como
/// punto de recogida por defecto en las órdenes.
class CompanyProfileScreen extends StatefulWidget {
  const CompanyProfileScreen({super.key});

  @override
  State<CompanyProfileScreen> createState() => _CompanyProfileScreenState();
}

class _CompanyProfileScreenState extends State<CompanyProfileScreen> {
  final db = Database.instance;
  bool _saving = false;

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

  Future<void> _pickLocation(Company company) async {
    final result = await Navigator.push<LocationResult>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => LocationPickerScreen(
          title: 'Ubicación de mi sede',
          subtitle: 'Punto de recogida por defecto',
          initialPosition: company.hasLocation
              ? LatLng(company.latitude!, company.longitude!)
              : null,
          markerColor: DS.brandBlue,
          markerIcon: Icons.store_mall_directory,
        ),
      ),
    );

    if (result == null) return;

    setState(() => _saving = true);
    try {
      await db.setCompanyCoords(
        company.id,
        latitude: result.latitude,
        longitude: result.longitude,
      );
      if (!mounted) return;
      showSuccessSnack(context, '✓ Ubicación de sede guardada');
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, 'Error: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = db.currentUser!;
    final company = db.companyById(user.linkedEntityId);
    if (company == null) {
      return const Center(
        child: Text('Empresa no encontrada',
            style: TextStyle(color: DS.inkMuted)),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(DS.space5),
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(DS.space5),
          decoration: BoxDecoration(
            color: DS.surfaceRaised,
            borderRadius: BorderRadius.circular(DS.radiusLg),
            border: Border.all(color: DS.border, width: 1),
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: DS.brandBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(DS.radiusMd),
                ),
                child: Center(
                  child: Text(
                    company.name.isNotEmpty
                        ? company.name[0].toUpperCase()
                        : '?',
                    style: DS.display(22,
                        color: DS.brandBlue, weight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: DS.space4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(company.name,
                        style: DS.display(18, weight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    Text(company.email,
                        style: DS.ui(12, color: DS.inkMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    if (company.phone.isNotEmpty)
                      Text(company.phone,
                          style: DS.ui(12, color: DS.inkMuted)),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: DS.space5),

        // Sección de ubicación
        Container(
          decoration: BoxDecoration(
            color: DS.surfaceRaised,
            borderRadius: BorderRadius.circular(DS.radiusLg),
            border: Border.all(
              color: company.hasLocation
                  ? DS.success.withValues(alpha: 0.3)
                  : DS.warning.withValues(alpha: 0.3),
              width: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header del card
              Container(
                padding: const EdgeInsets.all(DS.space4),
                decoration: BoxDecoration(
                  color: (company.hasLocation ? DS.success : DS.warning)
                      .withValues(alpha: 0.06),
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(DS.radiusLg)),
                ),
                child: Row(
                  children: [
                    Icon(
                      company.hasLocation
                          ? Icons.check_circle
                          : Icons.warning_amber_rounded,
                      color:
                          company.hasLocation ? DS.success : DS.warning,
                      size: 20,
                    ),
                    const SizedBox(width: DS.space3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            company.hasLocation
                                ? 'UBICACIÓN CONFIGURADA'
                                : 'UBICACIÓN PENDIENTE',
                            style: DS.eyebrow(
                              color: company.hasLocation
                                  ? DS.success
                                  : DS.warning,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            company.hasLocation
                                ? 'Las órdenes usarán este punto como origen'
                                : 'Configura tu sede para mejorar las entregas',
                            style: DS.ui(13,
                                color: DS.ink, weight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Contenido
              Padding(
                padding: const EdgeInsets.all(DS.space4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Esta ubicación se usará automáticamente como punto de recogida cuando crees nuevas órdenes. El motorizado y la central podrán ver dónde recoger los paquetes.',
                      style:
                          DS.ui(12, color: DS.inkSecondary, height: 1.6),
                    ),
                    const SizedBox(height: DS.space4),

                    // Dirección registrada
                    Container(
                      padding: const EdgeInsets.all(DS.space3),
                      decoration: BoxDecoration(
                        color: DS.surfaceMuted,
                        borderRadius: BorderRadius.circular(DS.radiusSm),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.location_on_outlined,
                              color: DS.inkMuted, size: 16),
                          const SizedBox(width: DS.space2),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('DIRECCIÓN REGISTRADA',
                                    style: DS.eyebrow()),
                                const SizedBox(height: 2),
                                Text(company.address,
                                    style: DS.ui(13,
                                        weight: FontWeight.w500)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Mapa preview si hay coords
                    if (company.hasLocation) ...[
                      const SizedBox(height: DS.space4),
                      AppMap(
                        markers: [
                          MapMarker(
                            point: LatLng(
                                company.latitude!, company.longitude!),
                            label: company.name,
                            icon: Icons.store_mall_directory,
                            color: DS.brandBlue,
                          ),
                        ],
                        height: 200,
                        initialZoom: 16,
                      ),
                      const SizedBox(height: DS.space2),
                      Row(
                        children: [
                          const Icon(Icons.gps_fixed,
                              color: DS.inkMuted, size: 12),
                          const SizedBox(width: 4),
                          Text(
                            '${company.latitude!.toStringAsFixed(5)}, ${company.longitude!.toStringAsFixed(5)}',
                            style: DS.numeric(11,
                                color: DS.inkMuted,
                                weight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: DS.space4),

                    // Botón
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed:
                            _saving ? null : () => _pickLocation(company),
                        icon: _saving
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : Icon(
                                company.hasLocation
                                    ? Icons.edit_location_alt
                                    : Icons.add_location_alt,
                                size: 16),
                        label: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(_saving
                              ? 'Guardando...'
                              : company.hasLocation
                                  ? 'Cambiar ubicación'
                                  : 'Configurar ubicación'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: DS.space5),

        // Info adicional
        Container(
          padding: const EdgeInsets.all(DS.space4),
          decoration: BoxDecoration(
            color: DS.infoBg,
            borderRadius: BorderRadius.circular(DS.radiusSm),
            border: Border.all(
                color: DS.info.withValues(alpha: 0.2), width: 1),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, color: DS.info, size: 16),
              const SizedBox(width: DS.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('SOBRE LA UBICACIÓN',
                        style: DS.eyebrow(color: DS.info)),
                    const SizedBox(height: 4),
                    Text(
                      'Solo se usa para indicarle al motorizado dónde recoger el paquete. No se comparte con clientes ni con otras empresas. Puedes cambiarla en cualquier momento.',
                      style:
                          DS.ui(12, color: DS.info, height: 1.5),
                    ),
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
