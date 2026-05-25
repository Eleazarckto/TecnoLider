import 'package:flutter/material.dart';
import '../services/permissions.dart';
import '../widgets/design_system.dart';

/// Pantalla de bienvenida que solicita los permisos del sistema.
class PermissionsScreen extends StatefulWidget {
  final VoidCallback onContinue;
  const PermissionsScreen({super.key, required this.onContinue});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen>
    with WidgetsBindingObserver {
  bool _notificationGranted = false;
  bool _locationGranted = false;
  bool _locationServiceEnabled = true;
  bool _locationDeniedForever = false;
  bool _loadingNotif = false;
  bool _loadingLoc = false;
  bool _checkedInitial = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkCurrentStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Cuando el usuario vuelve a la app desde ajustes del sistema,
  /// refrescamos el estado de los permisos
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkCurrentStatus();
    }
  }

  Future<void> _checkCurrentStatus() async {
    final notif = await AppPermissions.hasNotification();
    final loc = await AppPermissions.hasLocation();
    final service = await AppPermissions.isLocationServiceEnabled();
    final deniedForever = await AppPermissions.isLocationDeniedForever();
    if (!mounted) return;
    setState(() {
      _notificationGranted = notif;
      _locationGranted = loc;
      _locationServiceEnabled = service;
      _locationDeniedForever = deniedForever;
      _checkedInitial = true;
    });
  }

  Future<void> _requestNotification() async {
    setState(() => _loadingNotif = true);
    final granted = await AppPermissions.requestNotification();
    if (!granted) {
      final has = await AppPermissions.hasNotification();
      if (!has && mounted) {
        // Probablemente denegado permanente - mostrar ajustes
        await _showOpenSettingsDialog('notificaciones');
      }
    }
    await _checkCurrentStatus();
    if (mounted) setState(() => _loadingNotif = false);
  }

  Future<void> _requestLocation() async {
    setState(() => _loadingLoc = true);

    // Si el servicio GPS está apagado, llevar a los ajustes
    if (!await AppPermissions.isLocationServiceEnabled()) {
      if (mounted) {
        final ok = await _showActivateGpsDialog();
        if (ok) {
          await AppPermissions.openLocationSettings();
        }
      }
      await _checkCurrentStatus();
      if (mounted) setState(() => _loadingLoc = false);
      return;
    }

    final granted = await AppPermissions.requestLocation();

    if (!granted) {
      // Verificar si fue denegado para siempre
      final forever = await AppPermissions.isLocationDeniedForever();
      if (forever && mounted) {
        await _showOpenSettingsDialog('ubicación');
      }
    }
    await _checkCurrentStatus();
    if (mounted) setState(() => _loadingLoc = false);
  }

  Future<bool> _showActivateGpsDialog() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Activar GPS'),
        content: const Text(
          'El GPS de tu dispositivo está desactivado. Para usar la ubicación, primero debes activarlo en los ajustes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Abrir ajustes'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _showOpenSettingsDialog(String permName) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Permiso denegado'),
        content: Text(
          'Has denegado el permiso de $permName. Para activarlo, ve a los ajustes de la app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Abrir ajustes'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await AppPermissions.openAppSettings();
    }
  }

  bool get _canContinue => _notificationGranted && _locationGranted;

  @override
  Widget build(BuildContext context) {
    if (!_checkedInitial) {
      return const Scaffold(
        backgroundColor: DS.dark,
        body: Center(
          child: CircularProgressIndicator(color: DS.brandOrange),
        ),
      );
    }

    return Scaffold(
      backgroundColor: DS.dark,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(DS.space6),
              child: Column(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: DS.brandOrange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(DS.radiusLg),
                    ),
                    child: const Icon(Icons.delivery_dining,
                        color: DS.brandOrange, size: 36),
                  ),
                  const SizedBox(height: DS.space4),
                  Text('Bienvenido a YJ Delivery',
                      style: DS.display(22,
                          color: Colors.white, weight: FontWeight.w700)),
                  const SizedBox(height: DS.space2),
                  Text(
                    'Antes de comenzar, otorga los siguientes permisos para que la app funcione correctamente.',
                    textAlign: TextAlign.center,
                    style: DS.ui(13,
                        color: Colors.white.withValues(alpha: 0.7),
                        height: 1.5),
                  ),
                ],
              ),
            ),

            // Permission cards
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: DS.space5),
                children: [
                  _PermissionCard(
                    icon: Icons.notifications_active_outlined,
                    title: 'Notificaciones',
                    description:
                        'Recibe alertas cuando lleguen nuevas órdenes o cuando la central te asigne entregas.',
                    granted: _notificationGranted,
                    loading: _loadingNotif,
                    onTap: _requestNotification,
                  ),
                  const SizedBox(height: DS.space3),
                  _PermissionCard(
                    icon: Icons.location_on_outlined,
                    title: 'Ubicación',
                    description:
                        'Para mostrarte el mapa de entregas, indicar puntos de recogida y reportar tu posición a la central.',
                    granted: _locationGranted,
                    loading: _loadingLoc,
                    warning: !_locationServiceEnabled
                        ? 'El GPS del dispositivo está desactivado'
                        : (_locationDeniedForever && !_locationGranted)
                            ? 'Permiso denegado - debes activarlo en Ajustes'
                            : null,
                    onTap: _requestLocation,
                  ),
                ],
              ),
            ),

            // Bottom action
            Container(
              padding: const EdgeInsets.all(DS.space5),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _canContinue ? widget.onContinue : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: DS.brandOrange,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            Colors.white.withValues(alpha: 0.1),
                        disabledForegroundColor:
                            Colors.white.withValues(alpha: 0.4),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(
                        _canContinue
                            ? 'Continuar'
                            : 'Otorga los permisos para continuar',
                        style: DS.ui(14, weight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(height: DS.space2),
                  TextButton(
                    onPressed: widget.onContinue,
                    child: Text(
                      'Saltar por ahora',
                      style: DS.ui(12,
                          color: Colors.white.withValues(alpha: 0.5)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final bool granted;
  final bool loading;
  final String? warning;
  final VoidCallback onTap;

  const _PermissionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.granted,
    required this.loading,
    this.warning,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DS.space4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(DS.radiusLg),
        border: Border.all(
          color: granted
              ? DS.success.withValues(alpha: 0.4)
              : (warning != null
                  ? DS.warning.withValues(alpha: 0.4)
                  : Colors.white.withValues(alpha: 0.1)),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: (granted ? DS.success : DS.brandOrange)
                  .withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(DS.radiusMd),
            ),
            child: Icon(
              granted ? Icons.check_circle : icon,
              color: granted ? DS.success : DS.brandOrange,
              size: 22,
            ),
          ),
          const SizedBox(width: DS.space4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(title,
                        style: DS.ui(15,
                            color: Colors.white,
                            weight: FontWeight.w600)),
                    if (granted) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: DS.success.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('ACTIVO',
                            style: DS.ui(8,
                                color: DS.success,
                                weight: FontWeight.w700)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(description,
                    style: DS.ui(11,
                        color: Colors.white.withValues(alpha: 0.6),
                        height: 1.5)),
                if (warning != null) ...[
                  const SizedBox(height: DS.space2),
                  Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: DS.warning, size: 12),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          warning!,
                          style: DS.ui(10,
                              color: DS.warning,
                              weight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ],
                if (!granted) ...[
                  const SizedBox(height: DS.space2),
                  GestureDetector(
                    onTap: loading ? null : onTap,
                    child: Row(
                      children: [
                        if (loading)
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: DS.brandOrange),
                          )
                        else
                          const Icon(Icons.add_circle_outline,
                              color: DS.brandOrange, size: 14),
                        const SizedBox(width: 6),
                        Text(
                          loading
                              ? 'Procesando...'
                              : (warning != null
                                  ? 'Abrir ajustes'
                                  : 'Activar permiso'),
                          style: DS.ui(12,
                              color: DS.brandOrange,
                              weight: FontWeight.w600),
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
