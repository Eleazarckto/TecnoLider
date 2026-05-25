import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/database.dart';
import '../services/gps_service.dart';
import '../widgets/design_system.dart';
import '../widgets/components.dart';
import '../widgets/app_shell.dart';
import 'login_screen.dart';
import 'rider_payouts_tab.dart';
import 'order_map_screen.dart';

class RiderScreen extends StatefulWidget {
  const RiderScreen({super.key});

  @override
  State<RiderScreen> createState() => _RiderScreenState();
}

class _RiderScreenState extends State<RiderScreen> {
  final db = Database.instance;
  final gps = GpsService.instance;

  @override
  void initState() {
    super.initState();
    db.addListener(_onChange);
    gps.addListener(_onChange);
    // Activar GPS y heartbeat al iniciar sesión (motorizado en línea)
    _startGpsOnLogin();
  }

  @override
  void dispose() {
    db.removeListener(_onChange);
    gps.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) {
      setState(() {});
    }
  }

  /// Inicia GPS automáticamente al iniciar sesión (motorizado en línea).
  /// El GPS reportará posición + heartbeat cada segundo y al cerrar
  /// sesión se marcará como offline en el servidor.
  Future<void> _startGpsOnLogin() async {
    final user = db.currentUser;
    if (user == null || user.role != UserRole.rider) return;
    if (gps.isTracking) return;
    await gps.startTracking();
  }

  Future<void> _logout() async {
    // Esperar a que el motorizado se marque offline antes de salir.
    // Si no esperamos, la sesion queda "online" en el servidor por unos
    // segundos mas (hasta que expire por timeout).
    try {
      await gps.stopTracking();
    } catch (_) {
      // No bloquear el logout si falla
    }
    await db.logout();
    if (!mounted) return;
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final user = db.currentUser!;
    final rider = db.riderById(user.linkedEntityId);
    if (rider == null) {
      return const Scaffold(
          body: Center(child: Text('Motorizado no encontrado')));
    }

    final mine = db.ordersByRider(rider.id);
    final active = mine
        .where((o) =>
            o.status == OrderStatus.assigned ||
            o.status == OrderStatus.inTransit)
        .length;

    final newPayouts = db.myPayouts.length;

    return AppShell(
      userName: rider.name,
      userRoleLabel: 'Motorizado',
      userSubtitle: '${rider.vehicle.label} · ${rider.plate}',
      onLogout: _logout,
      roleColor: DS.brandOrange,
      items: [
        NavItem(
          label: 'Activas',
          icon: Icons.directions_run,
          body: _ActiveTab(riderId: rider.id),
          badge: active > 0 ? active : null,
        ),
        NavItem(
          label: 'Historial',
          icon: Icons.history,
          body: _HistoryTab(riderId: rider.id),
        ),
        NavItem(
          label: 'Ganancias',
          icon: Icons.trending_up,
          body: _EarningsTab(riderId: rider.id),
        ),
        NavItem(
          label: 'Mis pagos',
          icon: Icons.payments_outlined,
          body: const RiderPayoutsTab(),
          badge: newPayouts > 0 ? newPayouts : null,
        ),
      ],
    );
  }
}

// ====================== ACTIVE TAB ======================
class _ActiveTab extends StatelessWidget {
  final String riderId;
  const _ActiveTab({required this.riderId});

  @override
  Widget build(BuildContext context) {
    final db = Database.instance;
    final mine = db.ordersByRider(riderId);
    final active = mine
        .where((o) =>
            o.status == OrderStatus.assigned ||
            o.status == OrderStatus.inTransit)
        .toList();

    if (active.isEmpty) {
      return const EmptyState(
        icon: Icons.coffee_outlined,
        message: 'No tienes entregas activas',
        hint:
            'Cuando la central te asigne una orden, aparecerá aquí. Mantén tu app abierta.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(DS.space6),
      itemCount: active.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: DS.space3),
      itemBuilder: (context, i) {
        if (i == 0) return const _GpsStatusBanner();
        return _ActiveOrderCard(order: active[i - 1]);
      },
    );
  }
}

