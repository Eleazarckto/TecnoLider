import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../services/database.dart';
import '../../widgets/design_system.dart';
import '../../widgets/components.dart';

/// Pantalla de admin: Cuentas pendientes (deudas)
/// Muestra todas las órdenes "pagar después" sin pagar, agrupadas por empresa.
/// Permite marcarlas como pagadas.
class AdminDebts extends StatefulWidget {
  const AdminDebts({super.key});

  @override
  State<AdminDebts> createState() => _AdminDebtsState();
}

class _AdminDebtsState extends State<AdminDebts> {
  final db = Database.instance;
  String? _expandedCompanyId;

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
    // Trabajamos sobre el cache local — instantáneo y se actualiza con sync
    final allDebts = db.debtOrders();

    if (allDebts.isEmpty) {
      return const EmptyState(
        icon: Icons.check_circle_outline,
        message: '¡No hay cuentas pendientes!',
        hint:
            'Todas las órdenes a crédito están pagadas. Cuando una empresa elija "pagar después" aparecerá aquí.',
      );
    }

    // Agrupar por empresa
    final byCompany = <String, List<DeliveryOrder>>{};
    for (final o in allDebts) {
      byCompany.putIfAbsent(o.companyId, () => []).add(o);
    }

    final grandTotal =
        allDebts.fold<double>(0, (s, o) => s + o.amount);

