import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../services/database.dart';
import '../../widgets/design_system.dart';
import '../../widgets/components.dart';

class AdminConfig extends StatefulWidget {
  const AdminConfig({super.key});

  @override
  State<AdminConfig> createState() => _AdminConfigState();
}

class _AdminConfigState extends State<AdminConfig> {
  final db = Database.instance;

  late CommissionType _type;
  late TextEditingController _value;
  late String _currency;

  late bool _autoQuote;
  late TextEditingController _pricePerKm;
  late TextEditingController _minPrice;
  late TextEditingController _distanceFactor;

  late TextEditingController _supportPhone;

  // Routing
  late bool _routingEnabled;
  late TextEditingController _orsApiKey;
  bool _orsKeyConfigured = false;
  String _orsKeyHint = '';
  bool _testingApiKey = false;

  // Google API key (super admin only)
  late TextEditingController _googleApiKey;
  bool _googleKeyConfigured = false;
  String _googleKeyHint = '';

  // Tramos de comision
  late bool _tiersEnabled;
  List<_TierDraft> _tiers = [];
  bool _loadingTiers = false;

  static const Map<String, String> _currencies = {
    'USD': '\$', 'EUR': '€', 'MXN': '\$',
    'COP': '\$', 'ARS': '\$', 'VES': 'Bs.',
  };

  @override
  void initState() {
    super.initState();
    final c = db.config;
    _type = c.commissionType;
    _value = TextEditingController(text: c.commissionValue.toString());
    _currency = c.currency;
    _autoQuote = c.autoQuoteEnabled;
    _pricePerKm = TextEditingController(text: c.pricePerKm.toStringAsFixed(2));
    _minPrice = TextEditingController(text: c.minPrice.toStringAsFixed(2));
    _distanceFactor = TextEditingController(text: c.distanceFactor.toStringAsFixed(2));
    _supportPhone = TextEditingController(text: c.supportPhone);
    _routingEnabled = c.routingEnabled;
    _orsApiKey = TextEditingController();
    _orsKeyConfigured = c.orsApiKeyConfigured;
    _orsKeyHint = c.orsApiKeyHint;
    _googleApiKey = TextEditingController();
    _googleKeyConfigured = c.googleApiKeyConfigured;
    _googleKeyHint = c.googleApiKeyHint;
    _tiersEnabled = c.tiersEnabled;
    _loadTiers();
  }

  Future<void> _loadTiers() async {
    if (db.tiers.isEmpty) {
      setState(() => _loadingTiers = true);
      try {
        await db.refreshTiers();
      } catch (_) {}
      if (mounted) setState(() => _loadingTiers = false);
    }
    if (mounted) {
      setState(() {
        _tiers = db.tiers
            .map((t) => _TierDraft(
                  id: t.id,
                  min: TextEditingController(
                      text: t.minAmount.toStringAsFixed(2)),
                  company: TextEditingController(
                      text: t.companyAmount.toStringAsFixed(2)),
                ))
            .toList();
      });
    }
  }

  @override
  void dispose() {
    _value.dispose();
    _pricePerKm.dispose();
    _minPrice.dispose();
    _distanceFactor.dispose();
    _supportPhone.dispose();
    _orsApiKey.dispose();
    _googleApiKey.dispose();
    for (final t in _tiers) {
      t.min.dispose();
      t.company.dispose();
    }
    super.dispose();
  }

