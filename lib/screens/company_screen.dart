import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import '../models/models.dart';
import '../services/database.dart';
import '../widgets/design_system.dart';
import '../widgets/components.dart';
import '../widgets/app_shell.dart';
import '../widgets/location_picker.dart';
import 'login_screen.dart';
import 'company_profile_screen.dart';
import 'customer_tracking_screen.dart';

class CompanyScreen extends StatefulWidget {
  const CompanyScreen({super.key});

  @override
  State<CompanyScreen> createState() => _CompanyScreenState();
}

class _CompanyScreenState extends State<CompanyScreen> {
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

  Future<void> _logout() async {
    await db.logout();
    if (!mounted) return;
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final user = db.currentUser!;
    final company = db.companyById(user.linkedEntityId);
    if (company == null) {
      return const Scaffold(body: Center(child: Text('Empresa no encontrada')));
    }

    final myOrders = db.ordersByCompany(company.id);
    final pendingQuotes =
        myOrders.where((o) => o.status == OrderStatus.quoted).length;
    final activeOrders = myOrders
        .where((o) =>
            o.status != OrderStatus.delivered &&
            o.status != OrderStatus.cancelled &&
            o.status != OrderStatus.rejected)
        .length;
    final myDebts = db.debtOrders(companyId: company.id).length;

    return AppShell(
      userName: company.name,
      userRoleLabel: 'Empresa',
      userSubtitle: 'Portal cliente',
      onLogout: _logout,
      roleColor: DS.brandBlue,
      items: [
        NavItem(
          label: 'Nueva orden',
          icon: Icons.add_circle_outline,
          body: NewOrderTab(company: company),
        ),
        NavItem(
          label: 'Cotizaciones',
          icon: Icons.request_quote_outlined,
          body: QuotesTab(companyId: company.id),
          badge: pendingQuotes > 0 ? pendingQuotes : null,
        ),
        NavItem(
          label: 'Mis órdenes',
          icon: Icons.receipt_long_outlined,
          body: MyOrdersTab(companyId: company.id),
          badge: activeOrders > 0 ? activeOrders : null,
        ),
        if (company.payLaterEnabled)
          NavItem(
            label: 'Cuentas pendientes',
            icon: Icons.account_balance_wallet_outlined,
            body: MyDebtsTab(companyId: company.id),
            badge: myDebts > 0 ? myDebts : null,
          ),
        NavItem(
          label: 'Mi perfil',
          icon: Icons.business_outlined,
          body: const CompanyProfileScreen(),
          // Badge naranja si no tiene ubicación configurada
          badge: company.hasLocation ? null : 1,
        ),
      ],
    );
  }
}

// ====================== NEW ORDER ======================
class NewOrderTab extends StatefulWidget {
  final Company company;
  const NewOrderTab({super.key, required this.company});

  @override
  State<NewOrderTab> createState() => _NewOrderTabState();
}

class _NewOrderTabState extends State<NewOrderTab> {
  final _formKey = GlobalKey<FormState>();
  final _customer = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _description = TextEditingController();
  bool _submitting = false;
  LatLng? _pickupLocation;  // punto de recogida (por defecto sede de la empresa)
  LatLng? _dropoffLocation; // destino seleccionado en el mapa

  @override
  void initState() {
    super.initState();
    // Si la empresa tiene sede configurada, usar como recogida por defecto
    final c = widget.company;
    if (c.hasLocation) {
      _pickupLocation = LatLng(c.latitude!, c.longitude!);
    }
  }

