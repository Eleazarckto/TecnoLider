import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/gps_service.dart';
import '../services/geocoding_service.dart';
import 'design_system.dart';
import 'components.dart';

/// Resultado del selector
class LocationResult {
  final double latitude;
  final double longitude;
  LocationResult(this.latitude, this.longitude);
}

/// Pantalla full-screen para seleccionar una ubicación.
class LocationPickerScreen extends StatefulWidget {
  final String title;
  final String subtitle;
  final LatLng? initialPosition;
  final Color markerColor;
  final IconData markerIcon;

  const LocationPickerScreen({
    super.key,
    required this.title,
    required this.subtitle,
    this.initialPosition,
    this.markerColor = DS.brandBlue,
    this.markerIcon = Icons.location_on,
  });

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final MapController _mapCtrl = MapController();
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  LatLng? _selected;
  bool _loadingGps = false;
  GeocodingResponse _searchResponse =
      GeocodingResponse(state: GeocodingState.idle);

  @override
  void initState() {
    super.initState();
    _selected = widget.initialPosition;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    GeocodingService.instance.cancelDebounce();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    GeocodingService.instance.searchWithDebounce(
      query,
      (response) {
        if (!mounted) return;
        setState(() => _searchResponse = response);
      },
    );
  }

  void _selectSuggestion(GeocodingResult r) {
    setState(() {
      _selected = LatLng(r.latitude, r.longitude);
      _searchCtrl.text = r.shortName;
      _searchResponse = GeocodingResponse(state: GeocodingState.idle);
    });
    _searchFocus.unfocus();
    _mapCtrl.move(LatLng(r.latitude, r.longitude), 17);
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _loadingGps = true);
    try {
      final pos = await GpsService.instance.getCurrentPosition();
      if (pos != null && mounted) {
        final p = LatLng(pos.latitude, pos.longitude);
        setState(() => _selected = p);
        _mapCtrl.move(p, 17);
      } else if (mounted) {
        showErrorSnack(context,
            GpsService.instance.lastError ?? 'No se pudo obtener tu ubicación');
      }
    } finally {
      if (mounted) setState(() => _loadingGps = false);
    }
  }

  void _onMapTap(TapPosition pos, LatLng latlng) {
    setState(() => _selected = latlng);
  }

  /// Widget que muestra el estado de búsqueda
  Widget _buildSearchFeedback() {
    final state = _searchResponse.state;

    if (state == GeocodingState.idle) return const SizedBox.shrink();

    if (state == GeocodingState.searching) {
      return _feedbackContainer(
        child: Row(
          children: const [
            SizedBox(
              width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Buscando direcciones...'),
          ],
        ),
      );
    }

    if (state == GeocodingState.error) {
      return _feedbackContainer(
        color: DS.danger.withValues(alpha: 0.08),
        child: Row(
          children: [
            const Icon(Icons.cloud_off, color: DS.danger, size: 16),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _searchResponse.errorMessage ?? 'Error de búsqueda',
                style: DS.ui(12, color: DS.danger, weight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
    }

    if (state == GeocodingState.empty) {
      return _feedbackContainer(
        color: DS.warning.withValues(alpha: 0.08),
        child: Row(
          children: [
            const Icon(Icons.search_off, color: DS.warning, size: 16),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Sin resultados',
                      style: DS.ui(12, color: DS.warning, weight: FontWeight.w700)),
                  Text(
                    'Intenta con menos palabras o toca el mapa para marcar el lugar',
                    style: DS.ui(10, color: DS.inkSecondary, height: 1.3),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Hay resultados
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(DS.radiusMd),
      color: DS.surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 320),
        child: ListView.separated(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: _searchResponse.results.length,
          separatorBuilder: (_, __) =>
              const Divider(height: 1, color: DS.border),
          itemBuilder: (ctx, i) {
            final r = _searchResponse.results[i];
            return InkWell(
              onTap: () => _selectSuggestion(r),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    const Icon(Icons.place, color: DS.inkMuted, size: 16),
                    const SizedBox(width: DS.space2),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.shortName,
                              style: DS.ui(13, weight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          Text(r.displayName,
                              style: DS.ui(10,
                                  color: DS.inkMuted, height: 1.3),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _feedbackContainer({required Widget child, Color? color}) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(DS.radiusMd),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color ?? DS.surface,
          borderRadius: BorderRadius.circular(DS.radiusMd),
        ),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final start = widget.initialPosition ?? const LatLng(10.4806, -66.9036);

    return Scaffold(
      backgroundColor: DS.surface,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.title,
                style: DS.display(16, weight: FontWeight.w700)),
            Text(widget.subtitle,
                style: DS.ui(10, color: DS.inkMuted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ),
        backgroundColor: DS.surfaceRaised,
        foregroundColor: DS.ink,
        elevation: 0,
        shape: const Border(bottom: BorderSide(color: DS.border)),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapCtrl,
            options: MapOptions(
              initialCenter: start,
              initialZoom: 14,
              onTap: _onMapTap,
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
              if (_selected != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _selected!,
                      width: 48,
                      height: 48,
                      alignment: Alignment.topCenter,
                      child: Icon(
                        widget.markerIcon,
                        color: widget.markerColor,
                        size: 44,
                        shadows: const [
                          Shadow(color: Colors.black45, blurRadius: 6),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),

          // Barra de busqueda + feedback
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(DS.space3),
                child: Column(
                  children: [
                    Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(DS.radiusMd),
                      child: TextField(
                        controller: _searchCtrl,
                        focusNode: _searchFocus,
                        onChanged: _onSearchChanged,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'Buscar dirección o lugar...',
                          hintStyle: DS.ui(13, color: DS.inkMuted),
                          prefixIcon:
                              const Icon(Icons.search, color: DS.inkMuted),
                          suffixIcon: _searchCtrl.text.isNotEmpty
                              ? IconButton(
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    setState(() => _searchResponse =
                                        GeocodingResponse(
                                            state: GeocodingState.idle));
                                  },
                                  icon: const Icon(Icons.close,
                                      color: DS.inkMuted),
                                )
                              : null,
                          filled: true,
                          fillColor: DS.surface,
                          border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(DS.radiusMd),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                        ),
                      ),
                    ),
                    if (_searchResponse.state != GeocodingState.idle) ...[
                      const SizedBox(height: DS.space2),
                      _buildSearchFeedback(),
                    ],
                  ],
                ),
              ),
            ),
          ),

          // Boton GPS
          Positioned(
            right: DS.space3,
            bottom: 100,
            child: Material(
              color: DS.surface,
              shape: const CircleBorder(),
              elevation: 4,
              child: InkWell(
                onTap: _loadingGps ? null : _useCurrentLocation,
                customBorder: const CircleBorder(),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: _loadingGps
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: DS.brandOrange),
                        )
                      : const Icon(Icons.my_location,
                          color: DS.brandOrange, size: 22),
                ),
              ),
            ),
          ),

          // Confirmar
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.all(DS.space4),
                decoration: const BoxDecoration(
                  color: DS.surfaceRaised,
                  border: Border(top: BorderSide(color: DS.border)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_selected != null)
                            Text('Ubicación seleccionada',
                                style: DS.ui(11,
                                    color: DS.success,
                                    weight: FontWeight.w600))
                          else
                            Text(
                                'Busca o toca el mapa para marcar',
                                style: DS.ui(11, color: DS.inkMuted)),
                          if (_selected != null)
                            Text(
                              '${_selected!.latitude.toStringAsFixed(5)}, '
                              '${_selected!.longitude.toStringAsFixed(5)}',
                              style:
                                  DS.numeric(11, color: DS.inkSecondary),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: DS.space3),
                    ElevatedButton.icon(
                      onPressed: _selected == null
                          ? null
                          : () => Navigator.pop(
                                context,
                                LocationResult(
                                    _selected!.latitude, _selected!.longitude),
                              ),
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('Confirmar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: widget.markerColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
