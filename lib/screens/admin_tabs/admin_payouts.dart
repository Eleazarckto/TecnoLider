import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../services/database.dart';
import '../../widgets/design_system.dart';
import '../../widgets/components.dart';

/// Pantalla de admin: Liquidaciones (pagos a motorizados)
/// Tiene 2 secciones (TabBar):
///   1. Pendiente: calcula liquidación por rango de fechas y permite pagar
///   2. Historial: liquidaciones ya hechas
class AdminPayouts extends StatefulWidget {
  const AdminPayouts({super.key});

  @override
  State<AdminPayouts> createState() => _AdminPayoutsState();
}

class _AdminPayoutsState extends State<AdminPayouts>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: DS.surfaceRaised,
          child: TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: DS.brandOrange,
            unselectedLabelColor: DS.inkSecondary,
            indicatorColor: DS.brandOrange,
            indicatorWeight: 2.5,
            labelStyle: DS.ui(13, weight: FontWeight.w600),
            unselectedLabelStyle: DS.ui(13, weight: FontWeight.w500),
            tabs: const [
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.calculate_outlined, size: 16),
                    SizedBox(width: 8),
                    Text('Liquidar'),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.history, size: 16),
                    SizedBox(width: 8),
                    Text('Historial'),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: const [
              _PendingPayoutTab(),
              _PayoutHistoryTab(),
            ],
          ),
        ),
      ],
    );
  }
}

// ======================================================================
//  TAB 1: LIQUIDAR (calcular y pagar)
// ======================================================================
class _PendingPayoutTab extends StatefulWidget {
  const _PendingPayoutTab();

  @override
  State<_PendingPayoutTab> createState() => _PendingPayoutTabState();
}

class _PendingPayoutTabState extends State<_PendingPayoutTab> {
  final db = Database.instance;
  late DateTime _from;
  late DateTime _to;
  PayoutPreview? _preview;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, now.day - 7);
    _to = DateTime(now.year, now.month, now.day);
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    setState(() => _loading = true);
    try {
      final preview = await db.previewPayouts(from: _from, to: _to);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showErrorSnack(context, 'Error: $e');
    }
  }

  Future<void> _pickDate(bool isFrom) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? _from : _to,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
        if (_to.isBefore(_from)) _to = _from;
      } else {
        _to = picked;
        if (_from.isAfter(_to)) _from = _to;
      }
    });
    _loadPreview();
  }

  void _setQuickRange(int days) {
    final now = DateTime.now();
    setState(() {
      _to = DateTime(now.year, now.month, now.day);
      _from = DateTime(now.year, now.month, now.day - days);
    });
    _loadPreview();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ----- Selector de rango de fechas -----
        Container(
          padding: const EdgeInsets.all(DS.space5),
          decoration: const BoxDecoration(
            color: DS.surfaceRaised,
            border: Border(bottom: BorderSide(color: DS.border, width: 1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _DateButton(
                      label: 'DESDE',
                      date: _from,
                      onTap: () => _pickDate(true),
                    ),
                  ),
                  Container(
                    width: 24,
                    alignment: Alignment.center,
                    child: const Icon(Icons.arrow_forward,
                        color: DS.inkMuted, size: 16),
                  ),
                  Expanded(
                    child: _DateButton(
                      label: 'HASTA',
                      date: _to,
                      onTap: () => _pickDate(false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: DS.space3),
              Wrap(
                spacing: DS.space2,
                children: [
                  _QuickRangeChip(label: 'Hoy', onTap: () => _setQuickRange(0)),
                  _QuickRangeChip(
                      label: '7 días', onTap: () => _setQuickRange(7)),
                  _QuickRangeChip(
                      label: '15 días', onTap: () => _setQuickRange(15)),
                  _QuickRangeChip(
                      label: '30 días', onTap: () => _setQuickRange(30)),
                ],
              ),
            ],
          ),
        ),

        // ----- Contenido del preview -----
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: DS.brandOrange))
              : _buildPreviewContent(),
        ),
      ],
    );
  }

  Widget _buildPreviewContent() {
    final preview = _preview;
    if (preview == null || preview.riders.isEmpty) {
      return EmptyState(
        icon: Icons.calculate_outlined,
        message: 'Sin comisiones por liquidar',
        hint:
            'No hay órdenes entregadas pendientes de pago en este rango de fechas. Ajusta las fechas o espera a que se entreguen más órdenes.',
        action: OutlinedButton.icon(
          onPressed: _loadPreview,
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('Refrescar'),
        ),
      );
    }

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
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: DS.brandOrange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(DS.radiusMd),
                ),
                child: const Icon(Icons.payments_outlined,
                    color: DS.brandOrange, size: 26),
              ),
              const SizedBox(width: DS.space4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('TOTAL POR LIQUIDAR',
                        style: DS.eyebrow(
                            color: Colors.white.withValues(alpha: 0.6))),
                    const SizedBox(height: 4),
                    Text(formatMoney(preview.grandTotal),
                        style: DS.numeric(28,
                            color: Colors.white,
                            weight: FontWeight.w700)),
                    Text(
                      '${preview.totalOrders} ${preview.totalOrders == 1 ? "orden" : "órdenes"} · ${preview.riders.length} ${preview.riders.length == 1 ? "motorizado" : "motorizados"}',
                      style: DS.ui(12,
                          color: Colors.white.withValues(alpha: 0.7)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: DS.space4),
        // Por motorizado
        Text('POR MOTORIZADO', style: DS.eyebrow()),
        const SizedBox(height: DS.space3),
        for (final r in preview.riders) ...[
          _RiderPayoutCard(
            rider: r,
            periodStart: _from,
            periodEnd: _to,
            onPaid: _loadPreview,
          ),
          const SizedBox(height: DS.space3),
        ],
      ],
    );
  }
}

