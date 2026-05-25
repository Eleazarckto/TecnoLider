import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../services/database.dart';
import '../../widgets/design_system.dart';
import '../../widgets/components.dart';

/// Operations panel for admin/superAdmin.
/// Has 4 sub-tabs:
///   1. Por cotizar  - solicitudes nuevas + rechazadas (esperando cliente también)
///   2. Pendientes   - cotizadas+aceptadas, esperando asignar motorizado
///   3. En curso     - asignadas / en tránsito
///   4. Historial    - todo (entregadas, canceladas)
class AdminOrders extends StatefulWidget {
  const AdminOrders({super.key});

  @override
  State<AdminOrders> createState() => _AdminOrdersState();
}

class _AdminOrdersState extends State<AdminOrders>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final db = Database.instance;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    db.addListener(_onChange);
  }

  @override
  void dispose() {
    db.removeListener(_onChange);
    _tabs.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final toQuote = db.awaitingQuoteOrders().length;
    final pending = db.pendingOrders().length;
    final active = db.activeOrders().length;

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
            tabs: [
              _buildTab('Por cotizar', toQuote, Icons.request_quote_outlined),
              _buildTab('Pendientes', pending, Icons.schedule),
              _buildTab('En curso', active, Icons.local_shipping_outlined),
              _buildTab('Historial', 0, Icons.history),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: const [
              _ToQuoteTab(),
              _PendingTab(),
              _InProgressTab(),
              _AllOrdersTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTab(String label, int count, IconData icon) {
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 8),
          Text(label),
          if (count > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: DS.danger,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: DS.numeric(10,
                    color: Colors.white, weight: FontWeight.w700),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ======================================================================
//  TAB: POR COTIZAR
// ======================================================================
class _ToQuoteTab extends StatelessWidget {
  const _ToQuoteTab();

  @override
  Widget build(BuildContext context) {
    final db = Database.instance;
    final toQuote = db.awaitingQuoteOrders();
    final waitingClient = db.quotedOrders();

    Future<void> onRefresh() async {
      await db.refresh();
    }

    if (toQuote.isEmpty && waitingClient.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 200),
            EmptyState(
              icon: Icons.request_quote_outlined,
              message: 'No hay solicitudes por cotizar',
              hint:
                  'Las nuevas solicitudes de las empresas aparecerán aquí para que les asignes un monto.',
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(DS.space5),
      children: [
        if (toQuote.isNotEmpty) ...[
          Text('REQUIEREN COTIZACIÓN', style: DS.eyebrow()),
          const SizedBox(height: DS.space3),
          ...toQuote.map((o) => Padding(
                padding: const EdgeInsets.only(bottom: DS.space3),
                child: _QuoteRequestCard(order: o),
              )),
        ],
        if (waitingClient.isNotEmpty) ...[
          if (toQuote.isNotEmpty) const SizedBox(height: DS.space5),
          Text('ESPERANDO RESPUESTA DEL CLIENTE', style: DS.eyebrow()),
          const SizedBox(height: DS.space3),
          ...waitingClient.map((o) => Padding(
                padding: const EdgeInsets.only(bottom: DS.space3),
                child: _WaitingClientCard(order: o),
              )),
        ],
      ],
    ),
    );
  }
}

class _QuoteRequestCard extends StatelessWidget {
  final DeliveryOrder order;
  const _QuoteRequestCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final db = Database.instance;
    final company = db.companyById(order.companyId);
    final isRejected = order.status == OrderStatus.rejected;

    return Container(
      decoration: BoxDecoration(
        color: DS.surfaceRaised,
        borderRadius: BorderRadius.circular(DS.radiusLg),
        border: Border.all(
            color: isRejected ? DS.danger.withValues(alpha: 0.3) : DS.border,
            width: isRejected ? 1.5 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isRejected)
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: DS.space4, vertical: DS.space3),
              decoration: BoxDecoration(
                color: DS.dangerBg,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(DS.radiusLg)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.thumb_down_outlined,
                      size: 14, color: DS.danger),
                  const SizedBox(width: DS.space2),
                  Expanded(
                    child: Text(
                      'El cliente rechazó la cotización anterior. Envía otra con un monto distinto.',
                      style: DS.ui(12,
                          color: DS.danger, weight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(DS.space4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Solicitud #${order.number}',
                        style: DS.numeric(14, weight: FontWeight.w700)),
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
                    Expanded(
                      child: Text(formatDate(order.createdAt),
                          style: DS.ui(11, color: DS.inkMuted)),
                    ),
                  ],
                ),
                const SizedBox(height: DS.space3),
                InfoRow(
                    icon: Icons.apartment,
                    label: 'Empresa',
                    value: company?.name ?? '—'),
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
                      label: 'Paquete',
                      value: order.description),
                const SizedBox(height: DS.space4),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _quote(context),
                    icon: const Icon(Icons.attach_money, size: 16),
                    label: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(isRejected
                          ? 'Enviar nueva cotización'
                          : 'Enviar cotización'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _quote(BuildContext context) async {
    final amount = await showDialog<double>(
      context: context,
      builder: (ctx) => _QuoteAmountDialog(orderNumber: order.number),
    );
    if (amount == null || amount <= 0) return;

    try {
      await Database.instance.quoteOrder(order.id, amount);
      if (context.mounted) {
        showSuccessSnack(context,
            'Cotización enviada · ${formatMoney(amount)}. Esperando respuesta del cliente.');
      }
    } catch (e) {
      if (context.mounted) showErrorSnack(context, 'Error: $e');
    }
  }
}

class _QuoteAmountDialog extends StatefulWidget {
  final int orderNumber;
  const _QuoteAmountDialog({required this.orderNumber});

  @override
  State<_QuoteAmountDialog> createState() => _QuoteAmountDialogState();
}

class _QuoteAmountDialogState extends State<_QuoteAmountDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final db = Database.instance;
    final amt = double.tryParse(_controller.text) ?? 0;
    final commission = db.calcCommission(amt);
    final central = double.parse((amt - commission).toStringAsFixed(2));

    return AlertDialog(
      title: Text('Cotizar solicitud #${widget.orderNumber}',
          style: DS.display(20)),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Monto del delivery (${db.config.currency})',
                style: DS.ui(12, weight: FontWeight.w600)),
            const SizedBox(height: DS.space2),
            TextFormField(
              controller: _controller,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              decoration: InputDecoration(
                hintText: '0.00',
                prefixText: '${db.config.currencySymbol} ',
              ),
              validator: (v) {
                final n = double.tryParse(v ?? '');
                if (n == null || n <= 0) return 'Monto inválido';
                return null;
              },
              onChanged: (_) => setState(() {}),
            ),
            if (amt > 0) ...[
              const SizedBox(height: DS.space4),
              Container(
                padding: const EdgeInsets.all(DS.space3),
                decoration: BoxDecoration(
                  color: DS.surfaceMuted,
                  borderRadius: BorderRadius.circular(DS.radiusSm),
                ),
                child: Column(
                  children: [
                    _row('Total', formatMoney(amt), DS.ink, bold: true),
                    const SizedBox(height: 4),
                    _row('Motorizado', formatMoney(commission), DS.warning),
                    const SizedBox(height: 4),
                    _row('Central', formatMoney(central), DS.brandBlue),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context, double.parse(_controller.text));
            }
          },
          child: const Text('Enviar al cliente'),
        ),
      ],
    );
  }

  Widget _row(String label, String value, Color color, {bool bold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: DS.ui(12, color: DS.inkSecondary)),
        Text(value,
            style: DS.numeric(13,
                color: color,
                weight: bold ? FontWeight.w700 : FontWeight.w600)),
      ],
    );
  }
}

