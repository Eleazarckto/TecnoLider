import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../models/models.dart';
import '../../services/database.dart';
import '../../widgets/design_system.dart';
import '../../widgets/components.dart';

/// Pantalla de seguimiento de motorizados en tiempo real.
/// Muestra un mapa con todos los motorizados activos y una lista lateral
/// con detalles. Se actualiza automáticamente vía sync.
class AdminTracking extends StatefulWidget {
  const AdminTracking({super.key});

  @override
  State<AdminTracking> createState() => _AdminTrackingState();
}

class _AdminTrackingState extends State<AdminTracking> {
  final db = Database.instance;
  final MapController _mapCtrl = MapController();
  String? _selectedRiderId;

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
    final locations = db.riderLocations;
    final isWide = MediaQuery.of(context).size.width >= 900;

    if (locations.isEmpty) {
      return EmptyState(
        icon: Icons.location_off,
        message: 'Ningún motorizado en línea',
        hint:
            'Los motorizados aparecen aquí automáticamente al iniciar sesión en la app. '
            'Si un motorizado tiene sesión abierta pero no aparece, puede que su GPS '
            'esté desactivado o sin permiso de ubicación.',
        action: OutlinedButton.icon(
          onPressed: () => db.refresh(),
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('Refrescar'),
        ),
      );
    }

    if (isWide) {
      return Row(
        children: [
          SizedBox(
            width: 340,
            child: _RidersList(
              locations: locations,
              selectedId: _selectedRiderId,
              onSelect: _selectRider,
            ),
          ),
          const VerticalDivider(width: 1, color: DS.border),
          Expanded(child: _buildMap(locations)),
        ],
      );
    }