  Future<void> _saveCommission() async {
    final v = double.tryParse(_value.text);
    if (v == null || v < 0) { showErrorSnack(context, 'Valor inválido'); return; }
    try {
      await db.updateConfig(
        commissionType: _type, commissionValue: v,
        currency: _currency, currencySymbol: _currencies[_currency]!,
      );
      if (!mounted) return;
      showSuccessSnack(context, 'Comisiones actualizadas');
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, 'Error: $e');
    }
  }

  Future<void> _saveAutoQuote() async {
    final perKm = double.tryParse(_pricePerKm.text);
    final minP = double.tryParse(_minPrice.text);
    final factor = double.tryParse(_distanceFactor.text);
    if (perKm == null || perKm < 0) { showErrorSnack(context, 'Precio por km inválido'); return; }
    if (minP == null || minP < 0) { showErrorSnack(context, 'Precio mínimo inválido'); return; }
    if (factor == null || factor < 1 || factor > 3) { showErrorSnack(context, 'Factor debe ser entre 1 y 3'); return; }
    try {
      await db.updateConfig(
        autoQuoteEnabled: _autoQuote,
        pricePerKm: perKm, minPrice: minP, distanceFactor: factor,
      );
      if (!mounted) return;
      showSuccessSnack(context, 'Cotización automática actualizada');
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, 'Error: $e');
    }
  }

  Future<void> _saveSupportPhone() async {
    final phone = _supportPhone.text.trim();
    // Validar formato basico
    if (phone.isNotEmpty) {
      final valid = RegExp(r'^\+?[0-9]{6,20}$').hasMatch(phone);
      if (!valid) {
        showErrorSnack(context,
            'Número inválido. Formato: +584121234567 (sin espacios ni guiones)');
        return;
      }
    }
    try {
      await db.updateConfig(supportPhone: phone);
      if (!mounted) return;
      showSuccessSnack(context,
          phone.isEmpty
              ? 'Número de soporte eliminado'
              : 'Número de soporte actualizado');
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, 'Error: $e');
    }
  }

  Future<void> _saveRouting() async {
    final key = _orsApiKey.text.trim();
    try {
      // Si el campo de api key esta vacio, mandamos null para no cambiarla
      // Si tiene contenido, la actualizamos
      await db.updateConfig(
        routingEnabled: _routingEnabled,
        orsApiKey: key.isEmpty ? null : key,
      );
      if (!mounted) return;
      setState(() {
        _orsKeyConfigured = db.config.orsApiKeyConfigured;
        _orsKeyHint = db.config.orsApiKeyHint;
        _orsApiKey.clear();
      });
      showSuccessSnack(context, 'Configuración de routing actualizada');
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, 'Error: $e');
    }
  }

  Future<void> _testRouting() async {
    if (!_orsKeyConfigured) {
      showErrorSnack(context, 'Primero guarda una API key');
      return;
    }
    setState(() => _testingApiKey = true);
    try {
      final result = await db.testRouting();
      if (!mounted) return;
      setState(() => _testingApiKey = false);

      final success = result['success'] == true;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              Icon(
                success ? Icons.check_circle : Icons.error,
                color: success ? DS.success : DS.danger,
              ),
              const SizedBox(width: 8),
              Text(success ? '¡Funciona!' : 'Error'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(result['message']?.toString() ?? '',
                  style: DS.ui(13, height: 1.5)),
              if (success) ...[
                const SizedBox(height: DS.space3),
                Container(
                  padding: const EdgeInsets.all(DS.space3),
                  decoration: BoxDecoration(
                    color: DS.success.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(DS.radiusMd),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('RUTA DE PRUEBA',
                          style: DS.eyebrow(color: DS.success)),
                      const SizedBox(height: 4),
                      Text(result['testRoute']?.toString() ?? '',
                          style: DS.ui(12, color: DS.inkSecondary)),
                      const SizedBox(height: 4),
                      Text(
                        'Distancia: ${result['distanceKm']} km',
                        style: DS.numeric(16,
                            color: DS.success, weight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Entendido')),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _testingApiKey = false);
      showErrorSnack(context, 'Error al probar: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(DS.space6),
      children: [
        // SOPORTE WhatsApp
        _buildSupportSection(),
        const SizedBox(height: DS.space5),

        // ROUTING - SOLO super admin lo ve
        if (db.currentUser?.role == UserRole.superAdmin) ...[
          _buildRoutingSection(),
          const SizedBox(height: DS.space5),
          _buildGoogleSection(),
          const SizedBox(height: DS.space5),
        ],

        _buildAutoQuoteSection(),
        const SizedBox(height: DS.space5),

        // TRAMOS DE COMISION (unico modo)
        _buildTiersSection(),
      ],
    );
  }

  Widget _buildSupportSection() {
    final hasPhone = _supportPhone.text.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(DS.space6),
      decoration: BoxDecoration(
        color: DS.surfaceRaised,
        borderRadius: BorderRadius.circular(DS.radiusLg),
        border: Border.all(color: DS.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
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
                child: const Icon(Icons.support_agent,
                    color: DS.success, size: 18),
              ),
              const SizedBox(width: DS.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('SOPORTE POR WHATSAPP', style: DS.eyebrow()),
                    const SizedBox(height: 2),
                    Text('Número que verán todos los usuarios',
                        style: DS.display(18, weight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: DS.space3),
          Text(
            'Este es el número de WhatsApp al que se redirige cuando los usuarios pulsan el botón de soporte. Empresas, motorizados y operadores pueden contactarte directamente.',
            style: DS.ui(13, color: DS.inkSecondary, height: 1.6),
          ),
          const SizedBox(height: DS.space5),

          Text('Número de WhatsApp',
              style: DS.ui(12, color: DS.ink, weight: FontWeight.w600)),
          const SizedBox(height: DS.space2),
          TextFormField(
            controller: _supportPhone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              hintText: '+584121234567',
              prefixIcon: Icon(Icons.phone),
              helperText: 'Incluye el código de país. Sin espacios ni guiones.',
              helperMaxLines: 2,
            ),
            onChanged: (_) => setState(() {}),
          ),

          const SizedBox(height: DS.space4),

          // Vista previa del mensaje
          if (hasPhone)
            Container(
              padding: const EdgeInsets.all(DS.space3),
              decoration: BoxDecoration(
                color: DS.success.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(DS.radiusMd),
                border: Border.all(
                    color: DS.success.withValues(alpha: 0.2), width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.check_circle,
                          color: DS.success, size: 14),
                      const SizedBox(width: 6),
                      Text('CONFIGURADO',
                          style: DS.eyebrow(color: DS.success)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Los usuarios serán redirigidos a este número con el mensaje: "Hola, soy [nombre] ([rol]) y necesito ayuda con YJ Delivery."',
                    style: DS.ui(12, color: DS.inkSecondary, height: 1.5),
                  ),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(DS.space3),
              decoration: BoxDecoration(
                color: DS.warning.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(DS.radiusMd),
                border: Border.all(
                    color: DS.warning.withValues(alpha: 0.2), width: 1),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: DS.warning, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Sin número configurado. El botón de soporte no funcionará hasta que pongas un número.',
                      style: DS.ui(12,
                          color: DS.inkSecondary,
                          weight: FontWeight.w500,
                          height: 1.4),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: DS.space5),

          ElevatedButton.icon(
            onPressed: _saveSupportPhone,
            icon: const Icon(Icons.check, size: 16),
            label: const Text('Guardar número de soporte'),
            style: ElevatedButton.styleFrom(
              backgroundColor: DS.success,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoutingSection() {
    return Container(
      padding: const EdgeInsets.all(DS.space6),
      decoration: BoxDecoration(
        color: DS.surfaceRaised,
        borderRadius: BorderRadius.circular(DS.radiusLg),
        border: Border.all(color: DS.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: DS.brandBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(DS.radiusSm),
                ),
                child: const Icon(Icons.route, color: DS.brandBlue, size: 18),
              ),
              const SizedBox(width: DS.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('CÁLCULO DE DISTANCIA', style: DS.eyebrow()),
                    const SizedBox(height: 2),
                    Text('Línea recta o ruta real por calles',
                        style: DS.display(18, weight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: DS.space3),
          Text(
            'Por defecto las distancias se calculan en línea recta × factor de corrección. Si activas OpenRouteService, las distancias serán EXACTAS por calles.',
            style: DS.ui(13, color: DS.inkSecondary, height: 1.6),
          ),
          const SizedBox(height: DS.space5),

          // Switch ON/OFF
          Container(
            padding: const EdgeInsets.all(DS.space3),
            decoration: BoxDecoration(
              color: _routingEnabled
                  ? DS.brandBlue.withValues(alpha: 0.06)
                  : DS.surfaceMuted,
              borderRadius: BorderRadius.circular(DS.radiusMd),
              border: Border.all(
                color: _routingEnabled
                    ? DS.brandBlue.withValues(alpha: 0.3)
                    : DS.border,
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: (_routingEnabled ? DS.brandBlue : DS.inkMuted)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(DS.radiusSm),
                  ),
                  child: Icon(
                    _routingEnabled ? Icons.route : Icons.timeline,
                    color: _routingEnabled ? DS.brandBlue : DS.inkMuted,
                    size: 18,
                  ),
                ),
                const SizedBox(width: DS.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _routingEnabled
                            ? 'RUTA REAL POR CALLES'
                            : 'LÍNEA RECTA × FACTOR',
                        style: DS.ui(11,
                            color: _routingEnabled
                                ? DS.brandBlue
                                : DS.inkMuted,
                            weight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _routingEnabled
                            ? 'Calcula distancias exactas usando OpenRouteService (gratis hasta 2000/día)'
                            : 'Usa la fórmula simple. Gratis ilimitado.',
                        style: DS.ui(12, color: DS.inkSecondary, height: 1.4),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _routingEnabled,
                  onChanged: (v) => setState(() => _routingEnabled = v),
                  activeColor: DS.brandBlue,
                ),
              ],
            ),
          ),

          const SizedBox(height: DS.space5),

          // Estado de la API key
          AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: _routingEnabled ? 1.0 : 0.5,
            child: IgnorePointer(
              ignoring: !_routingEnabled,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Estado actual
                  Container(
                    padding: const EdgeInsets.all(DS.space3),
                    decoration: BoxDecoration(
                      color: _orsKeyConfigured
                          ? DS.success.withValues(alpha: 0.06)
                          : DS.warning.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(DS.radiusMd),
                      border: Border.all(
                        color: (_orsKeyConfigured ? DS.success : DS.warning)
                            .withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _orsKeyConfigured
                              ? Icons.check_circle
                              : Icons.warning_amber_rounded,
                          color: _orsKeyConfigured ? DS.success : DS.warning,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _orsKeyConfigured
                                    ? 'API KEY CONFIGURADA'
                                    : 'SIN API KEY',
                                style: DS.ui(11,
                                    color: _orsKeyConfigured
                                        ? DS.success
                                        : DS.warning,
                                    weight: FontWeight.w700),
                              ),
                              if (_orsKeyConfigured)
                                Text(
                                  'Termina en: $_orsKeyHint',
                                  style: DS.numeric(11,
                                      color: DS.inkSecondary),
                                )
                              else
                                Text(
                                  'Pega tu API key abajo y guarda',
                                  style: DS.ui(11, color: DS.inkSecondary),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: DS.space4),

                  // Input para nueva API key
                  Text(
                    _orsKeyConfigured ? 'Cambiar API key' : 'Pega tu API key',
                    style: DS.ui(12, color: DS.ink, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: DS.space2),
                  TextFormField(
                    controller: _orsApiKey,
                    obscureText: false,
                    decoration: InputDecoration(
                      hintText: _orsKeyConfigured
                          ? 'Dejar vacío para mantener la actual'
                          : '5b3ce3597851...',
                      hintStyle: DS.ui(12,
                          color: DS.inkMuted, weight: FontWeight.normal),
                      prefixIcon: const Icon(Icons.key),
                      helperText:
                          'Obtén tu key gratis en openrouteservice.org/dev (plan Free)',
                      helperMaxLines: 2,
                    ),
                  ),

                  const SizedBox(height: DS.space4),

                  // Botones
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _saveRouting,
                          icon: const Icon(Icons.check, size: 16),
                          label: const Text('Guardar'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: DS.brandBlue,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: DS.space2),
                      ElevatedButton.icon(
                        onPressed:
                            (_testingApiKey || !_orsKeyConfigured)
                                ? null
                                : _testRouting,
                        icon: _testingApiKey
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.wifi_tethering, size: 16),
                        label: const Text('Probar'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: DS.success,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: DS.space3),

                  // Info adicional
                  Container(
                    padding: const EdgeInsets.all(DS.space3),
                    decoration: BoxDecoration(
                      color: DS.surfaceMuted,
                      borderRadius: BorderRadius.circular(DS.radiusMd),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('LÍMITES DEL PLAN GRATIS',
                            style: DS.eyebrow(color: DS.inkMuted)),
                        const SizedBox(height: 4),
                        Text(
                          '• 2,000 cálculos de ruta por día (alcanza para ~200-400 órdenes)\n'
                          '• 40 cálculos por minuto\n'
                          '• Sin costo, sin tarjeta de crédito\n'
                          '• Si se acaba el límite, vuelve automáticamente a línea recta',
                          style: DS.ui(11,
                              color: DS.inkSecondary, height: 1.6),
                        ),
                      ],
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

  Future<void> _saveGoogleKey() async {
    final key = _googleApiKey.text.trim();
    if (key.length < 30) {
      showErrorSnack(context, 'Pega una API key válida de Google');
      return;
    }
    try {
      await db.updateConfig(googleApiKey: key);
      if (!mounted) return;
      setState(() {
        _googleKeyConfigured = db.config.googleApiKeyConfigured;
        _googleKeyHint = db.config.googleApiKeyHint;
        _googleApiKey.clear();
      });
      showSuccessSnack(context, 'Google API key guardada');
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, 'Error: $e');
    }
  }

  Future<void> _removeGoogleKey() async {
    try {
      await db.updateConfig(googleApiKey: '');
      if (!mounted) return;
      setState(() {
        _googleKeyConfigured = false;
        _googleKeyHint = '';
        _googleApiKey.clear();
      });
      showSuccessSnack(context, 'Google API key eliminada');
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, 'Error: $e');
    }
  }

  Widget _buildGoogleSection() {
    return Container(
      padding: const EdgeInsets.all(DS.space6),
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
              const Icon(Icons.search, size: 20, color: DS.brandBlue),
              const SizedBox(width: 8),
              Text('BÚSQUEDA DE DIRECCIONES (GOOGLE)', style: DS.eyebrow()),
            ],
          ),
          const SizedBox(height: DS.space2),
          Text(
            'Pega tu API key de Google Maps para buscar direcciones reales en '
            'Venezuela. Si está vacío, usa OpenStreetMap (gratis pero limitado).',
            style: DS.ui(12, color: DS.inkSecondary, height: 1.4),
          ),
          const SizedBox(height: DS.space2),
          Text(
            'Cómo obtener: console.cloud.google.com → API y servicios → '
            'Credenciales → Crear API Key → Habilitar Geocoding API.',
            style: DS.ui(11, color: DS.inkSecondary, height: 1.3),
          ),
          const SizedBox(height: DS.space4),

          // Estado actual
          Container(
            padding: const EdgeInsets.all(DS.space3),
            decoration: BoxDecoration(
              color: _googleKeyConfigured
                  ? DS.success.withValues(alpha: 0.08)
                  : DS.warning.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(DS.radiusMd),
              border: Border.all(
                color: (_googleKeyConfigured ? DS.success : DS.warning)
                    .withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _googleKeyConfigured ? Icons.check_circle : Icons.warning,
                  color: _googleKeyConfigured ? DS.success : DS.warning,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _googleKeyConfigured
                        ? 'API key configurada $_googleKeyHint'
                        : 'Sin API key - usando OpenStreetMap (limitado en VE)',
                    style: DS.ui(12, color: DS.ink),
                  ),
                ),
                if (_googleKeyConfigured)
                  TextButton(
                    onPressed: _removeGoogleKey,
                    style: TextButton.styleFrom(
                      foregroundColor: DS.danger,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: const Text('Quitar'),
                  ),
              ],
            ),
          ),

          const SizedBox(height: DS.space3),

          TextFormField(
            controller: _googleApiKey,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Pega aquí tu Google API key',
              hintText: 'AIzaSy...',
              prefixIcon: Icon(Icons.vpn_key),
              isDense: true,
            ),
          ),
          const SizedBox(height: DS.space3),
          LoadingButton(
            label: 'Guardar Google API key',
            icon: Icons.save,
            onPressed: _saveGoogleKey,
          ),
        ],
      ),
    );
  }

  Widget _buildAutoQuoteSection() {
    final perKm = double.tryParse(_pricePerKm.text) ?? 0;
    final minP = double.tryParse(_minPrice.text) ?? 0;
    final factor = double.tryParse(_distanceFactor.text) ?? 1.4;
    const exampleDistance = 5.0;

    // Si routing real activo, NO se multiplica por factor (distancia ya es real)
    final useRouting = _routingEnabled && _orsKeyConfigured;
    final calculated =
        useRouting ? (exampleDistance * perKm) : (exampleDistance * factor * perKm);
    final exampleAmount = calculated < minP ? minP : calculated;

    return Container(
      padding: const EdgeInsets.all(DS.space6),
      decoration: BoxDecoration(
        color: DS.surfaceRaised,
        borderRadius: BorderRadius.circular(DS.radiusLg),
        border: Border.all(color: DS.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('COTIZACIÓN AUTOMÁTICA', style: DS.eyebrow()),
          const SizedBox(height: DS.space2),
          Text('Cobra automáticamente según la distancia',
              style: DS.display(20, weight: FontWeight.w500)),
          const SizedBox(height: DS.space2),
          Text(
            'Cuando está activado, las órdenes se cotizan automáticamente al crearse. Si está desactivado, un admin debe cotizarlas a mano.',
            style: DS.ui(13, color: DS.inkSecondary, height: 1.6),
          ),
          const SizedBox(height: DS.space6),

          Container(
            padding: const EdgeInsets.all(DS.space3),
            decoration: BoxDecoration(
              color: _autoQuote ? DS.success.withValues(alpha: 0.06) : DS.surfaceMuted,
              borderRadius: BorderRadius.circular(DS.radiusMd),
              border: Border.all(
                color: _autoQuote ? DS.success.withValues(alpha: 0.3) : DS.border,
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: (_autoQuote ? DS.success : DS.inkMuted).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(DS.radiusSm),
                  ),
                  child: Icon(_autoQuote ? Icons.auto_awesome : Icons.edit_note,
                      color: _autoQuote ? DS.success : DS.inkMuted, size: 18),
                ),
                const SizedBox(width: DS.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_autoQuote ? 'AUTOMÁTICA' : 'MANUAL',
                          style: DS.ui(11,
                              color: _autoQuote ? DS.success : DS.inkMuted,
                              weight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                          _autoQuote
                              ? 'Las órdenes se cotizan automáticamente'
                              : 'Un admin debe cotizar cada orden a mano',
                          style: DS.ui(12, color: DS.inkSecondary, height: 1.4)),
                    ],
                  ),
                ),
                Switch(
                    value: _autoQuote,
                    onChanged: (v) => setState(() => _autoQuote = v),
                    activeColor: DS.success),
              ],
            ),
          ),

          const SizedBox(height: DS.space5),

          AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: _autoQuote ? 1.0 : 0.5,
            child: IgnorePointer(
              ignoring: !_autoQuote,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Precio por kilómetro',
                      style: DS.ui(12, color: DS.ink, weight: FontWeight.w600)),
                  const SizedBox(height: DS.space2),
                  TextFormField(
                    controller: _pricePerKm,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      suffixText: db.config.currencySymbol,
                      helperText: 'Cuánto cobrar por cada km recorrido',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: DS.space4),
                  Text('Precio mínimo',
                      style: DS.ui(12, color: DS.ink, weight: FontWeight.w600)),
                  const SizedBox(height: DS.space2),
                  TextFormField(
                    controller: _minPrice,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      suffixText: db.config.currencySymbol,
                      helperText: 'Monto mínimo aunque la distancia sea corta',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  // Factor de correccion - SOLO se muestra cuando NO hay routing real
                  // Si routing esta activo + API key configurada, el factor ya no se usa
                  if (!(_routingEnabled && _orsKeyConfigured)) ...[
                    const SizedBox(height: DS.space4),
                    Text('Factor de corrección',
                        style: DS.ui(12, color: DS.ink, weight: FontWeight.w600)),
                    const SizedBox(height: DS.space2),
                    TextFormField(
                      controller: _distanceFactor,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        suffixText: 'x',
                        helperText: 'Multiplica la línea recta para aproximar la ruta real (1.4 recomendado)',
                        helperMaxLines: 2,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ] else ...[
                    const SizedBox(height: DS.space4),
                    Container(
                      padding: const EdgeInsets.all(DS.space3),
                      decoration: BoxDecoration(
                        color: DS.brandBlue.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(DS.radiusMd),
                        border: Border.all(
                            color: DS.brandBlue.withValues(alpha: 0.2),
                            width: 1),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline,
                              color: DS.brandBlue, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'El factor de corrección no se usa porque tienes el routing real activado. Las distancias se calculan exactas por calles.',
                              style: DS.ui(11,
                                  color: DS.inkSecondary, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: DS.space5),

                  Container(
                    padding: const EdgeInsets.all(DS.space3),
                    decoration: BoxDecoration(
                      color: DS.brandOrange.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(DS.radiusMd),
                      border: Border.all(
                          color: DS.brandOrange.withValues(alpha: 0.2), width: 1),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('EJEMPLO PARA 5 KM',
                            style: DS.eyebrow(color: DS.brandOrange)),
                        const SizedBox(height: DS.space2),
                        Text(
                            useRouting
                                ? '5 km × ${db.config.currencySymbol}${perKm.toStringAsFixed(2)} = '
                                  '${db.config.currencySymbol}${calculated.toStringAsFixed(2)}'
                                : '5 km × $factor × ${db.config.currencySymbol}${perKm.toStringAsFixed(2)} = '
                                  '${db.config.currencySymbol}${calculated.toStringAsFixed(2)}',
                            style: DS.numeric(13,
                                color: DS.inkSecondary, weight: FontWeight.w500)),
                        if (calculated < minP) ...[
                          const SizedBox(height: 4),
                          Text(
                              '(Menor al mínimo, se cobrará ${db.config.currencySymbol}${minP.toStringAsFixed(2)})',
                              style: DS.ui(11,
                                  color: DS.warning, weight: FontWeight.w600)),
                        ],
                        const SizedBox(height: DS.space2),
                        Row(
                          children: [
                            Text('Total: ',
                                style: DS.ui(13,
                                    color: DS.ink, weight: FontWeight.w600)),
                            Text(
                                '${db.config.currencySymbol}${exampleAmount.toStringAsFixed(2)}',
                                style: DS.numeric(20,
                                    color: DS.brandOrange,
                                    weight: FontWeight.w700)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: DS.space5),
          ElevatedButton.icon(
            onPressed: _saveAutoQuote,
            icon: const Icon(Icons.check, size: 16),
            label: const Text('Guardar cotización automática'),
            style: ElevatedButton.styleFrom(
              backgroundColor: DS.brandOrange,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // ============ TRAMOS DE COMISION ============
  void _addTier() {
    setState(() {
      _tiers.add(_TierDraft(
        min: TextEditingController(text: '0.00'),
        company: TextEditingController(text: '0.00'),
      ));
    });
  }

  Future<void> _removeTier(int index) async {
    final t = _tiers[index];
    final minVal = double.tryParse(t.min.text) ?? 0;
    final confirmed = await confirmAction(
      context,
      title: 'Eliminar tramo',
      message: minVal > 0
          ? 'Se eliminará el tramo de \$${minVal.toStringAsFixed(2)}.\n\nRecuerda guardar los cambios.'
          : '¿Eliminar este tramo?',
      confirmLabel: 'Eliminar',
      isDangerous: true,
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _tiers.removeAt(index);
    });
    // Disponer despues del frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      t.min.dispose();
      t.company.dispose();
    });
  }

  Future<void> _saveTiers() async {
    // Validar cada tramo
    final list = <CommissionTier>[];
    final seenMin = <double>{};
    for (var i = 0; i < _tiers.length; i++) {
      final t = _tiers[i];
      final min = double.tryParse(t.min.text);
      final company = double.tryParse(t.company.text);
      if (min == null || min < 0) {
        showErrorSnack(context, 'Tramo ${i + 1}: monto inválido');
        return;
      }
      if (company == null || company < 0) {
        showErrorSnack(context, 'Tramo ${i + 1}: comisión empresa inválida');
        return;
      }
      if (company > min) {
        showErrorSnack(context,
            'Tramo ${i + 1}: la comisión empresa (${company.toStringAsFixed(2)}) '
            'no puede ser mayor al monto (${min.toStringAsFixed(2)})');
        return;
      }
      if (seenMin.contains(min)) {
        showErrorSnack(context,
            'Hay dos tramos con el mismo monto (${min.toStringAsFixed(2)})');
        return;
      }
      seenMin.add(min);
      list.add(CommissionTier(
        id: t.id ?? '',
        minAmount: min,
        companyAmount: company,
      ));
    }

    try {
      await db.saveTiers(list);
      if (!mounted) return;
      // Recargar drafts con IDs ya asignados por el server
      setState(() {
        for (final t in _tiers) {
          t.min.dispose();
          t.company.dispose();
        }
        _tiers = db.tiers
            .map((t) => _TierDraft(
                  id: t.id,
                  min: TextEditingController(
                      text: t.minAmount.toStringAsFixed(2)),
                  company: TextEditingController(
                      text: t.companyAmount.toStringAsFixed(2)),
                ))
            .toList();
      });
      showSuccessSnack(context, 'Tramos guardados');
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, 'Error al guardar: $e');
    }
  }

  Widget _buildTiersSection() {
    return Container(
      padding: const EdgeInsets.all(DS.space6),
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
              const Icon(Icons.table_chart_outlined,
                  size: 20, color: DS.brandBlue),
              const SizedBox(width: 8),
              Text('TABLA DE COMISIONES POR TRAMO', style: DS.eyebrow()),
            ],
          ),
          const SizedBox(height: DS.space2),
          Text(
            'Define el monto del delivery y cuánto le corresponde a la empresa. '
            'El motorizado recibe automáticamente la diferencia.',
            style: DS.ui(12, color: DS.inkSecondary, height: 1.4),
          ),
          const SizedBox(height: DS.space5),

          // Header de la tabla
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: DS.space3, vertical: DS.space2),
            decoration: BoxDecoration(
              color: DS.surfaceMuted,
              borderRadius: BorderRadius.circular(DS.radiusSm),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text('MONTO DELIVERY', style: DS.eyebrow()),
                ),
                Expanded(
                  flex: 3,
                  child: Text('EMPRESA', style: DS.eyebrow()),
                ),
                Expanded(
                  flex: 3,
                  child: Text('MOTORIZADO', style: DS.eyebrow()),
                ),
                const SizedBox(width: 32),
              ],
            ),
          ),
          const SizedBox(height: DS.space2),

          // Loading
          if (_loadingTiers)
            const Padding(
              padding: EdgeInsets.all(DS.space4),
              child: Center(child: CircularProgressIndicator()),
            )
          // Sin tramos
          else if (_tiers.isEmpty)
            Container(
              padding: const EdgeInsets.all(DS.space4),
              decoration: BoxDecoration(
                color: DS.surfaceMuted,
                borderRadius: BorderRadius.circular(DS.radiusMd),
              ),
              child: Center(
                child: Text(
                  'Sin tramos definidos. Click "Agregar tramo" para empezar.',
                  style: DS.ui(12, color: DS.inkSecondary),
                ),
              ),
            )
          // Lista de tramos
          else
            ..._tiers.asMap().entries.map((entry) {
              final i = entry.key;
              final t = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: DS.space2),
                child: _TierRow(
                  minController: t.min,
                  companyController: t.company,
                  currencySymbol: db.config.currencySymbol,
                  onRemove: () => _removeTier(i),
                  onChanged: () => setState(() {}),
                ),
              );
            }),

          const SizedBox(height: DS.space3),

          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _addTier,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Agregar tramo'),
              ),
              const Spacer(),
              LoadingButton(
                label: 'Guardar tramos',
                icon: Icons.save,
                onPressed: _saveTiers,
              ),
            ],
          ),

          // Ejemplo de calculo
          if (_tiers.isNotEmpty) ...[
            const SizedBox(height: DS.space4),
            Container(
              padding: const EdgeInsets.all(DS.space3),
              decoration: BoxDecoration(
                color: DS.brandBlue.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(DS.radiusMd),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('CÓMO FUNCIONA',
                      style: DS.eyebrow(color: DS.brandBlue)),
                  const SizedBox(height: 6),
                  Text(
                    'El sistema busca el tramo cuyo monto sea menor o igual '
                    'al delivery. Si el delivery es mayor que el último '
                    'tramo, se aplica el tramo más alto. Si es menor que el '
                    'primero, se aplica el primero.\n\n'
                    'Ejemplo: si pones tramo \$1.50 = empresa \$0.50 y tramo '
                    '\$2.00 = empresa \$0.60:\n'
                    '• Delivery \$1.75 → empresa \$0.50, motorizado \$1.25\n'
                    '• Delivery \$2.00 → empresa \$0.60, motorizado \$1.40\n'
                    '• Delivery \$3.50 → empresa \$0.60, motorizado \$2.90',
                    style: DS.ui(11, color: DS.inkSecondary, height: 1.5),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TypeOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  const _TypeOption({required this.icon, required this.title, required this.subtitle, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? DS.ink.withValues(alpha: 0.04) : DS.surfaceRaised,
      borderRadius: BorderRadius.circular(DS.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DS.radiusMd),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(DS.space3),
          decoration: BoxDecoration(
            border: Border.all(color: selected ? DS.ink : DS.border, width: selected ? 1.5 : 1),
            borderRadius: BorderRadius.circular(DS.radiusMd),
          ),
          child: Row(
            children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(color: selected ? DS.ink : DS.surfaceMuted, borderRadius: BorderRadius.circular(DS.radiusSm)),
                child: Icon(icon, size: 15, color: selected ? Colors.white : DS.inkSecondary),
              ),
              const SizedBox(width: DS.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: DS.ui(13, color: DS.ink, weight: FontWeight.w600)),
                    Text(subtitle, style: DS.ui(11, color: DS.inkMuted), overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              if (selected) const Icon(Icons.check_circle, size: 16, color: DS.ink),
            ],
          ),
        ),
      ),
    );
  }
}

class _SampleRow {
  final double amount;
  final double commission;
  final double central;
  _SampleRow({required this.amount, required this.commission, required this.central});
}

class _TierDraft {
  final String? id;
  final TextEditingController min;
  final TextEditingController company;
  _TierDraft({this.id, required this.min, required this.company});
}

class _TierRow extends StatelessWidget {
  final TextEditingController minController;
  final TextEditingController companyController;
  final String currencySymbol;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  const _TierRow({
    required this.minController,
    required this.companyController,
    required this.currencySymbol,
    required this.onRemove,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final min = double.tryParse(minController.text) ?? 0;
    final company = double.tryParse(companyController.text) ?? 0;
    final rider = (min - company).clamp(0, double.infinity);

    return Row(
      children: [
        Expanded(
          flex: 3,
          child: TextFormField(
            controller: minController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              prefixText: currencySymbol,
              isDense: true,
            ),
            onChanged: (_) => onChanged(),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: TextFormField(
            controller: companyController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              prefixText: currencySymbol,
              isDense: true,
            ),
            onChanged: (_) => onChanged(),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 8, vertical: 12),
            decoration: BoxDecoration(
              color: DS.warning.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(DS.radiusSm),
              border: Border.all(
                  color: DS.warning.withValues(alpha: 0.2), width: 1),
            ),
            child: Text(
              '$currencySymbol${rider.toStringAsFixed(2)}',
              style: DS.numeric(13,
                  color: DS.warning, weight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        IconButton(
          onPressed: onRemove,
          icon: const Icon(Icons.delete_outline, color: DS.danger, size: 20),
          tooltip: 'Eliminar tramo',
        ),
      ],
    );
  }
}
