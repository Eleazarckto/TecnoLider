import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/models.dart';
import '../services/database.dart';
import '../services/eta_service.dart';
import '../services/external_apps.dart';
import '../widgets/design_system.dart';
import '../widgets/components.dart';

/// Mapa estilo Yummy: tracking en tiempo real para el cliente.
/// Vista full-screen con bottom sheet expandible.
class CustomerTrackingScreen extends StatefulWidget {
  final DeliveryOrder order;

  const CustomerTrackingScreen({super.key, required this.order});

  @override
  State<CustomerTrackingScreen> createState() => _CustomerTrackingScreenState();
}

class _CustomerTrackingScreenState extends State<CustomerTrackingScreen>
    with TickerProviderStateMixin {
  final db = Database.instance;
  final MapController _mapCtrl = MapController();

  // Animación del marcador del motorizado
  LatLng? _animatedRiderPos;
  AnimationController? _animController;
  LatLng? _lastRiderPos;

  @override
  void initState() {
    super.initState();
    db.addListener(_onChange);
  }

  @override
  void dispose() {
    db.removeListener(_onChange);
    _animController?.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) {
      _maybeAnimateRider();
      setState(() {});
    }
  }

  /// Anima suavemente al marcador del motorizado entre posiciones
  void _maybeAnimateRider() {
    final order = _currentOrder();
    if (order.riderId == null) return;
    final loc = db.riderLocationById(order.riderId);
    if (loc == null) return;
    final newPos = LatLng(loc.latitude, loc.longitude);
    if (_lastRiderPos == null) {
      _animatedRiderPos = newPos;
      _lastRiderPos = newPos;
      return;
    }
    if (_lastRiderPos == newPos) return;

    _animController?.dispose();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    final from = _lastRiderPos!;
    final to = newPos;
    final tween = Tween<double>(begin: 0, end: 1);
    final anim = tween.animate(CurvedAnimation(
      parent: _animController!,
      curve: Curves.easeInOut,
    ));
    anim.addListener(() {
      final t = anim.value;
      final lat = from.latitude + (to.latitude - from.latitude) * t;
      final lng = from.longitude + (to.longitude - from.longitude) * t;
      if (mounted) setState(() => _animatedRiderPos = LatLng(lat, lng));
    });
    _animController!.forward();
    _lastRiderPos = newPos;
  }

  DeliveryOrder _currentOrder() {
    return db.orders.firstWhere(
      (o) => o.id == widget.order.id,
      orElse: () => widget.order,
    );
  }

  /// Calcula ETA del motorizado al destino del cliente
  int? _calculateEta(DeliveryOrder order, RiderLocation? riderLoc) {
    if (riderLoc == null) return null;
    if (!order.hasDropoffLocation) return null;

    // Si el motorizado no ha recogido, ETA = a la empresa + al cliente
    if (order.status == OrderStatus.assigned && order.hasPickupLocation) {
      final dToPickup = EtaService.distanceKm(
        riderLoc.latitude,
        riderLoc.longitude,
        order.pickupLat!,
        order.pickupLng!,
      );
      final dToDropoff = EtaService.distanceKm(
        order.pickupLat!,
        order.pickupLng!,
        order.dropoffLat!,
        order.dropoffLng!,
      );
      return EtaService.etaMinutes(dToPickup + dToDropoff);
    }
    // Si está en tránsito, ETA = directo al cliente
    if (order.status == OrderStatus.inTransit) {
      final d = EtaService.distanceKm(
        riderLoc.latitude,
        riderLoc.longitude,
        order.dropoffLat!,
        order.dropoffLng!,
      );
      return EtaService.etaMinutes(d);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final order = _currentOrder();
    final rider = db.riderById(order.riderId);
    final company = db.companyById(order.companyId);
    final riderLoc = order.riderId != null
        ? db.riderLocationById(order.riderId)
        : null;

    final eta = _calculateEta(order, riderLoc);

    // Centro del mapa: motorizado si está, sino punto medio entre origen y destino
    LatLng mapCenter;
    if (_animatedRiderPos != null) {
      mapCenter = _animatedRiderPos!;
    } else if (order.hasBothLocations) {
      mapCenter = LatLng(
        (order.pickupLat! + order.dropoffLat!) / 2,
        (order.pickupLng! + order.dropoffLng!) / 2,
      );
    } else if (order.hasDropoffLocation) {
      mapCenter = LatLng(order.dropoffLat!, order.dropoffLng!);
    } else {
      mapCenter = const LatLng(10.4806, -66.9036);
    }

    return Scaffold(
      backgroundColor: DS.surface,
      body: Stack(
        children: [
          // MAPA FULL-SCREEN
          FlutterMap(
            mapController: _mapCtrl,
            options: MapOptions(
              initialCenter: mapCenter,
              initialZoom: 14.5,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.yj.delivery',
                maxZoom: 19,
              ),
              // Línea entre origen y destino
              if (order.hasBothLocations)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: [
                        LatLng(order.pickupLat!, order.pickupLng!),
                        LatLng(order.dropoffLat!, order.dropoffLng!),
                      ],
                      color: DS.brandOrange.withValues(alpha: 0.6),
                      strokeWidth: 4,
                    ),
                  ],
                ),
              // Marcadores
              MarkerLayer(
                markers: [
                  if (order.hasPickupLocation)
                    Marker(
                      point: LatLng(order.pickupLat!, order.pickupLng!),
                      width: 100,
                      height: 56,
                      alignment: Alignment.topCenter,
                      child: _MarkerBubble(
                        icon: Icons.store,
                        color: DS.brandBlue,
                        label: 'Recogida',
                      ),
                    ),
                  if (order.hasDropoffLocation)
                    Marker(
                      point: LatLng(order.dropoffLat!, order.dropoffLng!),
                      width: 100,
                      height: 56,
                      alignment: Alignment.topCenter,
                      child: _MarkerBubble(
                        icon: Icons.home,
                        color: DS.success,
                        label: 'Entrega',
                      ),
                    ),
                  if (_animatedRiderPos != null)
                    Marker(
                      point: _animatedRiderPos!,
                      width: 64,
                      height: 64,
                      alignment: Alignment.center,
                      child: _RiderMarker(rider: rider),
                    ),
                ],
              ),
            ],
          ),

          // BOTÓN VOLVER (superior izquierda)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(DS.space3),
                child: Row(
                  children: [
                    _MapTopButton(
                      icon: Icons.arrow_back,
                      onTap: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    // Centrar en motorizado
                    if (_animatedRiderPos != null)
                      _MapTopButton(
                        icon: Icons.my_location,
                        onTap: () =>
                            _mapCtrl.move(_animatedRiderPos!, 16),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // BOTTOM SHEET con info del pedido
          DraggableScrollableSheet(
            initialChildSize: 0.32,
            minChildSize: 0.15,
            maxChildSize: 0.85,
            builder: (context, scrollController) {
              return Container(
                decoration: const BoxDecoration(
                  color: DS.surface,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 16,
                      offset: Offset(0, -4),
                    ),
                  ],
                ),
                child: ListView(
                  controller: scrollController,
                  padding: EdgeInsets.zero,
                  children: [
                    // Handle
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: DS.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),

                    // Status header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                          DS.space5, 0, DS.space5, DS.space4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _StatusBadge(status: order.status),
                              const Spacer(),
                              Text(
                                '#${order.number}',
                                style: DS.numeric(13,
                                    color: DS.inkMuted,
                                    weight: FontWeight.w600),
                              ),
                            ],
                          ),
                          const SizedBox(height: DS.space3),
                          // ETA grande
                          if (eta != null) ...[
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  EtaService.formatEta(eta),
                                  style: DS.display(32,
                                      weight: FontWeight.w700,
                                      color: DS.brandOrange),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'aprox.',
                                  style: DS.ui(13, color: DS.inkMuted),
                                ),
                              ],
                            ),
                            Text(
                              order.status == OrderStatus.inTransit
                                  ? 'Tu motorizado está en camino'
                                  : 'Llegará pronto',
                              style: DS.ui(13, color: DS.inkSecondary),
                            ),
                          ] else
                            Text(
                              _statusMessage(order.status),
                              style: DS.display(20, weight: FontWeight.w600),
                            ),
                        ],
                      ),
                    ),

                    // Progress timeline
                    _OrderProgressTimeline(order: order),

                    const SizedBox(height: DS.space4),
                    const Divider(height: 1, color: DS.border),
                    const SizedBox(height: DS.space4),

                    // Rider info card with actions
                    if (rider != null)
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: DS.space5),
                        child: _RiderInfoCard(
                          rider: rider,
                          isOnline: riderLoc?.isOnline ?? false,
                          isFresh: riderLoc?.isFresh ?? false,
                          onCall: () => ExternalApps.callPhone(rider.phone),
                          onChat: () => ExternalApps.openWhatsApp(
                            rider.phone,
                            message:
                                'Hola ${rider.name}, soy de la orden #${order.number}',
                          ),
                        ),
                      ),

                    const SizedBox(height: DS.space4),

                    // Order details
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: DS.space5),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('DETALLES DEL PEDIDO', style: DS.eyebrow()),
                          const SizedBox(height: DS.space2),
                          _DetailRow(
                            icon: Icons.store,
                            label: 'Recoger en',
                            value: company?.name ?? '—',
                            subtitle: company?.address,
                          ),
                          const SizedBox(height: DS.space2),
                          _DetailRow(
                            icon: Icons.home,
                            label: 'Entregar a',
                            value: order.customer,
                            subtitle: order.address,
                          ),
                          const SizedBox(height: DS.space2),
                          if (order.description.isNotEmpty)
                            _DetailRow(
                              icon: Icons.inventory_2_outlined,
                              label: 'Paquete',
                              value: order.description,
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: DS.space6),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  String _statusMessage(OrderStatus s) {
    switch (s) {
      case OrderStatus.assigned:
        return 'El motorizado va al punto de recogida';
      case OrderStatus.inTransit:
        return 'Tu pedido viene en camino';
      case OrderStatus.delivered:
        return '¡Pedido entregado!';
      case OrderStatus.cancelled:
        return 'Pedido cancelado';
      default:
        return 'Procesando...';
    }
  }
}