// ============ TARJETA POR MOTORIZADO ============
class _RiderPayoutCard extends StatelessWidget {
  final RiderPayoutPreview rider;
  final DateTime periodStart;
  final DateTime periodEnd;
  final VoidCallback onPaid;

  const _RiderPayoutCard({
    required this.rider,
    required this.periodStart,
    required this.periodEnd,
    required this.onPaid,
  });

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
            padding: const EdgeInsets.all(DS.space4),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: DS.brandOrange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(DS.radiusMd),
                  ),
                  child: Center(
                    child: Text(
                      rider.riderName.isNotEmpty
                          ? rider.riderName[0].toUpperCase()
                          : '?',
                      style: DS.display(18,
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
                      Text(rider.riderName,
                          style: DS.display(16, weight: FontWeight.w600)),
                      Text(
                          '${rider.count} ${rider.count == 1 ? "orden" : "órdenes"}'
                          '${rider.plate.isNotEmpty ? " · ${rider.plate}" : ""}',
                          style: DS.ui(11, color: DS.inkMuted)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(formatMoney(rider.commissionsTotal),
                        style: DS.numeric(20,
                            weight: FontWeight.w700, color: DS.warning)),
                    Text('a cobrar',
                        style: DS.ui(10, color: DS.inkMuted)),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: DS.border),
          Padding(
            padding: const EdgeInsets.all(DS.space3),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _openPayoutDialog(context),
                icon: const Icon(Icons.payments_outlined, size: 16),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text('Liquidar y marcar como pagado'),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: DS.success,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openPayoutDialog(BuildContext context) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _PayoutDetailScreen(
          rider: rider,
          periodStart: periodStart,
          periodEnd: periodEnd,
        ),
      ),
    );
    if (result == true) onPaid();
  }
}

// ============ DETALLE DE LIQUIDACIÓN ============
class _PayoutDetailScreen extends StatefulWidget {
  final RiderPayoutPreview rider;
  final DateTime periodStart;
  final DateTime periodEnd;

  const _PayoutDetailScreen({
    required this.rider,
    required this.periodStart,
    required this.periodEnd,
  });

  @override
  State<_PayoutDetailScreen> createState() => _PayoutDetailScreenState();
}