    return Column(
      children: [
        _SummaryHeader(
          totalCount: allDebts.length,
          totalAmount: grandTotal,
          companyCount: byCompany.length,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(DS.space5),
            children: [
              for (final entry in byCompany.entries) ...[
                _CompanyDebtBlock(
                  companyId: entry.key,
                  orders: entry.value,
                  expanded: _expandedCompanyId == entry.key,
                  onToggle: () {
                    setState(() {
                      _expandedCompanyId =
                          _expandedCompanyId == entry.key ? null : entry.key;
                    });
                  },
                  onMarkPaid: _markPaid,
                ),
                const SizedBox(height: DS.space3),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _markPaid(DeliveryOrder order) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Marcar como pagada',
      message:
          'La orden #${order.number} por ${formatMoney(order.amount)} se marcará como pagada y saldrá de cuentas pendientes. ¿Continuar?',
      confirmLabel: 'Marcar pagada',
    );
    if (!ok) return;

    try {
      await db.markOrderPaid(order.id);
      if (mounted) {
        showSuccessSnack(
          context,
          'Orden #${order.number} marcada como pagada',
        );
      }
    } catch (e) {
      if (mounted) showErrorSnack(context, 'Error: $e');
    }
  }
}

// ============ HEADER CON RESUMEN ============
class _SummaryHeader extends StatelessWidget {
  final int totalCount;
  final double totalAmount;
  final int companyCount;

  const _SummaryHeader({
    required this.totalCount,
    required this.totalAmount,
    required this.companyCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DS.space5),
      decoration: const BoxDecoration(
        color: DS.surfaceRaised,
        border: Border(bottom: BorderSide(color: DS.border, width: 1)),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: DS.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(DS.radiusMd),
            ),
            child: const Icon(Icons.receipt_long_outlined,
                color: DS.warning, size: 26),
          ),
          const SizedBox(width: DS.space4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('TOTAL POR COBRAR', style: DS.eyebrow()),
                const SizedBox(height: 4),
                Text(
                  formatMoney(totalAmount),
                  style: DS.numeric(28,
                      weight: FontWeight.w700, color: DS.warning),
                ),
                Text(
                  '$totalCount ${totalCount == 1 ? "orden" : "órdenes"} · $companyCount ${companyCount == 1 ? "empresa" : "empresas"}',
                  style: DS.ui(12, color: DS.inkMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============ BLOQUE POR EMPRESA ============
class _CompanyDebtBlock extends StatelessWidget {
  final String companyId;
  final List<DeliveryOrder> orders;
  final bool expanded;
  final VoidCallback onToggle;
  final Future<void> Function(DeliveryOrder) onMarkPaid;

  const _CompanyDebtBlock({
    required this.companyId,
    required this.orders,
    required this.expanded,
    required this.onToggle,
    required this.onMarkPaid,
  });

  @override
  Widget build(BuildContext context) {
    final db = Database.instance;
    final company = db.companyById(companyId);
    final total = orders.fold<double>(0, (s, o) => s + o.amount);
    final companyName = company?.name ?? 'Empresa eliminada';
    final creditLimit = company?.creditLimit ?? 0;
    final overLimit = creditLimit > 0 && total > creditLimit;

    return Container(
      decoration: BoxDecoration(
        color: DS.surfaceRaised,
        borderRadius: BorderRadius.circular(DS.radiusLg),
        border: Border.all(
          color: overLimit ? DS.danger.withValues(alpha: 0.3) : DS.border,
          width: overLimit ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header colapsable
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.vertical(
                top: const Radius.circular(DS.radiusLg),
                bottom: expanded ? Radius.zero : const Radius.circular(DS.radiusLg),
              ),
              child: Padding(
                padding: const EdgeInsets.all(DS.space4),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: DS.brandOrange.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(DS.radiusMd),
                      ),
                      child: Center(
                        child: Text(
                          companyName.isNotEmpty
                              ? companyName[0].toUpperCase()
                              : '?',
                          style: DS.display(15,
                              color: DS.brandOrangeDeep,
                              weight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(width: DS.space3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(companyName,
                                    style: DS.ui(14,
                                        weight: FontWeight.w600),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              ),
                              if (overLimit)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color:
                                        DS.danger.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(
                                        DS.radiusSm),
                                  ),
                                  child: Text(
                                    'EXCEDE LÍMITE',
                                    style: DS.ui(9,
                                        color: DS.danger,
                                        weight: FontWeight.w700),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${orders.length} ${orders.length == 1 ? "orden" : "órdenes"} pendientes${creditLimit > 0 ? " · Límite: ${formatMoney(creditLimit)}" : ""}',
                            style: DS.ui(11, color: DS.inkMuted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: DS.space3),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(formatMoney(total),
                            style: DS.numeric(16,
                                weight: FontWeight.w700,
                                color: overLimit
                                    ? DS.danger
                                    : DS.warning)),
                        Text('por cobrar',
                            style: DS.ui(10, color: DS.inkMuted)),
                      ],
                    ),
                    const SizedBox(width: DS.space2),
                    Icon(
                      expanded
                          ? Icons.expand_less
                          : Icons.expand_more,
                      color: DS.inkMuted,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Detalle de órdenes (al expandir)
          if (expanded) ...[
            const Divider(height: 1, color: DS.border),
            for (var i = 0; i < orders.length; i++) ...[
              _DebtOrderRow(
                order: orders[i],
                onMarkPaid: () => onMarkPaid(orders[i]),
              ),
              if (i < orders.length - 1)
                const Divider(height: 1, color: DS.border),
            ],
          ],
        ],
      ),
    );
  }
}

// ============ FILA DE UNA ORDEN-DEUDA ============
class _DebtOrderRow extends StatelessWidget {
  final DeliveryOrder order;
  final VoidCallback onMarkPaid;
  const _DebtOrderRow({required this.order, required this.onMarkPaid});

  @override
  Widget build(BuildContext context) {
    final daysOld = DateTime.now().difference(order.createdAt).inDays;
    return Padding(
      padding: const EdgeInsets.all(DS.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Text('Orden #${order.number}',
                        style:
                            DS.numeric(14, weight: FontWeight.w700)),
                    const SizedBox(width: DS.space2),
                    Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: DS.inkMuted,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: DS.space2),
                    Flexible(
                      child: Text(
                        formatDate(order.createdAt),
                        style: DS.ui(11, color: DS.inkMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              if (daysOld >= 7)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: DS.danger.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(DS.radiusSm),
                  ),
                  child: Text(
                    '$daysOld días',
                    style: DS.ui(9,
                        color: DS.danger, weight: FontWeight.w700),
                  ),
                )
              else if (daysOld >= 3)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: DS.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(DS.radiusSm),
                  ),
                  child: Text(
                    '$daysOld días',
                    style: DS.ui(9,
                        color: DS.warning,
                        weight: FontWeight.w700),
                  ),
                ),
            ],
          ),
          const SizedBox(height: DS.space2),
          InfoRow(
              icon: Icons.person_outline,
              label: 'Cliente',
              value: '${order.customer} · ${order.customerPhone}'),
          InfoRow(
              icon: Icons.location_on_outlined,
              label: 'Dirección',
              value: order.address),
          if (order.description.isNotEmpty)
            InfoRow(
                icon: Icons.inventory_2_outlined,
                label: 'Detalle',
                value: order.description),
          const SizedBox(height: DS.space3),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: DS.space3, vertical: DS.space3),
                  decoration: BoxDecoration(
                    color: DS.warning.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(DS.radiusSm),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('MONTO', style: DS.eyebrow()),
                      const SizedBox(height: 2),
                      Text(formatMoney(order.amount),
                          style: DS.numeric(16,
                              weight: FontWeight.w700,
                              color: DS.warning)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: DS.space3),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onMarkPaid,
                  icon: const Icon(Icons.check_circle_outline, size: 16),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('Pagada'),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: DS.success,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