// ============= MARKER COMPONENTS =============

class _MarkerBubble extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  const _MarkerBubble({
    required this.icon,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(6),
            boxShadow: const [
              BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
            ],
          ),
          child: Text(label,
              style: DS.ui(10, color: Colors.white, weight: FontWeight.w700)),
        ),
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: const [
              BoxShadow(color: Colors.black38, blurRadius: 6, offset: Offset(0, 3)),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 16),
        ),
      ],
    );
  }
}

class _RiderMarker extends StatelessWidget {
  final Rider? rider;
  const _RiderMarker({this.rider});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Pulso animado
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.8, end: 1.4),
          duration: const Duration(seconds: 1),
          curve: Curves.easeOut,
          builder: (context, value, child) {
            return Container(
              width: 50 * value,
              height: 50 * value,
              decoration: BoxDecoration(
                color: DS.brandOrange.withValues(alpha: 0.3 * (2 - value)),
                shape: BoxShape.circle,
              ),
            );
          },
          onEnd: () {},
        ),
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: DS.brandOrange,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [
              BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 3)),
            ],
          ),
          child: const Icon(Icons.two_wheeler, color: Colors.white, size: 22),
        ),
      ],
    );
  }
}

class _MapTopButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _MapTopButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 4,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: DS.ink, size: 20),
        ),
      ),
    );
  }
}