    // Mobile: mapa arriba, lista debajo
    return Column(
      children: [
        SizedBox(
          height: 320,
          child: _buildMap(locations),
        ),
        Expanded(
          child: _RidersList(
            locations: locations,
            selectedId: _selectedRiderId,
            onSelect: _selectRider,
          ),
        ),
      ],
    );
  }

  void _selectRider(String riderId) {
    final loc = db.riderLocationById(riderId);
    if (loc == null) return;
    setState(() => _selectedRiderId = riderId);
    _mapCtrl.move(LatLng(loc.latitude, loc.longitude), 16);
  }

  Widget _buildMap(List<RiderLocation> locations) {
    // Calcular centro y zoom inicial
    LatLng center;
    double zoom = 13;
    if (locations.isNotEmpty) {
      double sumLat = 0, sumLng = 0;
      for (final l in locations) {
        sumLat += l.latitude;
        sumLng += l.longitude;
      }
      center = LatLng(sumLat / locations.length, sumLng / locations.length);
    } else {
      center = const LatLng(10.4806, -66.9036); // Caracas por defecto
    }

    return Container(
      decoration: BoxDecoration(
        border: const Border(left: BorderSide(color: DS.border, width: 1)),
        color: DS.surfaceMuted,
      ),
      child: Stack(
        children: [
          FlutterMap(
            mapController: _mapCtrl,
            options: MapOptions(
              initialCenter: center,
              initialZoom: zoom,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.yj.delivery',
                maxZoom: 19,
              ),
              MarkerLayer(
                markers: locations.map((loc) {
                  final isSelected = loc.riderId == _selectedRiderId;
                  return Marker(
                    point: LatLng(loc.latitude, loc.longitude),
                    width: 120,
                    height: 60,
                    alignment: Alignment.topCenter,
                    child: _RiderMarker(
                      location: loc,
                      isSelected: isSelected,
                      onTap: () => _selectRider(loc.riderId),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          // Contador en la esquina
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: DS.space3, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(DS.radiusSm),
                boxShadow: const [
                  BoxShadow(
                      color: Colors.black12,
                      blurRadius: 8,
                      offset: Offset(0, 2)),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: DS.success,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${locations.length} ${locations.length == 1 ? "motorizado" : "motorizados"} en línea',
                    style: DS.ui(12,
                        color: DS.ink, weight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
          // Atribución
          Positioned(
            bottom: 4,
            right: 4,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('© OpenStreetMap',
                  style: DS.ui(8, color: DS.inkMuted)),
            ),
          ),
        ],
      ),
    );
  }
}

// ============ MARCADOR DEL MOTORIZADO ============
class _RiderMarker extends StatelessWidget {
  final RiderLocation location;
  final bool isSelected;
  final VoidCallback onTap;

  const _RiderMarker({
    required this.location,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = location.isFresh
        ? DS.success
        : (location.isStale ? DS.danger : DS.warning);

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
              boxShadow: const [
                BoxShadow(
                    color: Colors.black26,
                    blurRadius: 4,
                    offset: Offset(0, 2)),
              ],
            ),
            child: Text(
              location.riderName ?? '?',
              style: DS.ui(9,
                  color: Colors.white, weight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            width: isSelected ? 40 : 32,
            height: isSelected ? 40 : 32,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                  color: Colors.white, width: isSelected ? 3 : 2),
              boxShadow: const [
                BoxShadow(
                    color: Colors.black26,
                    blurRadius: 4,
                    offset: Offset(0, 2)),
              ],
            ),
            child: Icon(Icons.two_wheeler,
                color: Colors.white, size: isSelected ? 20 : 16),
          ),
        ],
      ),
    );
  }
}

// ============ LISTA LATERAL ============
class _RidersList extends StatelessWidget {
  final List<RiderLocation> locations;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  const _RidersList({
    required this.locations,
    required this.selectedId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final db = Database.instance;

    // Ordenar: más recientes primero
    final sorted = [...locations]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    return Container(
      color: DS.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(DS.space5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SEGUIMIENTO EN TIEMPO REAL', style: DS.eyebrow()),
                const SizedBox(height: 2),
                Text('Motorizados activos',
                    style: DS.display(20, weight: FontWeight.w500)),
              ],
            ),
          ),
          const Divider(height: 1, color: DS.border),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(DS.space4),
              itemCount: sorted.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: DS.space2),
              itemBuilder: (context, i) {
                final loc = sorted[i];
                final activeOrders = db
                    .ordersByRider(loc.riderId)
                    .where((o) =>
                        o.status == OrderStatus.assigned ||
                        o.status == OrderStatus.inTransit)
                    .length;
                return _RiderTile(
                  location: loc,
                  activeOrders: activeOrders,
                  isSelected: loc.riderId == selectedId,
                  onTap: () => onSelect(loc.riderId),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RiderTile extends StatelessWidget {
  final RiderLocation location;
  final int activeOrders;
  final bool isSelected;
  final VoidCallback onTap;

  const _RiderTile({
    required this.location,
    required this.activeOrders,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = location.isFresh
        ? DS.success
        : (location.isStale ? DS.danger : DS.warning);
    final statusLabel = location.isFresh
        ? 'En línea'
        : (location.isStale ? 'Sin señal' : 'Desactualizado');

    final secondsAgo =
        DateTime.now().difference(location.updatedAt).inSeconds;
    final timeText = secondsAgo < 60
        ? 'hace ${secondsAgo}s'
        : secondsAgo < 3600
            ? 'hace ${secondsAgo ~/ 60} min'
            : 'hace ${secondsAgo ~/ 3600}h';

    return Material(
      color: isSelected
          ? DS.brandOrange.withValues(alpha: 0.08)
          : DS.surfaceRaised,
      borderRadius: BorderRadius.circular(DS.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DS.radiusMd),
        child: Container(
          padding: const EdgeInsets.all(DS.space3),
          decoration: BoxDecoration(
            border: Border.all(
                color: isSelected ? DS.brandOrange : DS.border,
                width: isSelected ? 1.5 : 1),
            borderRadius: BorderRadius.circular(DS.radiusMd),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(DS.radiusSm),
                    ),
                    child: Stack(
                      children: [
                        Center(
                          child: Icon(Icons.two_wheeler,
                              color: statusColor, size: 18),
                        ),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: statusColor,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: DS.surfaceRaised, width: 1.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: DS.space3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(location.riderName ?? '—',
                            style: DS.ui(13, weight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        Row(
                          children: [
                            Text(statusLabel,
                                style: DS.ui(10,
                                    color: statusColor,
                                    weight: FontWeight.w600)),
                            Text(' · ', style: DS.ui(10, color: DS.inkMuted)),
                            Text(timeText,
                                style: DS.ui(10, color: DS.inkMuted)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (activeOrders > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: DS.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(DS.radiusSm),
                      ),
                      child: Text(
                        '$activeOrders ${activeOrders == 1 ? "orden" : "órdenes"}',
                        style: DS.ui(9,
                            color: DS.accent,
                            weight: FontWeight.w700),
                      ),
                    ),
                ],
              ),
              if (location.plate != null && location.plate!.isNotEmpty) ...[
                const SizedBox(height: DS.space2),
                Row(
                  children: [
                    const Icon(Icons.confirmation_number_outlined,
                        color: DS.inkMuted, size: 12),
                    const SizedBox(width: 4),
                    Text(location.plate!,
                        style: DS.ui(11, color: DS.inkSecondary)),
                    if (location.speed != null && location.speed! > 0) ...[
                      const SizedBox(width: DS.space3),
                      const Icon(Icons.speed, color: DS.inkMuted, size: 12),
                      const SizedBox(width: 4),
                      Text(
                        '${(location.speed! * 3.6).toStringAsFixed(0)} km/h',
                        style: DS.ui(11, color: DS.inkSecondary),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