  @override
  void dispose() {
    _customer.dispose();
    _phone.dispose();
    _address.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickPickup() async {
    final result = await Navigator.push<LocationResult>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => LocationPickerScreen(
          title: 'Punto de recogida',
          subtitle: 'Indica dónde el motorizado recoge el pedido',
          initialPosition: _pickupLocation,
          markerColor: DS.brandBlue,
          markerIcon: Icons.store,
        ),
      ),
    );
    if (result == null) return;
    setState(() {
      _pickupLocation = LatLng(result.latitude, result.longitude);
    });
  }

  /// Restaura el pickup a la sede de la empresa (si la tiene)
  void _resetPickupToSede() {
    final c = widget.company;
    if (c.hasLocation) {
      setState(() {
        _pickupLocation = LatLng(c.latitude!, c.longitude!);
      });
    }
  }

  Future<void> _pickDropoff() async {
    final result = await Navigator.push<LocationResult>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => LocationPickerScreen(
          title: 'Punto de entrega',
          subtitle: 'Indica dónde debe entregar el motorizado',
          initialPosition: _dropoffLocation,
          markerColor: DS.success,
          markerIcon: Icons.flag,
        ),
      ),
    );
    if (result == null) return;
    setState(() {
      _dropoffLocation = LatLng(result.latitude, result.longitude);
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // Validar pickup
    if (_pickupLocation == null) {
      showErrorSnack(context,
          'Debes indicar el punto de recogida en el mapa');
      return;
    }

    // Validar dropoff
    if (_dropoffLocation == null) {
      final continuar = await showConfirmDialog(
        context,
        title: 'Sin destino en el mapa',
        message:
            'No has marcado el destino en el mapa. El motorizado no podrá '
            'ver la ubicación exacta de entrega.\n\n¿Crear la orden de todos modos?',
        confirmLabel: 'Crear sin mapa',
        cancelLabel: 'Volver',
      );
      if (!continuar) return;
    }

    setState(() => _submitting = true);
    try {
      // Crear orden con coordenadas (el backend hace autocotización si está activada)
      final order = await Database.instance.createOrder(
        companyId: widget.company.id,
        customer: _customer.text.trim(),
        customerPhone: _phone.text.trim(),
        address: _address.text.trim(),
        description: _description.text.trim(),
        pickupLat: _pickupLocation?.latitude,
        pickupLng: _pickupLocation?.longitude,
        dropoffLat: _dropoffLocation?.latitude,
        dropoffLng: _dropoffLocation?.longitude,
      );

      if (!mounted) return;

      final autoQuoted = order.amount > 0;

      if (autoQuoted) {
        // Mostrar diálogo grande con la cotización
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.auto_awesome, color: DS.success, size: 20),
                const SizedBox(width: 8),
                const Text('¡Tu pedido fue cotizado!'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Solicitud #${order.number}',
                    style: DS.ui(12, color: DS.inkMuted)),
                const SizedBox(height: DS.space3),
                Text('Precio del envío',
                    style: DS.ui(13, color: DS.inkSecondary)),
                const SizedBox(height: 4),
                Text(
                  '${Database.instance.config.currencySymbol}${order.amount.toStringAsFixed(2)}',
                  style: DS.display(34,
                      color: DS.brandOrange, weight: FontWeight.w700),
                ),
                const SizedBox(height: DS.space3),
                Container(
                  padding: const EdgeInsets.all(DS.space3),
                  decoration: BoxDecoration(
                    color: DS.brandBlue.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(DS.radiusMd),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline,
                          color: DS.brandBlue, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Ve a "Cotizaciones" para elegir tu método de pago y confirmar el pedido.',
                          style: DS.ui(12,
                              color: DS.inkSecondary, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Entendido'),
              ),
            ],
          ),
        );
      } else {
        showSuccessSnack(context,
            'Solicitud #${order.number} enviada · La central te cotizará pronto');
      }

      _customer.clear();
      _phone.clear();
      _address.clear();
      _description.clear();
      setState(() {
        _dropoffLocation = null;
        // Resetear pickup a la sede de la empresa (si existe)
        final c = widget.company;
        _pickupLocation = c.hasLocation
            ? LatLng(c.latitude!, c.longitude!)
            : null;
      });
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, 'No se pudo crear: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(DS.space6),
        children: [
          Container(
            padding: const EdgeInsets.all(DS.space4),
            decoration: BoxDecoration(
              color: DS.infoBg,
              borderRadius: BorderRadius.circular(DS.radiusMd),
              border:
                  Border.all(color: DS.info.withValues(alpha: 0.2), width: 1),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: DS.info, size: 18),
                const SizedBox(width: DS.space3),
                Expanded(
                  child: Text(
                    'Tu solicitud será enviada a la central. Recibirás una cotización antes de confirmar.',
                    style: DS.ui(13, color: DS.info, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: DS.space5),
          // Aviso si la empresa no tiene ubicación de sede configurada
          if (!widget.company.hasLocation) ...[
            Container(
              padding: const EdgeInsets.all(DS.space4),
              decoration: BoxDecoration(
                color: DS.warning.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(DS.radiusMd),
                border: Border.all(
                    color: DS.warning.withValues(alpha: 0.3), width: 1),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: DS.warning, size: 18),
                  const SizedBox(width: DS.space3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Configura la ubicación de tu sede',
                          style: DS.ui(12,
                              color: DS.warning, weight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Sin la ubicación de tu local, el motorizado no sabrá dónde recoger los pedidos. Ve a "Mi perfil" para configurarla.',
                          style: DS.ui(11,
                              color: DS.inkSecondary, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: DS.space5),
          ],
          _buildFormSection(),
          const SizedBox(height: DS.space5),
          ElevatedButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.send_outlined, size: 16),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(_submitting
                  ? 'Enviando...'
                  : 'Solicitar cotización a la central'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormSection() {
    return Container(
      padding: const EdgeInsets.all(DS.space6),
      decoration: BoxDecoration(
        color: DS.surfaceRaised,
        borderRadius: BorderRadius.circular(DS.radiusLg),
        border: Border.all(color: DS.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('DATOS DEL DESTINATARIO', style: DS.eyebrow()),
          const SizedBox(height: DS.space2),
          Text('Solicitar delivery',
              style: DS.display(22, weight: FontWeight.w500)),
          const SizedBox(height: DS.space2),
          Text(
            'Completa la información del cliente que recibirá el paquete. La central evaluará y te enviará el costo del delivery.',
            style: DS.ui(13, color: DS.inkSecondary, height: 1.5),
          ),
          const SizedBox(height: DS.space5),
          _label('Cliente destinatario'),
          TextFormField(
            controller: _customer,
            decoration: const InputDecoration(
              hintText: 'Nombre completo',
              prefixIcon: Icon(Icons.person_outline, size: 18),
            ),
            validator: (v) => v?.trim().isEmpty == true ? 'Requerido' : null,
          ),
          const SizedBox(height: DS.space3),
          _label('Teléfono del cliente'),
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              hintText: '+58 412-1234567',
              prefixIcon: Icon(Icons.phone_outlined, size: 18),
            ),
            validator: (v) {
              final s = (v ?? '').trim();
              if (s.isEmpty) return 'Requerido';
              // Solo permite digitos, espacios, +, - y parentesis
              final cleaned = s.replaceAll(RegExp(r'[\s\-\(\)]'), '');
              if (!RegExp(r'^\+?\d{7,15}$').hasMatch(cleaned)) {
                return 'Número de teléfono inválido';
              }
              return null;
            },
          ),
          const SizedBox(height: DS.space3),
          _label('Dirección de entrega'),
          TextFormField(
            controller: _address,
            maxLines: 2,
            decoration: const InputDecoration(
              hintText: 'Calle, número, referencia',
              prefixIcon: Padding(
                padding: EdgeInsets.only(bottom: 24),
                child: Icon(Icons.location_on_outlined, size: 18),
              ),
            ),
            validator: (v) {
              final s = (v ?? '').trim();
              if (s.isEmpty) return 'Requerido';
              if (s.length < 5) return 'Dirección muy corta';
              return null;
            },
          ),
          const SizedBox(height: DS.space3),

          // Selector de RECOGIDA
          _PickupPickerCard(
            location: _pickupLocation,
            isFromSede: widget.company.hasLocation &&
                _pickupLocation != null &&
                _pickupLocation!.latitude == widget.company.latitude &&
                _pickupLocation!.longitude == widget.company.longitude,
            companyHasSede: widget.company.hasLocation,
            onPick: _pickPickup,
            onResetToSede: _resetPickupToSede,
          ),
          const SizedBox(height: DS.space3),

          // Botón de selector en mapa (DESTINO)
          _DropoffPickerCard(
            location: _dropoffLocation,
            onPick: _pickDropoff,
            onClear: () => setState(() => _dropoffLocation = null),
          ),
          const SizedBox(height: DS.space5),
          const SectionDivider(label: 'Detalles'),
          _label('Descripción del paquete'),
          TextFormField(
            controller: _description,
            maxLines: 2,
            decoration: const InputDecoration(
              hintText: 'Qué se va a entregar (opcional)',
              prefixIcon: Padding(
                padding: EdgeInsets.only(bottom: 24),
                child: Icon(Icons.inventory_2_outlined, size: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: DS.space2),
        child: Text(text, style: DS.ui(12, weight: FontWeight.w600)),
      );
}

/// Card que muestra el botón para elegir el destino en el mapa,
/// o el destino ya seleccionado con opción de cambiar/borrar.
class _DropoffPickerCard extends StatelessWidget {
  final LatLng? location;
  final VoidCallback onPick;
  final VoidCallback onClear;

  const _DropoffPickerCard({
    required this.location,
    required this.onPick,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    if (location == null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPick,
          borderRadius: BorderRadius.circular(DS.radiusMd),
          child: Container(
            padding: const EdgeInsets.all(DS.space3),
            decoration: BoxDecoration(
              color: DS.surfaceMuted,
              borderRadius: BorderRadius.circular(DS.radiusMd),
              border: Border.all(
                color: DS.brandBlue.withValues(alpha: 0.3),
                width: 1,
                style: BorderStyle.solid,
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
                  child: const Icon(Icons.add_location_alt,
                      color: DS.brandBlue, size: 18),
                ),
                const SizedBox(width: DS.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('INDICAR DESTINO EN EL MAPA',
                          style: DS.eyebrow(color: DS.brandBlue)),
                      const SizedBox(height: 2),
                      Text('Opcional · Ayuda al motorizado a encontrar el punto',
                          style: DS.ui(11,
                              color: DS.inkMuted, height: 1.4)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: DS.inkMuted, size: 20),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(DS.space3),
      decoration: BoxDecoration(
        color: DS.success.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(DS.radiusMd),
        border: Border.all(
            color: DS.success.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: DS.success.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(DS.radiusSm),
            ),
            child: const Icon(Icons.flag, color: DS.success, size: 18),
          ),
          const SizedBox(width: DS.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('DESTINO MARCADO EN EL MAPA',
                    style: DS.eyebrow(color: DS.success)),
                const SizedBox(height: 2),
                Text(
                  '${location!.latitude.toStringAsFixed(5)}, ${location!.longitude.toStringAsFixed(5)}',
                  style: DS.numeric(11,
                      color: DS.inkSecondary,
                      weight: FontWeight.w600),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit, color: DS.brandBlue, size: 16),
            onPressed: onPick,
            tooltip: 'Cambiar punto',
          ),
          IconButton(
            icon: const Icon(Icons.close, color: DS.inkMuted, size: 16),
            onPressed: onClear,
            tooltip: 'Quitar punto',
          ),
        ],
      ),
    );
  }
}

/// Card que muestra el botón para elegir el punto de recogida en el mapa.
/// Si la empresa tiene sede configurada, muestra que está usando la sede
/// y ofrece cambiarla. Si no, exige al usuario marcar un punto.
class _PickupPickerCard extends StatelessWidget {
  final LatLng? location;
  final bool isFromSede;
  final bool companyHasSede;
  final VoidCallback onPick;
  final VoidCallback onResetToSede;

  const _PickupPickerCard({
    required this.location,
    required this.isFromSede,
    required this.companyHasSede,
    required this.onPick,
    required this.onResetToSede,
  });

  @override
  Widget build(BuildContext context) {
    // Sin ubicación de recogida - obligatorio elegir
    if (location == null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPick,
          borderRadius: BorderRadius.circular(DS.radiusMd),
          child: Container(
            padding: const EdgeInsets.all(DS.space3),
            decoration: BoxDecoration(
              color: DS.warning.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(DS.radiusMd),
              border: Border.all(
                color: DS.warning.withValues(alpha: 0.4),
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: DS.warning.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(DS.radiusSm),
                  ),
                  child: const Icon(Icons.store,
                      color: DS.warning, size: 18),
                ),
                const SizedBox(width: DS.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('INDICAR PUNTO DE RECOGIDA',
                          style: DS.eyebrow(color: DS.warning)),
                      const SizedBox(height: 2),
                      Text(
                          'Obligatorio · Indica dónde el motorizado recoge el pedido',
                          style:
                              DS.ui(11, color: DS.inkMuted, height: 1.4)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: DS.inkMuted, size: 20),
              ],
            ),
          ),
        ),
      );
    }

    // Pickup definido
    return Container(
      padding: const EdgeInsets.all(DS.space3),
      decoration: BoxDecoration(
        color: DS.brandBlue.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(DS.radiusMd),
        border: Border.all(
            color: DS.brandBlue.withValues(alpha: 0.3), width: 1),
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
            child: const Icon(Icons.store, color: DS.brandBlue, size: 18),
          ),
          const SizedBox(width: DS.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isFromSede ? 'RECOGER EN TU SEDE' : 'PUNTO DE RECOGIDA',
                  style: DS.eyebrow(color: DS.brandBlue),
                ),
                const SizedBox(height: 2),
                Text(
                  '${location!.latitude.toStringAsFixed(5)}, ${location!.longitude.toStringAsFixed(5)}',
                  style: DS.numeric(11, color: DS.inkSecondary),
                ),
                if (!isFromSede && companyHasSede) ...[
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: onResetToSede,
                    child: Text(
                      'Volver a usar mi sede',
                      style: DS.ui(10,
                          color: DS.brandBlue, weight: FontWeight.w600),
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: onPick,
            icon: const Icon(Icons.edit, size: 16),
            color: DS.brandBlue,
            tooltip: 'Cambiar',
          ),
        ],
      ),
    );
  }
}

// ====================== QUOTES TAB ======================
class QuotesTab extends StatelessWidget {
  final String companyId;
  const QuotesTab({super.key, required this.companyId});

  @override
  Widget build(BuildContext context) {
    final db = Database.instance;
    final mine = db.ordersByCompany(companyId);
    final quoted = mine.where((o) => o.status == OrderStatus.quoted).toList();
    final waiting =
        mine.where((o) => o.status == OrderStatus.awaitingQuote).toList();

    if (quoted.isEmpty && waiting.isEmpty) {
      return const EmptyState(
        icon: Icons.request_quote_outlined,
        message: 'No tienes cotizaciones pendientes',
        hint:
            'Cuando crees una solicitud, la central te enviará una cotización aquí.',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(DS.space6),
      children: [
        if (quoted.isNotEmpty) ...[
          Text('REQUIEREN TU RESPUESTA', style: DS.eyebrow()),
          const SizedBox(height: DS.space3),
          ...quoted.map((o) => Padding(
                padding: const EdgeInsets.only(bottom: DS.space3),
                child: _QuoteCard(order: o),
              )),
        ],
        if (waiting.isNotEmpty) ...[
          if (quoted.isNotEmpty) const SizedBox(height: DS.space5),
          Text('ESPERANDO COTIZACIÓN DE LA CENTRAL', style: DS.eyebrow()),
          const SizedBox(height: DS.space3),
          ...waiting.map((o) => Padding(
                padding: const EdgeInsets.only(bottom: DS.space3),
                child: _WaitingCard(order: o),
              )),
        ],
      ],
    );
  }
}

class _WaitingCard extends StatelessWidget {
  final DeliveryOrder order;
  const _WaitingCard({required this.order});

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
              Text('Solicitud #${order.number}',
                  style: DS.numeric(14, weight: FontWeight.w700)),
              const Spacer(),
              StatusChip(status: order.status, small: true),
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
                label: 'Paquete',
                value: order.description),
          const SizedBox(height: DS.space2),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(DS.space3),
            decoration: BoxDecoration(
              color: DS.surfaceMuted,
              borderRadius: BorderRadius.circular(DS.radiusSm),
            ),
            child: Row(
              children: [
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: DS.inkMuted),
                ),
                const SizedBox(width: DS.space3),
                Expanded(
                  child: Text(
                    'Esperando que la central asigne un monto para esta entrega...',
                    style: DS.ui(12, color: DS.inkMuted),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuoteCard extends StatelessWidget {
  final DeliveryOrder order;
  const _QuoteCard({required this.order});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: DS.surfaceRaised,
        borderRadius: BorderRadius.circular(DS.radiusLg),
        border: Border.all(color: DS.info.withValues(alpha: 0.3), width: 1.5),
        boxShadow: DS.shadowMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(DS.space5),
            decoration: const BoxDecoration(
              color: DS.dark,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(DS.radiusLg)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('COTIZACIÓN PARA SOLICITUD #${order.number}',
                    style: DS.eyebrow(
                        color: Colors.white.withValues(alpha: 0.6))),
                const SizedBox(height: DS.space3),
                Text(formatMoney(order.amount),
                    style: DS.numeric(36,
                        color: Colors.white, weight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('Costo del delivery propuesto por la central',
                    style: DS.ui(12,
                        color: Colors.white.withValues(alpha: 0.6))),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(DS.space4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _reject(context),
                        icon: const Icon(Icons.close, size: 14),
                        label: const Text('Rechazar'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: DS.danger,
                          side: BorderSide(
                              color: DS.danger.withValues(alpha: 0.3),
                              width: 1),
                        ),
                      ),
                    ),
                    const SizedBox(width: DS.space2),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: () => _accept(context),
                        icon: const Icon(Icons.check_circle_outline, size: 16),
                        label: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 4),
                          child: Text('Aceptar y elegir pago'),
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

  Future<void> _reject(BuildContext context) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Rechazar cotización',
      message:
          'La orden volverá a la central para que reconsidere el monto. ¿Confirmas?',
      confirmLabel: 'Sí, rechazar',
      destructive: true,
    );
    if (!ok) return;
    try {
      await Database.instance.rejectQuote(order.id);
      if (context.mounted) {
        showSuccessSnack(context, 'Cotización rechazada');
      }
    } catch (e) {
      if (context.mounted) showErrorSnack(context, 'Error: $e');
    }
  }

  Future<void> _accept(BuildContext context) async {
    final db = Database.instance;
    final company = db.companyById(order.companyId);

    if (db.paymentMethods.isEmpty && !(company?.payLaterEnabled ?? false)) {
      showErrorSnack(context,
          'No hay métodos de pago configurados. Pide al admin que agregue al menos uno.');
      return;
    }

    final currentDebt = db
        .debtOrders(companyId: order.companyId)
        .fold<double>(0, (s, o) => s + o.amount);

    final result = await Navigator.push<_PaymentChoice>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _PaymentSelectionScreen(
          order: order,
          methods: db.paymentMethods,
          payLaterEnabled: company?.payLaterEnabled ?? false,
          creditLimit: company?.creditLimit ?? 0,
          currentDebt: currentDebt,
        ),
      ),
    );

    if (result == null) return;

    try {
      if (result.payLater) {
        await db.acceptQuotePayLater(order.id);
        if (context.mounted) {
          showSuccessSnack(context,
              '¡Aceptado a crédito! La orden quedó en cuentas pendientes. La central asignará un motorizado.');
        }
      } else {
        await db.acceptQuote(order.id, result.method!.id);
        if (context.mounted) {
          showSuccessSnack(context,
              '¡Aceptado! Pago: ${result.method!.name}. La central asignará un motorizado pronto.');
        }
      }
    } catch (e) {
      if (context.mounted) showErrorSnack(context, 'Error: $e');
    }
  }
}

// ====================== SELECTOR DE PAGO ======================
class _PaymentChoice {
  final PaymentMethod? method;
  final bool payLater;
  _PaymentChoice.method(this.method) : payLater = false;
  _PaymentChoice.payLater()
      : method = null,
        payLater = true;
}

class _PaymentSelectionScreen extends StatefulWidget {
  final DeliveryOrder order;
  final List<PaymentMethod> methods;
  final bool payLaterEnabled;
  final double creditLimit;
  final double currentDebt;

  const _PaymentSelectionScreen({
    required this.order,
    required this.methods,
    required this.payLaterEnabled,
    required this.creditLimit,
    required this.currentDebt,
  });

  @override
  State<_PaymentSelectionScreen> createState() =>
      _PaymentSelectionScreenState();
}

class _PaymentSelectionScreenState extends State<_PaymentSelectionScreen> {
  PaymentMethod? _selected;
  bool _payLaterSelected = false;

  bool get _wouldExceedLimit {
    if (widget.creditLimit <= 0) return false;
    return (widget.currentDebt + widget.order.amount) > widget.creditLimit;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DS.surface,
      appBar: AppBar(
        title: Text('Elegir forma de pago',
            style: DS.display(18, weight: FontWeight.w600)),
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
                // Resumen del monto
                Container(
                  padding: const EdgeInsets.all(DS.space4),
                  decoration: BoxDecoration(
                    color: DS.dark,
                    borderRadius: BorderRadius.circular(DS.radiusLg),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('A PAGAR',
                                style: DS.eyebrow(
                                    color:
                                        Colors.white.withValues(alpha: 0.6))),
                            const SizedBox(height: 4),
                            Text(formatMoney(widget.order.amount),
                                style: DS.numeric(28,
                                    color: Colors.white,
                                    weight: FontWeight.w700)),
                          ],
                        ),
                      ),
                      Text('Orden #${widget.order.number}',
                          style: DS.ui(11,
                              color: Colors.white.withValues(alpha: 0.5))),
                    ],
                  ),
                ),

                const SizedBox(height: DS.space5),

                if (widget.methods.isNotEmpty) ...[
                  Text('PAGAR AHORA', style: DS.eyebrow()),
                  const SizedBox(height: DS.space2),
                  Text('Elige cómo vas a pagar este delivery',
                      style: DS.ui(12, color: DS.inkMuted)),
                  const SizedBox(height: DS.space3),
                  ...widget.methods.map((m) {
                    final isSelected =
                        !_payLaterSelected && _selected?.id == m.id;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: DS.space2),
                      child: _MethodOption(
                        method: m,
                        selected: isSelected,
                        onTap: () => setState(() {
                          _selected = m;
                          _payLaterSelected = false;
                        }),
                      ),
                    );
                  }),
                ],

                if (widget.payLaterEnabled) ...[
                  const SizedBox(height: DS.space5),
                  Text('PAGAR DESPUÉS', style: DS.eyebrow()),
                  const SizedBox(height: DS.space2),
                  Text('Acumular esta orden en tu cuenta',
                      style: DS.ui(12, color: DS.inkMuted)),
                  const SizedBox(height: DS.space3),
                  _PayLaterOption(
                    selected: _payLaterSelected,
                    creditLimit: widget.creditLimit,
                    currentDebt: widget.currentDebt,
                    orderAmount: widget.order.amount,
                    wouldExceed: _wouldExceedLimit,
                    onTap: _wouldExceedLimit
                        ? null
                        : () => setState(() {
                              _payLaterSelected = true;
                              _selected = null;
                            }),
                  ),
                ],

                if (_selected != null) ...[
                  const SizedBox(height: DS.space5),
                  _PaymentDataView(method: _selected!),
                ],
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
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
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
                      onPressed: _canConfirm() ? _confirm : null,
                      icon: const Icon(Icons.check, size: 16),
                      label: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(_payLaterSelected
                            ? 'Aceptar a crédito'
                            : 'Confirmar y aceptar'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _canConfirm() {
    if (_payLaterSelected) return !_wouldExceedLimit;
    return _selected != null;
  }

  void _confirm() {
    if (_payLaterSelected) {
      Navigator.pop(context, _PaymentChoice.payLater());
    } else if (_selected != null) {
      Navigator.pop(context, _PaymentChoice.method(_selected));
    }
  }
}

class _MethodOption extends StatelessWidget {
  final PaymentMethod method;
  final bool selected;
  final VoidCallback onTap;
  const _MethodOption({
    required this.method,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color:
          selected ? DS.brandBlue.withValues(alpha: 0.08) : DS.surfaceRaised,
      borderRadius: BorderRadius.circular(DS.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DS.radiusMd),
        child: Container(
          padding: const EdgeInsets.all(DS.space4),
          decoration: BoxDecoration(
            border: Border.all(
                color: selected ? DS.brandBlue : DS.border,
                width: selected ? 1.5 : 1),
            borderRadius: BorderRadius.circular(DS.radiusMd),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: DS.brandBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(DS.radiusSm),
                ),
                child: Icon(PaymentMethod.iconFor(method.icon),
                    color: DS.brandBlue, size: 18),
              ),
              const SizedBox(width: DS.space3),
              Expanded(
                child: Text(method.name,
                    style: DS.ui(14, weight: FontWeight.w600)),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected ? DS.brandBlue : DS.inkMuted,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PayLaterOption extends StatelessWidget {
  final bool selected;
  final double creditLimit;
  final double currentDebt;
  final double orderAmount;
  final bool wouldExceed;
  final VoidCallback? onTap;

  const _PayLaterOption({
    required this.selected,
    required this.creditLimit,
    required this.currentDebt,
    required this.orderAmount,
    required this.wouldExceed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    final color =
        wouldExceed ? DS.danger : (selected ? DS.warning : DS.inkSecondary);

    return Material(
      color: selected ? DS.warning.withValues(alpha: 0.08) : DS.surfaceRaised,
      borderRadius: BorderRadius.circular(DS.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DS.radiusMd),
        child: Container(
          padding: const EdgeInsets.all(DS.space4),
          decoration: BoxDecoration(
            border: Border.all(
                color: wouldExceed
                    ? DS.danger
                    : (selected ? DS.warning : DS.border),
                width: selected || wouldExceed ? 1.5 : 1),
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
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(DS.radiusSm),
                    ),
                    child: Icon(Icons.schedule, color: color, size: 18),
                  ),
                  const SizedBox(width: DS.space3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Pagar después',
                            style: DS.ui(14,
                                weight: FontWeight.w600,
                                color: disabled ? DS.inkMuted : DS.ink)),
                        Text('Esta orden quedará en cuentas pendientes',
                            style: DS.ui(11, color: DS.inkMuted)),
                      ],
                    ),
                  ),
                  if (!disabled)
                    Icon(
                      selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: selected ? DS.warning : DS.inkMuted,
                      size: 20,
                    ),
                ],
              ),
              if (creditLimit > 0) ...[
                const SizedBox(height: DS.space3),
                const Divider(height: 1, color: DS.border),
                const SizedBox(height: DS.space3),
                _LimitRow(
                    label: 'Deuda actual',
                    value: formatMoney(currentDebt)),
                const SizedBox(height: 4),
                _LimitRow(
                    label: 'Esta orden',
                    value: '+ ${formatMoney(orderAmount)}'),
                const SizedBox(height: 4),
                _LimitRow(
                  label: 'Total después',
                  value: formatMoney(currentDebt + orderAmount),
                  bold: true,
                  color: wouldExceed ? DS.danger : DS.warning,
                ),
                const SizedBox(height: 4),
                _LimitRow(
                    label: 'Tu límite',
                    value: formatMoney(creditLimit),
                    color: DS.inkMuted),
                if (wouldExceed) ...[
                  const SizedBox(height: DS.space3),
                  Container(
                    padding: const EdgeInsets.all(DS.space3),
                    decoration: BoxDecoration(
                      color: DS.dangerBg,
                      borderRadius: BorderRadius.circular(DS.radiusSm),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            color: DS.danger, size: 14),
                        const SizedBox(width: DS.space2),
                        Expanded(
                          child: Text(
                            'Excede tu límite de crédito. Paga deudas anteriores o elige otro método.',
                            style: DS.ui(11,
                                color: DS.danger,
                                weight: FontWeight.w600,
                                height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LimitRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final Color? color;
  const _LimitRow({
    required this.label,
    required this.value,
    this.bold = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: DS.ui(11, color: DS.inkSecondary)),
        Text(value,
            style: DS.numeric(12,
                color: color ?? DS.ink,
                weight: bold ? FontWeight.w700 : FontWeight.w600)),
      ],
    );
  }
}

class _PaymentDataView extends StatelessWidget {
  final PaymentMethod method;
  const _PaymentDataView({required this.method});

  @override
  Widget build(BuildContext context) {
    if (method.fields.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(DS.space4),
        decoration: BoxDecoration(
          color: DS.surfaceMuted,
          borderRadius: BorderRadius.circular(DS.radiusMd),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: DS.inkMuted, size: 18),
            const SizedBox(width: DS.space3),
            Expanded(
              child: Text(
                'Este método no tiene datos asociados. Coordina el pago directamente.',
                style: DS.ui(12, color: DS.inkSecondary, height: 1.5),
              ),
            ),
          ],
        ),
      );
    }

    final hasData = method.values.values.any((v) => v.trim().isNotEmpty);
    if (!hasData) {
      return Container(
        padding: const EdgeInsets.all(DS.space4),
        decoration: BoxDecoration(
          color: DS.warningBg,
          borderRadius: BorderRadius.circular(DS.radiusMd),
          border:
              Border.all(color: DS.warning.withValues(alpha: 0.2), width: 1),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: DS.warning, size: 18),
            const SizedBox(width: DS.space3),
            Expanded(
              child: Text(
                'El admin aún no ha cargado los datos para este método. Contacta a la central.',
                style: DS.ui(12, color: DS.warning, height: 1.5),
              ),
            ),
          ],
        ),
      );
    }

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
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: DS.brandBlue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(DS.radiusSm),
                  ),
                  child: Icon(PaymentMethod.iconFor(method.icon),
                      color: DS.brandBlue, size: 18),
                ),
                const SizedBox(width: DS.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('DATOS PARA EL PAGO', style: DS.eyebrow()),
                      Text(method.name,
                          style: DS.ui(14, weight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: DS.border),
          for (final field in method.fields)
            if ((method.values[field.fieldKey] ?? '').trim().isNotEmpty)
              _DataRow(
                label: field.label,
                value: method.values[field.fieldKey]!,
              ),
        ],
      ),
    );
  }
}

class _DataRow extends StatelessWidget {
  final String label;
  final String value;
  const _DataRow({required this.label, required this.value});

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
                Text(label.toUpperCase(), style: DS.eyebrow()),
                const SizedBox(height: 2),
                Text(value,
                    style: DS.ui(14, weight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 16),
            color: DS.inkMuted,
            tooltip: 'Copiar',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              showSuccessSnack(context, 'Copiado: $value');
            },
          ),
        ],
      ),
    );
  }
}