// ============= BOTTOM SHEET COMPONENTS =============

class _StatusBadge extends StatelessWidget {
  final OrderStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    IconData icon;
    switch (status) {
      case OrderStatus.assigned:
        color = DS.info;
        label = 'PREPARANDO';
        icon = Icons.assignment_ind;
        break;
      case OrderStatus.inTransit:
        color = DS.accent;
        label = 'EN CAMINO';
        icon = Icons.directions_run;
        break;
      case OrderStatus.delivered:
        color = DS.success;
        label = 'ENTREGADO';
        icon = Icons.check_circle;
        break;
      case OrderStatus.cancelled:
        color = DS.danger;
        label = 'CANCELADO';
        icon = Icons.cancel;
        break;
      default:
        color = DS.inkMuted;
        label = status.label.toUpperCase();
        icon = Icons.info;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 4),
          Text(label,
              style: DS.ui(10, color: color, weight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _OrderProgressTimeline extends StatelessWidget {
  final DeliveryOrder order;
  const _OrderProgressTimeline({required this.order});

  int get _currentStep {
    switch (order.status) {
      case OrderStatus.pending:
      case OrderStatus.awaitingQuote:
      case OrderStatus.quoted:
        return 0;
      case OrderStatus.assigned:
        return 1;
      case OrderStatus.inTransit:
        return 2;
      case OrderStatus.delivered:
        return 3;
      default:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = ['Confirmado', 'Recogiendo', 'En camino', 'Entregado'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: DS.space5),
      child: Row(
        children: List.generate(steps.length, (i) {
          final isDone = i <= _currentStep;
          final isCurrent = i == _currentStep;
          return Expanded(
            child: Row(
              children: [
                // Dot
                Container(
                  width: isCurrent ? 18 : 14,
                  height: isCurrent ? 18 : 14,
                  decoration: BoxDecoration(
                    color: isDone ? DS.brandOrange : DS.border,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isCurrent
                          ? DS.brandOrange.withValues(alpha: 0.3)
                          : Colors.transparent,
                      width: 4,
                    ),
                  ),
                  child: isDone
                      ? const Icon(Icons.check,
                          color: Colors.white, size: 10)
                      : null,
                ),
                // Line (except last)
                if (i < steps.length - 1)
                  Expanded(
                    child: Container(
                      height: 2,
                      color: i < _currentStep
                          ? DS.brandOrange
                          : DS.border,
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _RiderInfoCard extends StatelessWidget {
  final Rider rider;
  final bool isOnline;
  final bool isFresh;
  final VoidCallback onCall;
  final VoidCallback onChat;

  const _RiderInfoCard({
    required this.rider,
    required this.isOnline,
    required this.isFresh,
    required this.onCall,
    required this.onChat,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DS.space4),
      decoration: BoxDecoration(
        color: DS.surfaceRaised,
        borderRadius: BorderRadius.circular(DS.radiusLg),
        border: Border.all(color: DS.border, width: 1),
      ),
      child: Row(
        children: [
          // Avatar con dot online
          Stack(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: DS.brandOrange.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    rider.name.isNotEmpty ? rider.name[0].toUpperCase() : '?',
                    style: DS.display(20,
                        color: DS.brandOrange, weight: FontWeight.w700),
                  ),
                ),
              ),
              if (isOnline && isFresh)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: DS.success,
                      shape: BoxShape.circle,
                      border: Border.all(color: DS.surfaceRaised, width: 2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: DS.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(rider.name,
                    style: DS.ui(14, weight: FontWeight.w700)),
                Text(
                  '${rider.vehicle.label} · ${rider.plate}',
                  style: DS.ui(11, color: DS.inkMuted),
                ),
                if (isOnline)
                  Text(
                    'En línea',
                    style: DS.ui(10,
                        color: DS.success, weight: FontWeight.w600),
                  )
                else
                  Text(
                    'Desconectado',
                    style: DS.ui(10,
                        color: DS.inkMuted, weight: FontWeight.w600),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: onChat,
            icon: const Icon(Icons.chat_bubble_outline),
            color: DS.success,
            tooltip: 'WhatsApp',
            style: IconButton.styleFrom(
              backgroundColor: DS.success.withValues(alpha: 0.1),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: onCall,
            icon: const Icon(Icons.call),
            color: DS.brandBlue,
            tooltip: 'Llamar',
            style: IconButton.styleFrom(
              backgroundColor: DS.brandBlue.withValues(alpha: 0.1),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? subtitle;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: DS.inkMuted.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(DS.radiusSm),
          ),
          child: Icon(icon, color: DS.inkMuted, size: 16),
        ),
        const SizedBox(width: DS.space3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: DS.ui(10, color: DS.inkMuted, weight: FontWeight.w600)),
              Text(value,
                  style: DS.ui(13, weight: FontWeight.w600)),
              if (subtitle != null && subtitle!.isNotEmpty)
                Text(subtitle!,
                    style: DS.ui(12, color: DS.inkSecondary, height: 1.4)),
            ],
          ),
        ),
      ],
    );
  }
}
