import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../services/database.dart';
import '../../widgets/design_system.dart';
import '../../widgets/components.dart';

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final db = Database.instance;
    final stats = db.globalStats();
    final delivered = db.orders.where((o) => o.status == OrderStatus.delivered).toList();
    final isWide = MediaQuery.of(context).size.width >= 900;

    // Top riders calc
    final riderStats = <String, Map<String, dynamic>>{};
    for (final o in delivered) {
      if (o.riderId == null) continue;
      riderStats.putIfAbsent(o.riderId!, () => {'count': 0, 'earned': 0.0});
      riderStats[o.riderId!]!['count'] = (riderStats[o.riderId!]!['count'] as int) + 1;
      riderStats[o.riderId!]!['earned'] =
          (riderStats[o.riderId!]!['earned'] as double) + o.riderCommission;
    }
    final topRiders = riderStats.entries.toList()
      ..sort((a, b) =>
          (b.value['earned'] as double).compareTo(a.value['earned'] as double));

    // Top companies calc
    final companyStats = <String, Map<String, dynamic>>{};
    for (final o in delivered) {
      companyStats.putIfAbsent(o.companyId, () => {'count': 0, 'amount': 0.0});
      companyStats[o.companyId]!['count'] =
          (companyStats[o.companyId]!['count'] as int) + 1;
      companyStats[o.companyId]!['amount'] =
          (companyStats[o.companyId]!['amount'] as double) + o.amount;
    }
    final topCompanies = companyStats.entries.toList()
      ..sort((a, b) =>
          (b.value['amount'] as double).compareTo(a.value['amount'] as double));

    return ListView(
      padding: const EdgeInsets.all(DS.space6),
      children: [
        // ====== Hero financial section ======
        _FinancialHero(stats: stats),
        const SizedBox(height: DS.space6),

        // ====== Operational KPIs ======
        Text('Operación'.toUpperCase(), style: DS.eyebrow()),
        const SizedBox(height: DS.space3),
        _KpiGrid(stats: stats, isWide: isWide),
        const SizedBox(height: DS.space6),

        // ====== Two-column layout for tables ======
        if (isWide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _TopRidersCard(topRiders: topRiders, db: db)),
              const SizedBox(width: DS.space5),
              Expanded(child: _TopCompaniesCard(topCompanies: topCompanies, db: db)),
            ],
          )
        else ...[
          _TopRidersCard(topRiders: topRiders, db: db),
          const SizedBox(height: DS.space4),
          _TopCompaniesCard(topCompanies: topCompanies, db: db),
        ],

        const SizedBox(height: DS.space6),

        // ====== Recent activity ======
        _RecentOrdersCard(orders: db.orders.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt))),
        const SizedBox(height: DS.space8),
      ],
    );
  }
}

