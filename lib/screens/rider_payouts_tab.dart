import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/database.dart';
import '../widgets/design_system.dart';
import '../widgets/components.dart';

/// Pestaña "Mis pagos" para el motorizado.
/// Muestra el historial de liquidaciones que el admin le ha hecho.
class RiderPayoutsTab extends StatefulWidget {
  const RiderPayoutsTab({super.key});

  @override
  State<RiderPayoutsTab> createState() => _RiderPayoutsTabState();
}

class _RiderPayoutsTabState extends State<RiderPayoutsTab> {
  final db = Database.instance;

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
    // myPayouts viene del cache local que se mantiene actualizado
    final payouts = db.myPayouts;

    if (payouts.isEmpty) {
      return const EmptyState(
        icon: Icons.payments_outlined,
        message: 'Aún no tienes pagos registrados',
        hint:
            'Cuando la central liquide tus comisiones aparecerán aquí con todo el detalle.',
      );
    }

    final totalReceived =
        payouts.fold<double>(0, (s, p) => s + p.netAmount);
    final ordersTotal =
        payouts.fold<int>(0, (s, p) => s + p.ordersCount);

    return ListView(
      padding: const EdgeInsets.all(DS.space5),
      children: [
        // Resumen general
        Container(
          padding: const EdgeInsets.all(DS.space5),
          decoration: BoxDecoration(
            color: DS.dark,
            borderRadius: BorderRadius.circular(DS.radiusLg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('TOTAL RECIBIDO',
                  style: DS.eyebrow(
                      color: Colors.white.withValues(alpha: 0.6))),
              const SizedBox(height: 4),
              Text(formatMoney(totalReceived),
                  style: DS.numeric(32,
                      color: Colors.white, weight: FontWeight.w700)),
              const SizedBox(height: DS.space2),
              Row(
                children: [
                  _MetaItem(
                    icon: Icons.payments_outlined,
                    label: '${payouts.length} ${payouts.length == 1 ? "pago" : "pagos"}',
                  ),
                  const SizedBox(width: DS.space4),
                  _MetaItem(
                    icon: Icons.receipt_long_outlined,
                    label: '$ordersTotal ${ordersTotal == 1 ? "orden" : "órdenes"}',
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: DS.space5),

        Text('HISTORIAL DE PAGOS', style: DS.eyebrow()),
        const SizedBox(height: DS.space3),

        // Lista de liquidaciones
        for (final p in payouts) ...[
          _PayoutCard(payout: p),
          const SizedBox(height: DS.space3),
        ],
      ],
    );
  }
}

class _MetaItem extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MetaItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white.withValues(alpha: 0.6), size: 13),
        const SizedBox(width: 6),
        Text(label,
            style: DS.ui(12, color: Colors.white.withValues(alpha: 0.7))),
      ],
    );
  }
}

class _PayoutCard extends StatefulWidget {
  final RiderPayout payout;
  const _PayoutCard({required this.payout});

  @override
  State<_PayoutCard> createState() => _PayoutCardState();
}

class _PayoutCardState extends State<_PayoutCard> {
  bool _expanded = false;
  RiderPayout? _detail;
  bool _loadingDetail = false;