/// Banner que muestra el estado del GPS y conexión al motorizado.
/// Tres estados posibles:
///  - En línea + GPS activo (verde)
///  - En línea pero sin señal GPS (amarillo)
///  - Desconectado (gris)
class _GpsStatusBanner extends StatelessWidget {
  const _GpsStatusBanner();

  @override
  Widget build(BuildContext context) {
    final gps = GpsService.instance;

    // No está rastreando: no mostrar nada (o app recién abierta)
    if (!gps.isTracking) {
      return const SizedBox.shrink();
    }

    // CASO 1: En línea + GPS con señal → todo perfecto (verde)
    if (gps.isOnline && gps.hasGpsSignal) {
      return _banner(
        color: DS.success,
        icon: null,
        showDot: true,
        title: 'En línea · GPS activo',
        subtitle: 'La central puede ver tu ubicación en tiempo real',
      );
    }

    // CASO 2: En línea pero SIN señal GPS (amarillo)
    if (gps.isOnline && !gps.hasGpsSignal) {
      return _banner(
        color: DS.warning,
        icon: Icons.gps_off,
        showDot: false,
        title: 'En línea · Sin señal GPS',
        subtitle: gps.gpsStatusMessage ??
            'Apareces en línea pero no se ve tu ubicación en el mapa',
        actionLabel: 'Reintentar GPS',
        onAction: () => gps.retryGps(),
      );
    }

    // CASO 3: Desconectado (gris/rojo)
    return _banner(
      color: DS.danger,
      icon: Icons.cloud_off,
      showDot: false,
      title: 'Sin conexión con la central',
      subtitle: 'Revisa tu conexión a internet',
      actionLabel: 'Reintentar',
      onAction: () => gps.startTracking(),
    );
  }