class _WaitingClientCard extends StatelessWidget {
  final DeliveryOrder order;
  const _WaitingClientCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final company = Database.instance.companyById(order.companyId);
    return Container(
      padding: const EdgeInsets.all(DS.space4),
      decoration: BoxDecoration(
        color: DS.surfaceRaised,
        borderRadius: BorderRadius.circular(DS.radiusLg),
        border: Border.all(color: DS.border, width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: DS.info.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(DS.radiusMd),
            ),
            child: const Icon(Icons.mark_email_read_outlined,
                color: DS.info, size: 18),
          ),
          const SizedBox(width: DS.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    'Solicitud #${order.number} · ${formatMoney(order.amount)}',
                    style: DS.ui(13, weight: FontWeight.w600)),
                Text('${company?.name ?? "—"} · esperando respuesta',
                    style: DS.ui(11, color: DS.inkMuted)),
              ],
            ),
          ),
          Text(formatDate(order.quotedAt ?? order.createdAt),
              style: DS.ui(11, color: DS.inkMuted)),
        ],
      ),
    );
  }
}

// ======================================================================
//  TAB: PENDIENTES (asignar motorizado)
// ======================================================================
class _PendingTab extends StatelessWidget {
  const _PendingTab();

  @override
  Widget build(BuildContext context) {
    final db = Database.instance;
    final pending = db.pendingOrders();

    if (pending.isEmpty) {
      return const EmptyState(
        icon: Icons.check_circle_outline,
        message: 'Todas las órdenes están asignadas',
        hint:
            'Las órdenes que el cliente acepte aparecerán aquí para que las asignes a un motorizado.',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(DS.space5),
      children: [
        Container(
          padding: const EdgeInsets.all(DS.space4),
          decoration: BoxDecoration(
            color: DS.warningBg,
            borderRadius: BorderRadius.circular(DS.radiusMd),
            border: Border.all(
                color: DS.warning.withValues(alpha: 0.2), width: 1),
          ),
          child: Row(
            children: [
              const Icon(Icons.schedule, color: DS.warning, size: 18),
              const SizedBox(width: DS.space3),
              Expanded(
                child: Text(
                  '${pending.length} ${pending.length == 1 ? "orden esperando" : "órdenes esperando"} asignación',
                  style: DS.ui(13, color: DS.warning, weight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: DS.space4),
        ...pending.map((o) => Padding(
              padding: const EdgeInsets.only(bottom: DS.space3),
              child: _OrderCard(
                order: o,
                actionLabel: 'Asignar motorizado',
                actionIcon: Icons.person_add_alt,
                onAction: () => _showAssignSheet(context, o),
              ),
            )),
      ],
    );
  }

  void _showAssignSheet(BuildContext context, DeliveryOrder order) {
    final db = Database.instance;
    final riders = db.riders;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: DS.surfaceRaised,
      barrierColor: DS.ink.withValues(alpha: 0.5),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(DS.radiusXl)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(DS.space5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: DS.space4),
                decoration: BoxDecoration(
                  color: DS.inkSubtle,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: DS.brandOrange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(DS.radiusMd),
                  ),
                  child: const Icon(Icons.person_add_alt,
                      color: DS.brandOrange, size: 18),
                ),
                const SizedBox(width: DS.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Asignar orden #${order.number}',
                          style: DS.display(20, weight: FontWeight.w500)),
                      Text(
                          '${formatMoney(order.amount)} · Comisión ${formatMoney(order.riderCommission)}',
                          style: DS.ui(12, color: DS.inkMuted)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  color: DS.inkMuted,
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: DS.space5),
            if (riders.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: DS.space5),
                child: Text(
                  'No hay motorizados registrados. Crea al menos uno desde la pestaña Motorizados.',
                  textAlign: TextAlign.center,
                  style: DS.ui(13, color: DS.inkMuted, height: 1.6),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 380),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: riders.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: DS.space2),
                  itemBuilder: (context, i) {
                    final r = riders[i];
                    final stats = db.riderStats(r.id);
                    final active = stats['active'] as int;
                    return Material(
                      color: DS.surfaceRaised,
                      borderRadius: BorderRadius.circular(DS.radiusMd),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(DS.radiusMd),
                        onTap: () {
                          db.assignOrder(order.id, r.id);
                          Navigator.pop(ctx);
                          showSuccessSnack(context,
                              'Orden #${order.number} asignada a ${r.name}');
                        },
                        child: Container(
                          padding: const EdgeInsets.all(DS.space3),
                          decoration: BoxDecoration(
                            border: Border.all(color: DS.border, width: 1),
                            borderRadius: BorderRadius.circular(DS.radiusMd),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: DS.brandOrange
                                      .withValues(alpha: 0.12),
                                  borderRadius:
                                      BorderRadius.circular(DS.radiusSm),
                                ),
                                child: Center(
                                  child: Text(
                                    r.name.isNotEmpty
                                        ? r.name[0].toUpperCase()
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
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(r.name,
                                        style: DS.ui(13,
                                            weight: FontWeight.w600)),
                                    Text('${r.vehicle.label} · ${r.plate}',
                                        style:
                                            DS.ui(11, color: DS.inkMuted)),
                                  ],
                                ),
                              ),
                              if (active > 0)
                                MetaChip(
                                  icon: Icons.directions_run,
                                  label: '$active activas',
                                  color: DS.accent,
                                )
                              else
                                MetaChip(
                                  icon: Icons.check,
                                  label: 'Disponible',
                                  color: DS.success,
                                ),
                              const SizedBox(width: 4),
                              const Icon(Icons.chevron_right,
                                  color: DS.inkMuted, size: 18),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ======================================================================
//  TAB: EN CURSO
// ======================================================================
class _InProgressTab extends StatelessWidget {
  const _InProgressTab();

  @override
  Widget build(BuildContext context) {
    final db = Database.instance;
    final active = db.activeOrders();

    if (active.isEmpty) {
      return const EmptyState(
        icon: Icons.local_shipping_outlined,
        message: 'No hay entregas en curso',
        hint:
            'Las órdenes asignadas o en camino aparecerán aquí mientras se completan.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(DS.space5),
      itemCount: active.length,
      separatorBuilder: (_, __) => const SizedBox(height: DS.space3),
      itemBuilder: (context, i) {
        return _OrderCard(order: active[i]);
      },
    );
  }
}

// ======================================================================
//  TAB: HISTORIAL
// ======================================================================
class _AllOrdersTab extends StatelessWidget {
  const _AllOrdersTab();

  @override
  Widget build(BuildContext context) {
    final db = Database.instance;
    final orders = db.orders.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (orders.isEmpty) {
      return const EmptyState(
        icon: Icons.history,
        message: 'Sin historial todavía',
        hint: 'Aquí verás todas las órdenes que han pasado por la central.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(DS.space5),
      itemCount: orders.length,
      separatorBuilder: (_, __) => const SizedBox(height: DS.space3),
      itemBuilder: (context, i) => _OrderCard(order: orders[i]),
    );
  }
}

// ======================================================================
//  ORDER CARD (shared)
// ======================================================================
class _OrderCard extends StatelessWidget {
  final DeliveryOrder order;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;
  const _OrderCard({
    required this.order,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final db = Database.instance;
    final company = db.companyById(order.companyId);
    final rider = db.riderById(order.riderId);

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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Orden #${order.number}',
                        style: DS.numeric(15, weight: FontWeight.w700)),
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
                    Expanded(
                      child: Text(formatDate(order.createdAt),
                          style: DS.ui(11, color: DS.inkMuted)),
                    ),
                    StatusChip(status: order.status, small: true),
                  ],
                ),
                const SizedBox(height: DS.space3),
                InfoRow(
                    icon: Icons.apartment,
                    label: 'Empresa',
                    value: company?.name ?? '—'),
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
                if (rider != null)
                  InfoRow(
                      icon: Icons.two_wheeler,
                      label: 'Motorizado',
                      value: '${rider.name} · ${rider.vehicle.label}'),
                if (order.paymentMethodName != null &&
                    order.paymentMethodName!.isNotEmpty)
                  InfoRow(
                      icon: Icons.payment,
                      label: 'Pago',
                      value: order.paymentMethodName!),
                const SizedBox(height: DS.space3),
                Row(
                  children: [
                    Expanded(
                      child: _MoneyChip(
                          label: 'Total',
                          value: formatMoney(order.amount),
                          color: DS.ink),
                    ),
                    const SizedBox(width: DS.space2),
                    Expanded(
                      child: _MoneyChip(
                          label: 'Comisión',
                          value: formatMoney(order.riderCommission),
                          color: DS.warning),
                    ),
                    const SizedBox(width: DS.space2),
                    Expanded(
                      child: _MoneyChip(
                          label: 'Central',
                          value: formatMoney(order.centralProfit),
                          color: DS.brandBlue),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (onAction != null) ...[
            const Divider(height: 1, color: DS.border),
            Padding(
              padding: const EdgeInsets.all(DS.space3),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onAction,
                  icon: Icon(actionIcon, size: 16),
                  label: Text(actionLabel!),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MoneyChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _MoneyChip(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: DS.space3, vertical: DS.space2),
      decoration: BoxDecoration(
        color: DS.surfaceMuted,
        borderRadius: BorderRadius.circular(DS.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: DS.eyebrow()),
          const SizedBox(height: 2),
          Text(value,
              style: DS.numeric(13, color: color, weight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}