  Future<void> _toggle() async {
    if (!_expanded && _detail == null) {
      setState(() => _loadingDetail = true);
      final d = await Database.instance.fetchPayoutById(widget.payout.id);
      if (!mounted) return;
      setState(() {
        _detail = d;
        _loadingDetail = false;
        _expanded = true;
      });
    } else {
      setState(() => _expanded = !_expanded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.payout;
    return Container(
      decoration: BoxDecoration(
        color: DS.surfaceRaised,
        borderRadius: BorderRadius.circular(DS.radiusLg),
        border: Border.all(color: DS.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header (clickeable)
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _toggle,
              borderRadius: BorderRadius.vertical(
                top: const Radius.circular(DS.radiusLg),
                bottom:
                    _expanded ? Radius.zero : const Radius.circular(DS.radiusLg),
              ),
              child: Padding(
                padding: const EdgeInsets.all(DS.space4),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: DS.success.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(DS.radiusMd),
                      ),
                      child: const Icon(Icons.check_circle,
                          color: DS.success, size: 18),
                    ),
                    const SizedBox(width: DS.space3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Pago recibido',
                              style: DS.ui(13, weight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(formatDateLong(p.paidAt),
                              style:
                                  DS.ui(11, color: DS.inkMuted)),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(formatMoney(p.netAmount),
                            style: DS.numeric(18,
                                weight: FontWeight.w700,
                                color: DS.success)),
                        Text(
                            '${p.ordersCount} ${p.ordersCount == 1 ? "orden" : "órdenes"}',
                            style:
                                DS.ui(10, color: DS.inkMuted)),
                      ],
                    ),
                    const SizedBox(width: DS.space2),
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      color: DS.inkMuted,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Detalle expandible
          if (_expanded) ...[
            const Divider(height: 1, color: DS.border),

            // Resumen contable
            Padding(
              padding: const EdgeInsets.all(DS.space4),
              child: Container(
                padding: const EdgeInsets.all(DS.space3),
                decoration: BoxDecoration(
                  color: DS.surfaceMuted,
                  borderRadius: BorderRadius.circular(DS.radiusSm),
                ),
                child: Column(
                  children: [
                    _InfoLine(
                      label: 'Periodo',
                      value:
                          '${formatDate(p.periodStart)} → ${formatDate(p.periodEnd)}',
                    ),
                    const SizedBox(height: DS.space2),
                    _InfoLine(
                      label: 'Comisiones brutas',
                      value: formatMoney(p.commissionsTotal),
                    ),
                    if (p.discountTotal > 0) ...[
                      const SizedBox(height: DS.space2),
                      _InfoLine(
                        label: 'Descuentos',
                        value: '- ${formatMoney(p.discountTotal)}',
                        valueColor: DS.danger,
                      ),
                    ],
                    const SizedBox(height: DS.space3),
                    Container(height: 1, color: DS.border),
                    const SizedBox(height: DS.space3),
                    _InfoLine(
                      label: 'Neto recibido',
                      value: formatMoney(p.netAmount),
                      valueColor: DS.success,
                      bold: true,
                    ),
                  ],
                ),
              ),
            ),

            // Nota (si hay)
            if (p.note != null && p.note!.trim().isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    DS.space4, 0, DS.space4, DS.space3),
                child: Container(
                  padding: const EdgeInsets.all(DS.space3),
                  decoration: BoxDecoration(
                    color: DS.infoBg,
                    borderRadius: BorderRadius.circular(DS.radiusSm),
                    border: Border.all(
                        color: DS.info.withValues(alpha: 0.2), width: 1),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.notes,
                          color: DS.info, size: 14),
                      const SizedBox(width: DS.space2),
                      Expanded(
                        child: Text(p.note!,
                            style: DS.ui(12,
                                color: DS.info, height: 1.5)),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            // Detalle de órdenes (con loading)
            if (_loadingDetail)
              const Padding(
                padding: EdgeInsets.all(DS.space5),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: DS.brandOrange),
                  ),
                ),
              )
            else if (_detail != null && _detail!.items.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    DS.space4, 0, DS.space4, DS.space2),
                child: Text('ÓRDENES INCLUIDAS', style: DS.eyebrow()),
              ),
              for (final item in _detail!.items) ...[
                _OrderItemRow(item: item),
                if (item != _detail!.items.last)
                  const Divider(height: 1, color: DS.border),
              ],
              const SizedBox(height: DS.space2),
            ],
          ],
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool bold;

  const _InfoLine({
    required this.label,
    required this.value,
    this.valueColor,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: DS.ui(11,
                color: DS.inkSecondary,
                weight: bold ? FontWeight.w600 : FontWeight.w500)),
        Text(value,
            style: DS.numeric(bold ? 14 : 12,
                color: valueColor ?? DS.ink,
                weight: bold ? FontWeight.w700 : FontWeight.w600)),
      ],
    );
  }
}

class _OrderItemRow extends StatelessWidget {
  final PayoutItem item;
  const _OrderItemRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: DS.space4, vertical: DS.space3),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('#${item.number}',
                        style:
                            DS.numeric(13, weight: FontWeight.w700)),
                    const SizedBox(width: DS.space2),
                    if (item.deliveredAt != null)
                      Text(formatDate(item.deliveredAt!),
                          style: DS.ui(11, color: DS.inkMuted)),
                  ],
                ),
                if (item.customer.isNotEmpty)
                  Text(item.customer,
                      style: DS.ui(11, color: DS.inkSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: DS.space3),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (item.orderDiscount > 0) ...[
                Text(formatMoney(item.commission),
                    style: DS.numeric(11,
                        color: DS.inkMuted,
                        weight: FontWeight.w500)),
                Text('- ${formatMoney(item.orderDiscount)}',
                    style: DS.numeric(10,
                        color: DS.danger, weight: FontWeight.w600)),
                Text(formatMoney(item.net),
                    style: DS.numeric(13,
                        color: DS.success,
                        weight: FontWeight.w700)),
              ] else
                Text(formatMoney(item.commission),
                    style: DS.numeric(13,
                        color: DS.success,
                        weight: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }
}