// ====================== MY ORDERS ======================
class MyOrdersTab extends StatelessWidget {
  final String companyId;
  const MyOrdersTab({super.key, required this.companyId});

  @override
  Widget build(BuildContext context) {
    final db = Database.instance;
    final orders = db.ordersByCompany(companyId);

    if (orders.isEmpty) {
      return const EmptyState(
        icon: Icons.receipt_long_outlined,
        message: 'Aún no has enviado ninguna orden',
        hint:
            'Cuando crees una solicitud aparecerá aquí con su estado en tiempo real.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(DS.space6),
      itemCount: orders.length,
      separatorBuilder: (_, __) => const SizedBox(height: DS.space3),
      itemBuilder: (context, i) {
        final o = orders[i];
        final rider = db.riderById(o.riderId);
        final canCancel = o.status == OrderStatus.awaitingQuote ||
            o.status == OrderStatus.quoted ||
            o.status == OrderStatus.pending ||
            o.status == OrderStatus.assigned;

        return Container(
          padding: const EdgeInsets.all(DS.space4),
          decoration: BoxDecoration(
            color: DS.surfaceRaised,
            borderRadius: BorderRadius.circular(DS.radiusLg),
            border: Border.all(
              color: o.isDebt ? DS.warning.withValues(alpha: 0.3) : DS.border,
              width: o.isDebt ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Orden #${o.number}',
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
                  Text(formatDate(o.createdAt),
                      style: DS.ui(11, color: DS.inkMuted)),
                  const Spacer(),
                  if (o.isDebt)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: DS.warning.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(DS.radiusSm),
                      ),
                      child: Text('PAGAR DESPUÉS',
                          style: DS.ui(9,
                              color: DS.warning, weight: FontWeight.w700)),
                    )
                  else
                    StatusChip(status: o.status, small: true),
                ],
              ),
              const SizedBox(height: DS.space3),
              InfoRow(
                  icon: Icons.person_outline,
                  label: 'Cliente',
                  value: '${o.customer} · ${o.customerPhone}'),
              InfoRow(
                  icon: Icons.location_on_outlined,
                  label: 'Dirección',
                  value: o.address),
              if (rider != null)
                InfoRow(
                    icon: Icons.two_wheeler,
                    label: 'Asignado a',
                    value: rider.name),
              if (o.payLater)
                InfoRow(
                    icon: Icons.schedule,
                    label: 'Pago',
                    value: o.paidAt != null
                        ? 'Pagado el ${formatDate(o.paidAt!)}'
                        : 'Pendiente (a crédito)')
              else if (o.paymentMethodName != null &&
                  o.paymentMethodName!.isNotEmpty)
                InfoRow(
                    icon: Icons.payment,
                    label: 'Pago',
                    value: o.paymentMethodName!),
              const SizedBox(height: DS.space3),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: DS.space3, vertical: DS.space2),
                    decoration: BoxDecoration(
                      color: DS.surfaceMuted,
                      borderRadius: BorderRadius.circular(DS.radiusSm),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Total: ',
                            style: DS.ui(12, color: DS.inkSecondary)),
                        Text(
                            o.amount > 0
                                ? formatMoney(o.amount)
                                : 'Por cotizar',
                            style: DS.numeric(14,
                                weight: FontWeight.w700,
                                color: o.amount > 0 ? DS.ink : DS.inkMuted)),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // Botón "Seguir mi pedido" cuando hay motorizado asignado
                  if (o.status == OrderStatus.assigned ||
                      o.status == OrderStatus.inTransit)
                    Padding(
                      padding: const EdgeInsets.only(right: DS.space2),
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  CustomerTrackingScreen(order: o),
                            ),
                          );
                        },
                        icon: const Icon(Icons.location_on, size: 14),
                        label: const Text('Seguir mi pedido'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: DS.brandOrange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                        ),
                      ),
                    ),
                  if (canCancel)
                    OutlinedButton.icon(
                      onPressed: () => _cancel(context, o),
                      icon: const Icon(Icons.close, size: 14),
                      label: const Text('Cancelar'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: DS.danger,
                        side: BorderSide(
                            color: DS.danger.withValues(alpha: 0.3),
                            width: 1),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _cancel(BuildContext context, DeliveryOrder o) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Cancelar orden',
      message:
          '¿Cancelar la orden #${o.number}? Esta acción no se puede deshacer.',
      confirmLabel: 'Sí, cancelar',
      destructive: true,
    );
    if (!ok) return;
    try {
      await Database.instance.cancelOrderByCompany(o.id);
      if (context.mounted) {
        showSuccessSnack(context, 'Orden #${o.number} cancelada');
      }
    } catch (e) {
      if (context.mounted) showErrorSnack(context, 'Error: $e');
    }
  }
}