  Widget _banner({
    required Color color,
    required IconData? icon,
    required bool showDot,
    required String title,
    required String subtitle,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Container(
      padding: const EdgeInsets.all(DS.space3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(DS.radiusSm),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1),
      ),
      child: Row(
        children: [
          if (showDot)
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            )
          else if (icon != null)
            Icon(icon, color: color, size: 16),
          const SizedBox(width: DS.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: DS.ui(12, color: color, weight: FontWeight.w700),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style: DS.ui(10, color: DS.inkSecondary, height: 1.3),
                ),
              ],
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: color,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
              ),
              child: Text(actionLabel, style: DS.ui(11, weight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }
}

class _ActiveOrderCard extends StatelessWidget {
  final DeliveryOrder order;
  const _ActiveOrderCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final db = Database.instance;
    final company = db.companyById(order.companyId);

    final isAssigned = order.status == OrderStatus.assigned;
    final isInTransit = order.status == OrderStatus.inTransit;

    return Container(
      decoration: BoxDecoration(
        color: DS.surfaceRaised,
        borderRadius: BorderRadius.circular(DS.radiusLg),
        border: Border.all(color: DS.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status banner
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: DS.space4, vertical: DS.space3),
            decoration: BoxDecoration(
              color: isAssigned ? DS.infoBg : DS.accentBg,
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(DS.radiusLg)),
            ),
            child: Row(
              children: [
                Icon(
                  isAssigned
                      ? Icons.assignment_ind_outlined
                      : Icons.directions_run,
                  size: 16,
                  color: isAssigned ? DS.info : DS.accent,
                ),
                const SizedBox(width: DS.space2),
                Text(
                  isAssigned ? 'Lista para recoger' : 'En camino al destino',
                  style: DS.ui(12,
                      color: isAssigned ? DS.info : DS.accent,
                      weight: FontWeight.w700,
                      spacing: 0.3),
                ),
                const Spacer(),
                Text('Orden #${order.number}',
                    style: DS.numeric(13, weight: FontWeight.w700)),
              ],
            ),
          ),
          // Body
          Padding(
            padding: const EdgeInsets.all(DS.space4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InfoRow(
                    icon: Icons.apartment,
                    label: 'Recoger en',
                    value: company?.name ?? '—'),
                if (company != null)
                  InfoRow(
                      icon: Icons.location_on_outlined,
                      label: 'Origen',
                      value: company.address),
                const SectionDivider(),
                InfoRow(
                    icon: Icons.person_outline,
                    label: 'Cliente',
                    value: order.customer),
                InfoRow(
                    icon: Icons.phone_outlined,
                    label: 'Teléfono',
                    value: order.customerPhone),
                InfoRow(
                    icon: Icons.location_on,
                    label: 'Entregar en',
                    value: order.address,
                    maxLines: 3),
                if (order.description.isNotEmpty)
                  InfoRow(
                      icon: Icons.inventory_2_outlined,
                      label: 'Paquete',
                      value: order.description),
                const SizedBox(height: DS.space3),
                // Botón VER MAPA (siempre visible si hay alguna ubicación)
                if (order.hasPickupLocation || order.hasDropoffLocation) ...[
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => OrderMapScreen(order: order),
                          ),
                        );
                      },
                      icon: const Icon(Icons.map_outlined, size: 16),
                      label: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: Text('Ver mapa de la ruta'),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: DS.brandBlue,
                        side: BorderSide(
                            color: DS.brandBlue.withValues(alpha: 0.3),
                            width: 1),
                      ),
                    ),
                  ),
                  const SizedBox(height: DS.space3),
                ],
                // Earnings preview
                Container(
                  padding: const EdgeInsets.all(DS.space3),
                  decoration: BoxDecoration(
                    color: DS.dark,
                    borderRadius: BorderRadius.circular(DS.radiusMd),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: DS.brandOrange.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(DS.radiusSm),
                        ),
                        child: const Icon(Icons.payments_outlined,
                            color: DS.brandOrange, size: 16),
                      ),
                      const SizedBox(width: DS.space3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('GANARÁS POR ESTA ENTREGA',
                                style: DS.eyebrow(
                                    color:
                                        Colors.white.withValues(alpha: 0.5))),
                            const SizedBox(height: 2),
                            Text(formatMoney(order.riderCommission),
                                style: DS.numeric(20,
                                    color: DS.brandOrange,
                                    weight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: DS.space4),
                // Actions
                if (isAssigned)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        db.updateOrderStatus(
                            order.id, OrderStatus.inTransit);
                        showSuccessSnack(context,
                            'Marcaste el paquete como recogido. Buen viaje.');
                      },
                      icon:
                          const Icon(Icons.shopping_bag_outlined, size: 16),
                      label: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: Text('Marcar como recogido'),
                      ),
                    ),
                  )
                else if (isInTransit)
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final ok = await showConfirmDialog(
                              context,
                              title: 'Cancelar entrega',
                              message:
                                  '¿Seguro? Esta acción es irreversible.',
                              confirmLabel: 'Sí, cancelar',
                              destructive: true,
                            );
                            if (ok) {
                              db.cancelOrder(order.id);
                              showErrorSnack(context,
                                  'Orden #${order.number} cancelada');
                            }
                          },
                          icon: const Icon(Icons.close, size: 14),
                          label: const Text('Cancelar'),
                        ),
                      ),
                      const SizedBox(width: DS.space2),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: DS.success),
                          onPressed: () {
                            db.updateOrderStatus(
                                order.id, OrderStatus.delivered);
                            showSuccessSnack(context,
                                '¡Entrega completada! +${formatMoney(order.riderCommission)} a tus ganancias.');
                          },
                          icon: const Icon(Icons.check_circle, size: 16),
                          label: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 4),
                            child: Text('Entregado'),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ====================== HISTORY TAB ======================
class _HistoryTab extends StatelessWidget {
  final String riderId;
  const _HistoryTab({required this.riderId});