class _PayoutDetailScreenState extends State<_PayoutDetailScreen> {
  late Set<String> _selectedOrders;
  late Map<String, double> _orderDiscounts;
  double _discountTotal = 0;
  final _noteController = TextEditingController();
  final _discountTotalController = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedOrders = widget.rider.orders.map((o) => o.id).toSet();
    _orderDiscounts = {for (final o in widget.rider.orders) o.id: 0.0};
  }

  @override
  void dispose() {
    _noteController.dispose();
    _discountTotalController.dispose();
    super.dispose();
  }

  double get _commissionsTotal {
    double total = 0;
    for (final o in widget.rider.orders) {
      if (_selectedOrders.contains(o.id)) total += o.riderCommission;
    }
    return total;
  }

  double get _orderDiscountsTotal {
    double total = 0;
    for (final id in _selectedOrders) {
      total += _orderDiscounts[id] ?? 0;
    }
    return total;
  }

  double get _netAmount {
    final n = _commissionsTotal - _orderDiscountsTotal - _discountTotal;
    return n < 0 ? 0 : n;
  }

  Future<void> _confirm() async {
    if (_selectedOrders.isEmpty) {
      showErrorSnack(context, 'Selecciona al menos una orden');
      return;
    }

    final ok = await showConfirmDialog(
      context,
      title: 'Confirmar liquidación',
      message:
          'Pagar ${formatMoney(_netAmount)} a ${widget.rider.riderName} por ${_selectedOrders.length} ${_selectedOrders.length == 1 ? "orden" : "órdenes"}. Esta acción no se puede deshacer.',
      confirmLabel: 'Marcar como pagado',
    );
    if (!ok) return;

    setState(() => _saving = true);
    try {
      // Solo enviar descuentos > 0
      final discountsToSend = <String, double>{};
      for (final entry in _orderDiscounts.entries) {
        if (_selectedOrders.contains(entry.key) && entry.value > 0) {
          discountsToSend[entry.key] = entry.value;
        }
      }

      await Database.instance.createPayout(
        riderId: widget.rider.riderId,
        periodStart: widget.periodStart,
        periodEnd: widget.periodEnd,
        orderIds: _selectedOrders.toList(),
        orderDiscounts: discountsToSend,
        discountTotal: _discountTotal,
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
      );

      if (!mounted) return;
      Navigator.pop(context, true);
      showSuccessSnack(context,
          '✓ Liquidación creada · ${formatMoney(_netAmount)} pagado a ${widget.rider.riderName}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showErrorSnack(context, 'Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DS.surface,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Liquidar a ${widget.rider.riderName}',
                style: DS.display(16, weight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            Text(
              '${formatDate(widget.periodStart)} → ${formatDate(widget.periodEnd)}',
              style: DS.ui(11, color: DS.inkMuted),
            ),
          ],
        ),
        backgroundColor: DS.surfaceRaised,
        foregroundColor: DS.ink,
        elevation: 0,
        shape: const Border(bottom: BorderSide(color: DS.border)),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(DS.space5),
              children: [
                // Resumen
                _SummaryBox(
                  commissionsTotal: _commissionsTotal,
                  orderDiscountsTotal: _orderDiscountsTotal,
                  totalDiscount: _discountTotal,
                  netAmount: _netAmount,
                  ordersCount: _selectedOrders.length,
                ),
                const SizedBox(height: DS.space5),

                // Órdenes
                Text('ÓRDENES (${widget.rider.orders.length})',
                    style: DS.eyebrow()),
                const SizedBox(height: DS.space2),
                Text(
                  'Desmarca las que no quieras incluir. Aplica descuento por orden si corresponde.',
                  style: DS.ui(12, color: DS.inkMuted),
                ),
                const SizedBox(height: DS.space3),

                for (final o in widget.rider.orders) ...[
                  _OrderRow(
                    order: o,
                    selected: _selectedOrders.contains(o.id),
                    discount: _orderDiscounts[o.id] ?? 0,
                    onToggle: () {
                      setState(() {
                        if (_selectedOrders.contains(o.id)) {
                          _selectedOrders.remove(o.id);
                        } else {
                          _selectedOrders.add(o.id);
                        }
                      });
                    },
                    onDiscountChanged: (v) {
                      setState(() {
                        _orderDiscounts[o.id] = v;
                      });
                    },
                  ),
                  const SizedBox(height: DS.space2),
                ],

                const SizedBox(height: DS.space4),
                Text('DESCUENTO ADICIONAL', style: DS.eyebrow()),
                const SizedBox(height: DS.space2),
                Text(
                  'Descuento extra que se resta del total final (ej: deudas anteriores, multas).',
                  style: DS.ui(12, color: DS.inkMuted),
                ),
                const SizedBox(height: DS.space3),
                _DiscountTotalInput(
                  controller: _discountTotalController,
                  onChanged: (v) {
                    setState(() => _discountTotal = v);
                  },
                ),

                const SizedBox(height: DS.space4),
                Text('NOTA (OPCIONAL)', style: DS.eyebrow()),
                const SizedBox(height: DS.space2),
                TextField(
                  controller: _noteController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    hintText: 'Observaciones del pago...',
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(DS.space4),
            decoration: const BoxDecoration(
              color: DS.surfaceRaised,
              border: Border(top: BorderSide(color: DS.border, width: 1)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('NETO A PAGAR', style: DS.eyebrow()),
                      Text(formatMoney(_netAmount),
                          style: DS.numeric(22,
                              weight: FontWeight.w700, color: DS.success)),
                    ],
                  ),
                  const SizedBox(height: DS.space3),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _saving
                              ? null
                              : () => Navigator.pop(context),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 4),
                            child: Text('Cancelar'),
                          ),
                        ),
                      ),
                      const SizedBox(width: DS.space3),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed:
                              _saving || _netAmount <= 0 ? null : _confirm,
                          icon: _saving
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.check, size: 16),
                          label: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text(_saving
                                ? 'Procesando...'
                                : 'Marcar como pagado'),
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
            ),
          ),
        ],
      ),
    );
  }
}

