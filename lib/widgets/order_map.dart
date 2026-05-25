import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/models.dart';
import 'design_system.dart';

/// Marker simple representando un punto en el mapa.
class MapMarker {
  final LatLng point;
  final String label;
  final IconData icon;
  final Color color;

  MapMarker({
    required this.point,
    required this.label,
    required this.icon,
    required this.color,
  });
}

/// Mapa interactivo con OpenStreetMap.
/// Muestra una colección de marcadores y opcionalmente la línea
/// que conecta el origen con el destino.
class AppMap extends StatefulWidget {
  final List<MapMarker> markers;
  final bool drawLine;
  final double height;
  final LatLng? initialCenter;
  final double initialZoom;
  final bool interactive;

  const AppMap({
    super.key,
    required this.markers,
    this.drawLine = false,
    this.height = 280,
    this.initialCenter,
    this.initialZoom = 14.0,
    this.interactive = true,
  });

  /// Helper: crea un mapa para visualizar el origen y destino de una orden
  factory AppMap.forOrder(
    DeliveryOrder order, {
    double height = 280,
    RiderLocation? riderLocation,
  }) {
    final markers = <MapMarker>[];

    if (order.hasPickupLocation) {
      markers.add(MapMarker(
        point: LatLng(order.pickupLat!, order.pickupLng!),
        label: 'Recogida',
        icon: Icons.store_mall_directory,
        color: DS.brandBlue,
      ));
    }
    if (order.hasDropoffLocation) {
      markers.add(MapMarker(
        point: LatLng(order.dropoffLat!, order.dropoffLng!),
        label: 'Entrega',
        icon: Icons.flag,
        color: DS.success,
      ));
    }
    if (riderLocation != null) {
      markers.add(MapMarker(
        point: LatLng(riderLocation.latitude, riderLocation.longitude),
        label: 'Motorizado',
        icon: Icons.two_wheeler,
        color: DS.brandOrange,
      ));
    }

    return AppMap(
      markers: markers,
      drawLine: order.hasBothLocations,
      height: height,
    );
  }

  @override
  State<AppMap> createState() => _AppMapState();
}

class _AppMapState extends State<AppMap> {
  final MapController _ctrl = MapController();

  LatLng _computeCenter() {
    if (widget.initialCenter != null) return widget.initialCenter!;
    if (widget.markers.isEmpty) {
      return const LatLng(10.4806, -66.9036); // default: Caracas, Venezuela
    }
    double sumLat = 0, sumLng = 0;
    for (final m in widget.markers) {
      sumLat += m.point.latitude;
      sumLng += m.point.longitude;
    }
    return LatLng(
      sumLat / widget.markers.length,
      sumLng / widget.markers.length,
    );
  }

  /// Calcula el zoom adecuado para que se vean todos los marcadores
  double _computeZoom() {
    if (widget.markers.length < 2) return widget.initialZoom;

    double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
    for (final m in widget.markers) {
      if (m.point.latitude < minLat) minLat = m.point.latitude;
      if (m.point.latitude > maxLat) maxLat = m.point.latitude;
      if (m.point.longitude < minLng) minLng = m.point.longitude;
      if (m.point.longitude > maxLng) maxLng = m.point.longitude;
    }

    final latDiff = maxLat - minLat;
    final lngDiff = maxLng - minLng;
    final maxDiff = latDiff > lngDiff ? latDiff : lngDiff;

    if (maxDiff < 0.005) return 16;
    if (maxDiff < 0.01) return 15;
    if (maxDiff < 0.05) return 13;
    if (maxDiff < 0.1) return 12;
    if (maxDiff < 0.5) return 10;
    return 8;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(DS.radiusLg),
        border: Border.all(color: DS.border, width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(DS.radiusLg),
        child: Stack(
          children: [
            FlutterMap(
              mapController: _ctrl,
              options: MapOptions(
                initialCenter: _computeCenter(),
                initialZoom: _computeZoom(),
                interactionOptions: InteractionOptions(
                  flags: widget.interactive
                      ? InteractiveFlag.all & ~InteractiveFlag.rotate
                      : InteractiveFlag.none,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.yj.delivery',
                  maxZoom: 19,
                ),
                if (widget.drawLine && widget.markers.length >= 2)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: widget.markers.map((m) => m.point).toList(),
                        color: DS.brandOrange,
                        strokeWidth: 3,
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: widget.markers.map((m) {
                    return Marker(
                      point: m.point,
                      width: 110,
                      height: 56,
                      alignment: Alignment.topCenter,
                      child: _MarkerBubble(marker: m),
                    );
                  }).toList(),
                ),
              ],
            ),
            // Atribución OSM (legal)
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
                child: Text(
                  '© OpenStreetMap',
                  style: DS.ui(8, color: DS.inkMuted),
                ),
              ),
            ),
            // Botón centrar todo
            if (widget.markers.length >= 2 && widget.interactive)
              Positioned(
                top: 8,
                right: 8,
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(DS.radiusSm),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(DS.radiusSm),
                    onTap: () {
                      _ctrl.move(_computeCenter(), _computeZoom());
                    },
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.center_focus_strong,
                          color: DS.ink, size: 18),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MarkerBubble extends StatelessWidget {
  final MapMarker marker;
  const _MarkerBubble({required this.marker});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: marker.color,
            borderRadius: BorderRadius.circular(4),
            boxShadow: const [
              BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
            ],
          ),
          child: Text(
            marker.label,
            style: DS.ui(9, color: Colors.white, weight: FontWeight.w700),
          ),
        ),
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: marker.color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [
              BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
            ],
          ),
          child: Icon(marker.icon, color: Colors.white, size: 16),
        ),
      ],
    );
  }
}