  @override
  Widget build(BuildContext context) {
    final db = Database.instance;
    final mine = db.ordersByRider(riderId);
    final history = mine
        .where((o) =>
            o.status == OrderStatus.delivered ||
            o.status == OrderStatus.cancelled)
        .toList();

    if (history.isEmpty) {
      return const EmptyState(
        icon: Icons.history,
        message: 'Sin historial todavía',
        hint: 'Tus entregas completadas y canceladas aparecerán aquí.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(DS.space6),
      itemCount: history.length,
      separatorBuilder: (_, __) => const SizedBox(height: DS.space2),
      itemBuilder: (context, i) {
        final o = history[i];
        final company = db.companyById(o.companyId);
        return Container(
          padding: const EdgeInsets.all(DS.space4),
          decoration: BoxDecoration(
            color: DS.surfaceRaised,
            borderRadius: BorderRadius.circular(DS.radiusLg),
            border: Border.all(color: DS.border, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('#${o.number}',
                      style: DS.numeric(14,
                          color: DS.inkMuted, weight: FontWeight.w700)),
                  const SizedBox(width: DS.space2),
                  Expanded(
                    child: Text(company?.name ?? '—',
                        style: DS.ui(13, weight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis),
                  ),
                  if (o.payoutId != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: DS.success.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(DS.radiusSm),
                      ),
                      child: Text('LIQUIDADA',
                          style: DS.ui(9,
                              color: DS.success,
                              weight: FontWeight.w700)),
                    )
                  else
                    StatusChip(status: o.status, small: true),
                ],
              ),
              const SizedBox(height: 4),
              Text('${o.address} · ${formatDate(o.createdAt)}',
                  style: DS.ui(12, color: DS.inkMuted, height: 1.4),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: DS.space2),
              if (o.status == OrderStatus.delivered)
                Row(
                  children: [
                    const Icon(Icons.payments_outlined,
                        size: 13, color: DS.success),
                    const SizedBox(width: 4),
                    Text(formatMoney(o.riderCommission),
                        style: DS.numeric(13,
                            color: DS.success, weight: FontWeight.w700)),
                    if (o.payoutId == null) ...[
                      const SizedBox(width: DS.space2),
                      Text('· pendiente de cobro',
                          style: DS.ui(11,
                              color: DS.warning,
                              weight: FontWeight.w500)),
                    ],
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

// ====================== EARNINGS TAB ======================
class _EarningsTab extends StatelessWidget {
  final String riderId;
  const _EarningsTab({required this.riderId});

  @override
  Widget build(BuildContext context) {
    final db = Database.instance;
    final stats = db.riderStats(riderId);
    final mine = db.ordersByRider(riderId);
    final delivered =
        mine.where((o) => o.status == OrderStatus.delivered).toList();

    final earned = stats['earned'] as double;
    final deliveredCount = stats['delivered'] as int;
    final avg = deliveredCount > 0 ? earned / deliveredCount : 0.0;

    final paid = delivered
        .where((o) => o.payoutId != null)
        .fold<double>(0, (s, o) => s + o.riderCommission);
    final pending = delivered
        .where((o) => o.payoutId == null)
        .fold<double>(0, (s, o) => s + o.riderCommission);

    final byDay = <String, double>{};
    for (final o in delivered) {
      final key =
          '${o.deliveredAt!.year}-${o.deliveredAt!.month.toString().padLeft(2, '0')}-${o.deliveredAt!.day.toString().padLeft(2, '0')}';
      byDay[key] = (byDay[key] ?? 0) + o.riderCommission;
    }
    final sortedDays = byDay.keys.toList()..sort();

    return ListView(
      padding: const EdgeInsets.all(DS.space6),
      children: [
        Container(
          padding: const EdgeInsets.all(DS.space6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DS.radiusXl),
            gradient: const LinearGradient(
              colors: [DS.dark, Color(0xFF0A0D11)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: DS.shadowLg,
          ),
          child: Stack(
            children: [
              Positioned(
                right: -50,
                top: -50,
                child: Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        DS.brandOrange.withValues(alpha: 0.25),
                        DS.brandOrange.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('GANANCIAS ACUMULADAS',
                      style: DS.eyebrow(
                          color: Colors.white.withValues(alpha: 0.5))),
                  const SizedBox(height: DS.space4),
                  Text(formatMoney(earned),
                      style: DS.numeric(40,
                          color: Colors.white, weight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    'En $deliveredCount entrega${deliveredCount == 1 ? "" : "s"} completada${deliveredCount == 1 ? "" : "s"}',
                    style: DS.ui(13,
                        color: Colors.white.withValues(alpha: 0.6)),
                  ),
                  if (pending > 0 || paid > 0) ...[
                    const SizedBox(height: DS.space5),
                    Row(
                      children: [
                        Expanded(
                          child: _MiniBalance(
                            label: 'Ya cobrado',
                            value: paid,
                            color: DS.success,
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 36,
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                        Expanded(
                          child: _MiniBalance(
                            label: 'Por cobrar',
                            value: pending,
                            color: DS.warning,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: DS.space5),
        Row(
          children: [
            Expanded(
              child: KpiCard(
                label: 'Promedio',
                value: formatMoney(avg),
                trend: 'Por entrega',
                icon: Icons.trending_up,
                accentColor: DS.success,
                compact: true,
              ),
            ),
            const SizedBox(width: DS.space3),
            Expanded(
              child: KpiCard(
                label: 'Activas',
                value: stats['active'].toString(),
                trend: 'En curso',
                icon: Icons.directions_run,
                accentColor: DS.accent,
                compact: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: DS.space5),
        if (sortedDays.isNotEmpty) ...[
          Text('POR DÍA', style: DS.eyebrow()),
          const SizedBox(height: DS.space3),
          Container(
            decoration: BoxDecoration(
              color: DS.surfaceRaised,
              borderRadius: BorderRadius.circular(DS.radiusLg),
              border: Border.all(color: DS.border, width: 1),
            ),
            child: Column(
              children: sortedDays.reversed.toList().asMap().entries.map((e) {
                final isLast = e.key == sortedDays.length - 1;
                final day = e.value;
                final amount = byDay[day]!;
                final parts = day.split('-');
                final date = DateTime(int.parse(parts[0]),
                    int.parse(parts[1]), int.parse(parts[2]));
                final ordersThatDay = delivered.where((o) {
                  final d = o.deliveredAt!;
                  return d.year == date.year &&
                      d.month == date.month &&
                      d.day == date.day;
                }).length;
                return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: DS.space4, vertical: DS.space3),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                          color: isLast ? Colors.transparent : DS.border,
                          width: 1),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: DS.brandOrange.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(DS.radiusSm),
                        ),
                        child: const Icon(Icons.calendar_today_outlined,
                            size: 14, color: DS.brandOrangeDeep),
                      ),
                      const SizedBox(width: DS.space3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(formatDateLong(date),
                                style: DS.ui(13, weight: FontWeight.w600)),
                            Text(
                                '$ordersThatDay entrega${ordersThatDay == 1 ? "" : "s"}',
                                style: DS.ui(11, color: DS.inkMuted)),
                          ],
                        ),
                      ),
                      Text(formatMoney(amount),
                          style: DS.numeric(15,
                              color: DS.success, weight: FontWeight.w700)),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ] else
          const EmptyState(
            icon: Icons.payments_outlined,
            message: 'Aún no tienes ganancias registradas',
            hint:
                'Completa tu primera entrega y verás aquí el desglose detallado.',
          ),
        const SizedBox(height: DS.space8),
      ],
    );
  }
}

class _MiniBalance extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _MiniBalance({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: DS.eyebrow(
                color: Colors.white.withValues(alpha: 0.5))),
        const SizedBox(height: 4),
        Text(formatMoney(value),
            style: DS.numeric(18, color: color, weight: FontWeight.w700)),
      ],
    );
  }
}