// ============ COMPONENTES AUXILIARES ============
class _SummaryBox extends StatelessWidget {
  final double commissionsTotal;
  final double orderDiscountsTotal;
  final double totalDiscount;
  final double netAmount;
  final int ordersCount;

  const _SummaryBox({
    required this.commissionsTotal,
    required this.orderDiscountsTotal,
    required this.totalDiscount,
    required this.netAmount,
    required this.ordersCount,
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
      child: Column(
        children: [
          _row('Comisiones brutas',
              '${formatMoney(commissionsTotal)} ($ordersCount órd.)',
              color: DS.ink),
          if (orderDiscountsTotal > 0) ...[
            const SizedBox(height: DS.space2),
            _row(
                'Descuentos por orden', '- ${formatMoney(orderDiscountsTotal)}',
                color: DS.danger),
          ],
          if (totalDiscount > 0) ...[
            const SizedBox(height: DS.space2),
            _row('Descuento adicional', '- ${formatMoney(totalDiscount)}',
                color: DS.danger),
          ],
          const SizedBox(height: DS.space3),
          Container(height: 1, color: DS.border),
          const SizedBox(height: DS.space3),
          _row('Neto a pagar', formatMoney(netAmount),
              color: DS.success, bold: true),
        ],
      ),
    );
  }

  Widget _row(String label, String value,
      {required Color color, bool bold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: DS.ui(12,
                color: DS.inkSecondary,
                weight: bold ? FontWeight.w600 : FontWeight.w500)),
        Text(value,
            style: DS.numeric(bold ? 16 : 13,
                color: color,
                weight: bold ? FontWeight.w700 : FontWeight.w600)),
      ],
    );
  }
}

class _OrderRow extends StatefulWidget {
  final PayoutOrderPreview order;
  final bool selected;
  final double discount;
  final VoidCallback onToggle;
  final ValueChanged<double> onDiscountChanged;

  const _OrderRow({
    required this.order,
    required this.selected,
    required this.discount,
    required this.onToggle,
    required this.onDiscountChanged,
  });

  @override
  State<_OrderRow> createState() => _OrderRowState();
}

