import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/database.dart';
import '../services/gps_service.dart';
import '../services/external_apps.dart';
import '../widgets/design_system.dart';
import '../widgets/components.dart';
import '../widgets/order_map.dart';

/// Pantalla full-screen de mapa para una orden.
class OrderMapScreen extends StatefulWidget {
  final DeliveryOrder order;
  final bool showRiderLocation;
  final bool isCustomerView;

  const OrderMapScreen({
    super.key,
    required this.order,
    this.showRiderLocation = false,
    this.isCustomerView = false,
  });

  @override
  State<OrderMapScreen> createState() => _OrderMapScreenState();
}

class _OrderMapScreenState extends State<OrderMapScreen> {
  final db = Database.instance;
  final gps = GpsService.instance;

  @override
  void initState() {
    super.initState();
    db.addListener(_onChange);
    gps.addListener(_onChange);
  }

  @override
  void dispose() {
    db.removeListener(_onChange);
    gps.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  /// Abre Google Maps / Apple Maps directamente con la navegación al destino.
  /// No copia nada al portapapeles: abre la app de mapas de una vez.
  Future<void> _openNavigation(double lat, double lng, String label) async {
    try {
      final ok = await ExternalApps.navigateTo(lat, lng, label: label);
      if (!ok && mounted) {
        // Si no se pudo abrir ninguna app de mapas, avisar
        showErrorSnack(
          context,
          'No se pudo abrir la app de mapas. Verifica que tengas Google Maps instalado.',
        );
      }
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, 'No se pudo abrir el navegador: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = db.orders.firstWhere(
      (o) => o.id == widget.order.id,
      orElse: () => widget.order,
    );
    final company = db.companyById(order.companyId);
    final rider = db.riderById(order.riderId);

    RiderLocation? riderLoc;
    if (widget.showRiderLocation && order.riderId != null) {
      riderLoc = db.riderLocationById(order.riderId);
    }

    final hasLocations = order.hasPickupLocation || order.hasDropoffLocation;

    return Scaffold(
      backgroundColor: DS.surface,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.isCustomerView
                  ? 'Seguir mi pedido'
                  : 'Orden #${order.number}',
              style: DS.display(16, weight: FontWeight.w600),
            ),
            Text(company?.name ?? '—',
                style: DS.ui(11, color: DS.inkMuted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ),
        backgroundColor: DS.surfaceRaised,
        foregroundColor: DS.ink,
        elevation: 0,
        shape: const Border(bottom: BorderSide(color: DS.border)),
      ),
      body: Column(
        children: [
          // Mapa
          Expanded(
            child: hasLocations
                ? Padding(
                    padding: const EdgeInsets.all(DS.space4),
                    child: AppMap.forOrder(
                      order,
                      height: double.infinity,
                      riderLocation: riderLoc,
                    ),
                  )
                : const _NoLocationsPlaceholder(),
          ),

          // Información
          Container(
            padding: const EdgeInsets.all(DS.space5),
            decoration: const BoxDecoration(
              color: DS.surfaceRaised,
              border: Border(top: BorderSide(color: DS.border, width: 1)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _LocationRow(
                    icon: Icons.store_mall_directory,
                    color: DS.brandBlue,
                    label: 'RECOGER EN',
                    title: company?.name ?? '—',
                    address: company?.address ?? 'Sin dirección',
                    hasLocation: order.hasPickupLocation,
                    onNavigate: !widget.isCustomerView && order.hasPickupLocation
                        ? () => _openNavigation(
                              order.pickupLat!,
                              order.pickupLng!,
                              company?.name ?? 'Recogida',
                            )
                        : null,
                  ),
                  const SizedBox(height: DS.space3),
                  Container(height: 1, color: DS.border),
                  const SizedBox(height: DS.space3),
                  _LocationRow(
                    icon: Icons.flag,
                    color: DS.success,
                    label: 'ENTREGAR A',
                    title: order.customer,
                    address: order.address,
                    subtitle: order.customerPhone,
                    hasLocation: order.hasDropoffLocation,
                    onNavigate:
                        !widget.isCustomerView && order.hasDropoffLocation
                            ? () => _openNavigation(
                                  order.dropoffLat!,
                                  order.dropoffLng!,
                                  order.customer,
                                )
                            : null,
                  ),
                  if (rider != null) ...[
                    const SizedBox(height: DS.space3),
                    Container(height: 1, color: DS.border),
                    const SizedBox(height: DS.space3),
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: DS.brandOrange.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(DS.radiusSm),
                          ),
                          child: const Icon(Icons.two_wheeler,
                              color: DS.brandOrange, size: 18),
                        ),
                        const SizedBox(width: DS.space3),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.isCustomerView
                                    ? 'TU MOTORIZADO'
                                    : 'MOTORIZADO ASIGNADO',
                                style: DS.eyebrow(),
                              ),
                              Text(rider.name,
                                  style:
                                      DS.ui(13, weight: FontWeight.w600)),
                              if (riderLoc != null && riderLoc.isFresh)
                                Row(
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: const BoxDecoration(
                                        color: DS.success,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'En línea · ${DateTime.now().difference(riderLoc.updatedAt).inSeconds}s',
                                      style: DS.ui(10, color: DS.success),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoLocationsPlaceholder extends StatelessWidget {
  const _NoLocationsPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DS.space5),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: DS.inkMuted.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.location_off,
                  color: DS.inkMuted, size: 32),
            ),
            const SizedBox(height: DS.space4),
            Text('Sin ubicaciones registradas',
                style: DS.display(18, weight: FontWeight.w600)),
            const SizedBox(height: DS.space2),
            Text(
              'Esta orden aún no tiene coordenadas de recogida o entrega.',
              textAlign: TextAlign.center,
              style: DS.ui(13, color: DS.inkMuted, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String title;
  final String address;
  final String? subtitle;
  final bool hasLocation;
  final VoidCallback? onNavigate;

  const _LocationRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.title,
    required this.address,
    this.subtitle,
    required this.hasLocation,
    this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(DS.radiusSm),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: DS.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: DS.eyebrow(color: color)),
                  const SizedBox(height: 2),
                  Text(title,
                      style: DS.ui(14, weight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(address,
                      style: DS.ui(12, color: DS.inkSecondary, height: 1.4),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  if (subtitle != null)
                    Text(subtitle!,
                        style: DS.ui(11, color: DS.inkMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
        if (onNavigate != null) ...[
          const SizedBox(height: DS.space2),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onNavigate,
              icon: Icon(Icons.navigation, color: color, size: 16),
              label: Text(
                'Iniciar navegación',
                style: TextStyle(color: color),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: color.withValues(alpha: 0.4)),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