// ====================== FINANCIAL HERO ======================
class _FinancialHero extends StatelessWidget {
  final Map<String, double> stats;
  const _FinancialHero({required this.stats});

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;
    return Container(
      padding: const EdgeInsets.all(DS.space6),
      decoration: BoxDecoration(
        color: DS.dark,
        borderRadius: BorderRadius.circular(DS.radiusXl),
        boxShadow: DS.shadowLg,
      ),
      child: Stack(
        children: [
          Positioned(
            right: -40,
            top: -40,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    DS.brandOrange.withValues(alpha: 0.18),
                    DS.brandOrange.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'BALANCE OPERATIVO',
                    style: DS.eyebrow(color: Colors.white.withValues(alpha: 0.5)),
                  ),
                  const SizedBox(width: DS.space2),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: DS.success.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                              color: DS.success, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 4),
                        Text('EN VIVO',
                            style: DS.ui(9,
                                color: DS.success, weight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: DS.space5),
              isWide
                  ? Row(
                      children: [
                        Expanded(
                          child: _HeroMetric(
                            label: 'Ingresos totales',
                            value: formatMoney(stats['revenue']!),
                            color: Colors.white,
                            isPrimary: true,
                          ),
                        ),
                        Container(
                            width: 1,
                            height: 60,
                            color: Colors.white.withValues(alpha: 0.1)),
                        Expanded(
                          child: _HeroMetric(
                            label: 'Pagado a motorizados',
                            value: formatMoney(stats['commissions']!),
                            color: DS.brandOrange,
                          ),
                        ),
                        Container(
                            width: 1,
                            height: 60,
                            color: Colors.white.withValues(alpha: 0.1)),
                        Expanded(
                          child: _HeroMetric(
                            label: 'Ganancia central',
                            value: formatMoney(stats['central']!),
                            color: DS.brandBlue,
                          ),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _HeroMetric(
                          label: 'Ingresos totales',
                          value: formatMoney(stats['revenue']!),
                          color: Colors.white,
                          isPrimary: true,
                        ),
                        const SizedBox(height: DS.space4),
                        Row(
                          children: [
                            Expanded(
                              child: _HeroMetric(
                                label: 'Motorizados',
                                value: formatMoney(stats['commissions']!),
                                color: DS.brandOrange,
                              ),
                            ),
                            Expanded(
                              child: _HeroMetric(
                                label: 'Central',
                                value: formatMoney(stats['central']!),
                                color: DS.brandBlue,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool isPrimary;
  const _HeroMetric(
      {required this.label,
      required this.value,
      required this.color,
      this.isPrimary = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: DS.eyebrow(color: Colors.white.withValues(alpha: 0.45)),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: DS.numeric(isPrimary ? 36 : 24,
              color: color, weight: FontWeight.w600),
        ),
      ],
    );
  }
}

// ====================== KPI GRID ======================
class _KpiGrid extends StatelessWidget {
  final Map<String, double> stats;
  final bool isWide;
  const _KpiGrid({required this.stats, required this.isWide});

  @override
  Widget build(BuildContext context) {
    final db = Database.instance;
    final cards = [
      KpiCard(
        label: 'Total órdenes',
        value: stats['total']!.toInt().toString(),
        icon: Icons.receipt_long_outlined,
      ),
      KpiCard(
        label: 'Entregadas',
        value: stats['delivered']!.toInt().toString(),
        icon: Icons.check_circle_outline,
        accentColor: DS.success,
      ),
      KpiCard(
        label: 'Pendientes',
        value: stats['pending']!.toInt().toString(),
        icon: Icons.schedule,
        accentColor: DS.warning,
      ),
      KpiCard(
        label: 'En curso',
        value: db.activeOrders().length.toString(),
        icon: Icons.local_shipping_outlined,
        accentColor: DS.brandBlue,
      ),
    ];

    return GridView.count(
      crossAxisCount: isWide ? 4 : 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: DS.space4,
      mainAxisSpacing: DS.space4,
      childAspectRatio: isWide ? 1.6 : 1.5,
      children: cards,
    );
  }
}

// ====================== TOP RIDERS CARD ======================
class _TopRidersCard extends StatelessWidget {
  final List<MapEntry<String, Map<String, dynamic>>> topRiders;
  final Database db;
  const _TopRidersCard({required this.topRiders, required this.db});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: DS.surfaceRaised,
        borderRadius: BorderRadius.circular(DS.radiusLg),
        border: Border.all(color: DS.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(DS.space5),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: DS.brandOrange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(DS.radiusSm),
                  ),
                  child: const Icon(Icons.emoji_events_outlined,
                      size: 17, color: DS.brandOrange),
                ),
                const SizedBox(width: DS.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Top motorizados',
                          style: DS.display(17, weight: FontWeight.w500)),
                      Text(
                        'Ranking por ganancias acumuladas',
                        style: DS.ui(12, color: DS.inkMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (topRiders.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  DS.space5, 0, DS.space5, DS.space5),
              child: Text(
                'Aún no hay entregas completadas.',
                style: DS.ui(13, color: DS.inkMuted),
              ),
            )
          else ...[
            const Divider(height: 1, color: DS.border),
            ...topRiders.take(5).map((e) {
              final rider = db.riderById(e.key);
              final isLast = topRiders.indexOf(e) ==
                      (topRiders.length > 5 ? 4 : topRiders.length - 1);
              return Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: DS.space5, vertical: DS.space4),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                        color: isLast ? Colors.transparent : DS.border, width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      '#${topRiders.indexOf(e) + 1}',
                      style: DS.numeric(13,
                          color: DS.inkMuted, weight: FontWeight.w600),
                    ),
                    const SizedBox(width: DS.space3),
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: DS.brandOrange.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(DS.radiusSm),
                      ),
                      child: Center(
                        child: Text(
                          rider?.name.isNotEmpty == true
                              ? rider!.name[0].toUpperCase()
                              : '?',
                          style: DS.display(15,
                              color: DS.brandOrange, weight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(width: DS.space3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(rider?.name ?? '—',
                              style: DS.ui(13,
                                  color: DS.ink, weight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis),
                          Text('${e.value['count']} entregas',
                              style: DS.ui(11, color: DS.inkMuted)),
                        ],
                      ),
                    ),
                    Text(
                      formatMoney(e.value['earned'] as double),
                      style: DS.numeric(14,
                          color: DS.success, weight: FontWeight.w600),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

// ====================== TOP COMPANIES CARD ======================
class _TopCompaniesCard extends StatelessWidget {
  final List<MapEntry<String, Map<String, dynamic>>> topCompanies;
  final Database db;
  const _TopCompaniesCard({required this.topCompanies, required this.db});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: DS.surfaceRaised,
        borderRadius: BorderRadius.circular(DS.radiusLg),
        border: Border.all(color: DS.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(DS.space5),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: DS.brandBlue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(DS.radiusSm),
                  ),
                  child: const Icon(Icons.business_outlined,
                      size: 17, color: DS.brandBlue),
                ),
                const SizedBox(width: DS.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Empresas activas',
                          style: DS.display(17, weight: FontWeight.w500)),
                      Text(
                        'Por volumen facturado',
                        style: DS.ui(12, color: DS.inkMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (topCompanies.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  DS.space5, 0, DS.space5, DS.space5),
              child: Text(
                'Aún no hay órdenes facturadas.',
                style: DS.ui(13, color: DS.inkMuted),
              ),
            )
          else ...[
            const Divider(height: 1, color: DS.border),
            ...topCompanies.take(5).map((e) {
              final company = db.companyById(e.key);
              final isLast = topCompanies.indexOf(e) ==
                      (topCompanies.length > 5 ? 4 : topCompanies.length - 1);
              return Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: DS.space5, vertical: DS.space4),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                        color: isLast ? Colors.transparent : DS.border, width: 1),
                  ),
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
                      child: const Icon(Icons.apartment,
                          size: 16, color: DS.brandBlue),
                    ),
                    const SizedBox(width: DS.space3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(company?.name ?? '—',
                              style: DS.ui(13,
                                  color: DS.ink, weight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis),
                          Text('${e.value['count']} órdenes',
                              style: DS.ui(11, color: DS.inkMuted)),
                        ],
                      ),
                    ),
                    Text(
                      formatMoney(e.value['amount'] as double),
                      style: DS.numeric(14, weight: FontWeight.w600),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

// ====================== RECENT ORDERS ======================
class _RecentOrdersCard extends StatelessWidget {
  final List<DeliveryOrder> orders;
  const _RecentOrdersCard({required this.orders});

  @override
  Widget build(BuildContext context) {
    final db = Database.instance;
    final recent = orders.take(8).toList();
    return Container(
      decoration: BoxDecoration(
        color: DS.surfaceRaised,
        borderRadius: BorderRadius.circular(DS.radiusLg),
        border: Border.all(color: DS.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(DS.space5),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Actividad reciente',
                          style: DS.display(17, weight: FontWeight.w500)),
                      Text('Últimas órdenes registradas',
                          style: DS.ui(12, color: DS.inkMuted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (recent.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  DS.space5, 0, DS.space5, DS.space5),
              child: Text(
                'Aún no hay actividad. Las órdenes aparecerán aquí cuando las empresas comiencen a operar.',
                style: DS.ui(13, color: DS.inkMuted, height: 1.6),
              ),
            )
          else ...[
            const Divider(height: 1, color: DS.border),
            ...recent.map((o) {
              final company = db.companyById(o.companyId);
              final rider = db.riderById(o.riderId);
              final isLast = o == recent.last;
              return Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: DS.space5, vertical: DS.space4),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                        color: isLast ? Colors.transparent : DS.border, width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 56,
                      child: Text('#${o.number}',
                          style: DS.numeric(13,
                              color: DS.inkMuted, weight: FontWeight.w600)),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(company?.name ?? '—',
                              style: DS.ui(13,
                                  color: DS.ink, weight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis),
                          Text(
                              rider != null
                                  ? '→ ${rider.name}'
                                  : 'Sin asignar · ${formatDate(o.createdAt)}',
                              style: DS.ui(11, color: DS.inkMuted),
                              overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    const SizedBox(width: DS.space3),
                    Text(formatMoney(o.amount),
                        style: DS.numeric(13, weight: FontWeight.w600)),
                    const SizedBox(width: DS.space3),
                    StatusChip(status: o.status, small: true),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}