class _OrderRowState extends State<_OrderRow> {
  late TextEditingController _discount;

  @override
  void initState() {
    super.initState();
    _discount = TextEditingController(
        text: widget.discount > 0 ? widget.discount.toStringAsFixed(2) : '');
  }

  @override
  void dispose() {
    _discount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final net = widget.order.riderCommission - widget.discount;
    return Container(
      padding: const EdgeInsets.all(DS.space3),
      decoration: BoxDecoration(
        color: widget.selected
            ? DS.surfaceRaised
            : DS.surfaceRaised.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(DS.radiusMd),
        border: Border.all(
            color: widget.selected
                ? DS.brandOrange.withValues(alpha: 0.3)
                : DS.border,
            width: widget.selected ? 1.5 : 1),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Checkbox(
                value: widget.selected,
                onChanged: (_) => widget.onToggle(),
                activeColor: DS.brandOrange,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('#${widget.order.number}',
                            style: DS.numeric(13, weight: FontWeight.w700)),
                        const SizedBox(width: DS.space2),
                        Text(
                          widget.order.deliveredAt != null
                              ? formatDate(widget.order.deliveredAt!)
                              : '—',
                          style: DS.ui(11, color: DS.inkMuted),
                        ),
                      ],
                    ),
                    if (widget.order.customer.isNotEmpty)
                      Text(widget.order.customer,
                          style: DS.ui(11, color: DS.inkSecondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(formatMoney(widget.order.riderCommission),
                      style: DS.numeric(13,
                          weight: FontWeight.w700,
                          color: widget.selected ? DS.warning : DS.inkMuted)),
                  Text('comisión',
                      style: DS.ui(9, color: DS.inkMuted)),
                ],
              ),
            ],
          ),
          if (widget.selected) ...[
            const SizedBox(height: DS.space2),
            Row(
              children: [
                const Icon(Icons.remove_circle_outline,
                    color: DS.inkMuted, size: 14),
                const SizedBox(width: DS.space2),
                Text('Descuento',
                    style: DS.ui(11,
                        color: DS.inkMuted, weight: FontWeight.w500)),
                const SizedBox(width: DS.space3),
                Expanded(
                  child: SizedBox(
                    height: 32,
                    child: TextField(
                      controller: _discount,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      style: DS.numeric(12),
                      textAlign: TextAlign.right,
                      decoration: const InputDecoration(
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        hintText: '0',
                        isDense: true,
                      ),
                      onChanged: (v) {
                        final n = double.tryParse(v) ?? 0;
                        final clamped = n < 0
                            ? 0.0
                            : (n > widget.order.riderCommission
                                ? widget.order.riderCommission
                                : n);
                        widget.onDiscountChanged(clamped);
                      },
                    ),
                  ),
                ),
                const SizedBox(width: DS.space3),
                SizedBox(
                  width: 80,
                  child: Text(
                    formatMoney(net < 0 ? 0 : net),
                    style: DS.numeric(13,
                        weight: FontWeight.w700, color: DS.success),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DiscountTotalInput extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<double> onChanged;
  const _DiscountTotalInput(
      {required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final db = Database.instance;
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        hintText: '0.00',
        prefixText: '${db.config.currencySymbol} ',
        prefixIcon: const Icon(Icons.remove_circle_outline,
            color: DS.danger, size: 18),
      ),
      onChanged: (v) {
        final n = double.tryParse(v) ?? 0;
        onChanged(n < 0 ? 0 : n);
      },
    );
  }
}

class _DateButton extends StatelessWidget {
  final String label;
  final DateTime date;
  final VoidCallback onTap;
  const _DateButton(
      {required this.label, required this.date, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: DS.surfaceMuted,
      borderRadius: BorderRadius.circular(DS.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DS.radiusMd),
        child: Container(
          padding: const EdgeInsets.all(DS.space3),
          decoration: BoxDecoration(
            border: Border.all(color: DS.border, width: 1),
            borderRadius: BorderRadius.circular(DS.radiusMd),
          ),
          child: Row(
            children: [
              const Icon(Icons.calendar_today_outlined,
                  color: DS.inkMuted, size: 14),
              const SizedBox(width: DS.space2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: DS.eyebrow()),
                    const SizedBox(height: 2),
                    Text(formatDate(date),
                        style: DS.ui(12, weight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickRangeChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _QuickRangeChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DS.radiusSm),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: DS.space3, vertical: 6),
        decoration: BoxDecoration(
          color: DS.surfaceMuted,
          borderRadius: BorderRadius.circular(DS.radiusSm),
          border: Border.all(color: DS.border, width: 1),
        ),
        child: Text(label,
            style: DS.ui(11,
                color: DS.inkSecondary, weight: FontWeight.w600)),
      ),
    );
  }
}

// ======================================================================
//  TAB 2: HISTORIAL DE LIQUIDACIONES
// ======================================================================
class _PayoutHistoryTab extends StatefulWidget {
  const _PayoutHistoryTab();

  @override
  State<_PayoutHistoryTab> createState() => _PayoutHistoryTabState();
}

class _PayoutHistoryTabState extends State<_PayoutHistoryTab> {
  List<RiderPayout> _payouts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await Database.instance.fetchPayouts();
    if (!mounted) return;
    setState(() {
      _payouts = list;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: DS.brandOrange));
    }
    if (_payouts.isEmpty) {
      return EmptyState(
        icon: Icons.history,
        message: 'Sin liquidaciones registradas',
        hint:
            'Aquí verás el historial completo de pagos a motorizados que has realizado.',
        action: OutlinedButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('Refrescar'),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: DS.brandOrange,
      child: ListView.separated(
        padding: const EdgeInsets.all(DS.space5),
        itemCount: _payouts.length,
        separatorBuilder: (_, __) => const SizedBox(height: DS.space3),
        itemBuilder: (context, i) => _HistoryCard(payout: _payouts[i]),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final RiderPayout payout;
  const _HistoryCard({required this.payout});

  @override
  Widget build(BuildContext context) {
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
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: DS.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(DS.radiusSm),
                ),
                child: const Icon(Icons.check_circle,
                    color: DS.success, size: 18),
              ),
              const SizedBox(width: DS.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(payout.riderName ?? '—',
                        style: DS.ui(14, weight: FontWeight.w700)),
                    Text(
                      'Pagado el ${formatDate(payout.paidAt)}',
                      style: DS.ui(11, color: DS.inkMuted),
                    ),
                  ],
                ),
              ),
              Text(formatMoney(payout.netAmount),
                  style: DS.numeric(18,
                      weight: FontWeight.w700, color: DS.success)),
            ],
          ),
          const SizedBox(height: DS.space3),
          Container(
            padding: const EdgeInsets.all(DS.space3),
            decoration: BoxDecoration(
              color: DS.surfaceMuted,
              borderRadius: BorderRadius.circular(DS.radiusSm),
            ),
            child: Column(
              children: [
                _row('Periodo',
                    '${formatDate(payout.periodStart)} → ${formatDate(payout.periodEnd)}'),
                const SizedBox(height: 4),
                _row('Órdenes', '${payout.ordersCount}'),
                const SizedBox(height: 4),
                _row('Comisiones', formatMoney(payout.commissionsTotal)),
                if (payout.discountTotal > 0) ...[
                  const SizedBox(height: 4),
                  _row('Descuentos', '- ${formatMoney(payout.discountTotal)}',
                      color: DS.danger),
                ],
              ],
            ),
          ),
          if (payout.note != null && payout.note!.isNotEmpty) ...[
            const SizedBox(height: DS.space3),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.notes, color: DS.inkMuted, size: 14),
                const SizedBox(width: DS.space2),
                Expanded(
                  child: Text(payout.note!,
                      style:
                          DS.ui(12, color: DS.inkSecondary, height: 1.4)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, String value, {Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: DS.ui(11, color: DS.inkMuted)),
        Text(value,
            style: DS.numeric(12,
                color: color ?? DS.ink, weight: FontWeight.w600)),
      ],
    );
  }
}