// ====================== MY DEBTS TAB ======================
class MyDebtsTab extends StatelessWidget {
  final String companyId;
  const MyDebtsTab({super.key, required this.companyId});

  @override
  Widget build(BuildContext context) {
    final db = Database.instance;
    final company = db.companyById(companyId);
    final debts = db.debtOrders(companyId: companyId);
    final creditLimit = company?.creditLimit ?? 0;
    final total = debts.fold<double>(0, (s, o) => s + o.amount);

    if (debts.isEmpty) {
      return const EmptyState(
        icon: Icons.check_circle_outline,
        message: 'No tienes deudas pendientes',
        hint:
            'Cuando elijas "pagar después" al aceptar una cotización, las órdenes aparecerán aquí.',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(DS.space5),
      children: [
        Container(
          padding: const EdgeInsets.all(DS.space5),
          decoration: BoxDecoration(
            color: DS.dark,
            borderRadius: BorderRadius.circular(DS.radiusLg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('TOTAL ADEUDADO',
                  style:
                      DS.eyebrow(color: Colors.white.withValues(alpha: 0.6))),
              const SizedBox(height: 4),
              Text(formatMoney(total),
                  style: DS.numeric(32,
                      color: Colors.white, weight: FontWeight.w700)),
              const SizedBox(height: DS.space3),
              Text(
                '${debts.length} ${debts.length == 1 ? "orden" : "órdenes"} pendientes de pago',
                style:
                    DS.ui(12, color: Colors.white.withValues(alpha: 0.7)),
              ),
              if (creditLimit > 0) ...[
                const SizedBox(height: DS.space4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(DS.radiusSm),
                  child: LinearProgressIndicator(
                    value: (total / creditLimit).clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: Colors.white.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation(
                      total >= creditLimit ? DS.danger : DS.brandOrange,
                    ),
                  ),
                ),
                const SizedBox(height: DS.space2),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Límite: ${formatMoney(creditLimit)}',
                        style: DS.ui(11,
                            color: Colors.white.withValues(alpha: 0.6))),
                    Text(
                      'Disponible: ${formatMoney((creditLimit - total).clamp(0.0, double.infinity))}',
                      style: DS.ui(11,
                          color: Colors.white.withValues(alpha: 0.6),
                          weight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: DS.space4),

        Container(
          padding: const EdgeInsets.all(DS.space3),
          decoration: BoxDecoration(
            color: DS.infoBg,
            borderRadius: BorderRadius.circular(DS.radiusSm),
            border:
                Border.all(color: DS.info.withValues(alpha: 0.2), width: 1),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: DS.info, size: 14),
              const SizedBox(width: DS.space2),
              Expanded(
                child: Text(
                  'Coordina el pago con la central. Cuando paguen, el admin marcará tu deuda como saldada y desaparecerá de aquí.',
                  style: DS.ui(11, color: DS.info, height: 1.5),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: DS.space4),

        for (final o in debts) ...[
          _DebtOrderCard(order: o),
          const SizedBox(height: DS.space3),
        ],
      ],
    );
  }
}

class _DebtOrderCard extends StatelessWidget {
  final DeliveryOrder order;
  const _DebtOrderCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final daysOld = DateTime.now().difference(order.createdAt).inDays;

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
              Text('Orden #${order.number}',
                  style: DS.numeric(14, weight: FontWeight.w700)),
              const SizedBox(width: DS.space2),
              Text(formatDate(order.createdAt),
                  style: DS.ui(11, color: DS.inkMuted)),
              const Spacer(),
              if (daysOld >= 7)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: DS.danger.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(DS.radiusSm),
                  ),
                  child: Text('$daysOld días',
                      style: DS.ui(9,
                          color: DS.danger, weight: FontWeight.w700)),
                )
              else if (daysOld >= 3)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: DS.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(DS.radiusSm),
                  ),
                  child: Text('$daysOld días',
                      style: DS.ui(9,
                          color: DS.warning, weight: FontWeight.w700)),
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
          const SizedBox(height: DS.space3),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: DS.space3, vertical: DS.space3),
            decoration: BoxDecoration(
              color: DS.warning.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(DS.radiusSm),
            ),
            child: Row(
              children: [
                const Icon(Icons.schedule, color: DS.warning, size: 16),
                const SizedBox(width: DS.space3),
                Expanded(
                  child: Text('Pendiente de pago',
                      style: DS.ui(12,
                          color: DS.warning, weight: FontWeight.w600)),
                ),
                Text(formatMoney(order.amount),
                    style: DS.numeric(15,
                        weight: FontWeight.w700, color: DS.warning)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
