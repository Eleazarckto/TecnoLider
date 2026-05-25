import 'package:flutter/foundation.dart';
import '../models/models.dart';
import 'api_client.dart';
import 'geocoding_service.dart';
import 'sync_service.dart';

/// Cached repository that talks to the backend API.
class Database extends ChangeNotifier {
  Database._() {
    SyncService.instance.addListener(_onSyncChanged);
  }
  static final Database instance = Database._();

  final ApiClient _api = ApiClient.instance;
  final SyncService _sync = SyncService.instance;

  // ============ STATE (cached) ============
  AppUser? currentUser;
  List<Company> companies = [];
  List<Rider> riders = [];
  List<Operator> operators = [];
  List<AppUser> users = [];
  List<DeliveryOrder> orders = [];
  List<PaymentMethod> paymentMethods = [];
  List<RiderPayout> myPayouts = []; // for rider
  List<RiderLocation> riderLocations = []; // for admin/operator/company
  AppConfig config = AppConfig();
  AppLock appLock = AppLock.unlocked();

  Map<String, double>? _statsCache;

  bool _loading = false;
  bool get loading => _loading;
  String? lastError;

  // ============ AUTH ============
  Future<AppUser?> login(String email, String password) async {
    try {
      lastError = null;
      final userJson = await _api.login(email, password);
      currentUser = AppUser.fromJson(userJson);
      await refresh();
      await _loadGoogleApiKey();
      _sync.reset();
      _sync.start();
      notifyListeners();
      return currentUser;
    } on ApiException catch (e) {
      lastError = e.message;
      return null;
    } catch (e) {
      lastError = 'Error de conexión: $e';
      return null;
    }
  }

  /// Carga la Google API key del servidor y la configura en GeocodingService.
  /// Falla silenciosamente si no esta configurada o falla la red.
  Future<void> _loadGoogleApiKey() async {
    try {
      final res = await _api.get('/api/me/google-key');
      if (res is Map<String, dynamic>) {
        final key = res['googleApiKey']?.toString() ?? '';
        GeocodingService.instance.setGoogleApiKey(key);
      }
    } catch (_) {
      // No critico - se usa Nominatim como fallback
    }
  }

  Future<void> logout() async {
    _sync.stop();
    _sync.reset();
    await _api.logout();
    currentUser = null;
    companies = [];
    riders = [];
    operators = [];
    users = [];
    orders = [];
    paymentMethods = [];
    myPayouts = [];
    riderLocations = [];
    appLock = AppLock.unlocked();
    _statsCache = null;
    notifyListeners();
  }

  Future<bool> tryRestoreSession() async {
    await _api.loadFromStorage();
    if (!_api.isAuthenticated) return false;
    try {
      final res = await _api.get('/api/auth/me');
      if (res is! Map<String, dynamic>) {
        await _api.logout();
        return false;
      }
      final userJson = res['user'];
      if (userJson is! Map<String, dynamic>) {
        await _api.logout();
        return false;
      }
      currentUser = AppUser.fromJson(userJson);
      await refresh();
      await _loadGoogleApiKey();
      _sync.reset();
      _sync.start();
      notifyListeners();
      return true;
    } catch (_) {
      await _api.logout();
      return false;
    }
  }

  // ============ SYNC HANDLER ============
  void _onSyncChanged() {
    final changed = _sync.changedResources;
    if (changed.isEmpty || currentUser == null) return;
    _refreshSelected(changed);
  }

  Future<void> _refreshSelected(Set<String> resources) async {
    // Capturar el usuario al principio - si cambia durante la ejecucion,
    // no queremos crashear con null pointer
    final user = currentUser;
    if (user == null) return;
    final role = user.role;
    final canSeeEntities = role == UserRole.admin ||
        role == UserRole.superAdmin ||
        role == UserRole.operator;

    try {
      if (resources.contains('orders')) {
        final ordersJson = await _api.get('/api/orders') as List<dynamic>;
        orders = ordersJson
            .map((o) => DeliveryOrder.fromJson(o as Map<String, dynamic>))
            .toList();
        if (canSeeEntities) {
          await _refreshStats();
        }
      }

      if (resources.contains('companies') && canSeeEntities) {
        final j = await _api.get('/api/companies') as List<dynamic>;
        companies = j.map((c) => Company.fromJson(c as Map<String, dynamic>)).toList();
      }

      if (resources.contains('riders') && canSeeEntities) {
        final j = await _api.get('/api/riders') as List<dynamic>;
        riders = j.map((r) => Rider.fromJson(r as Map<String, dynamic>)).toList();
      }

      if (resources.contains('operators') &&
          (role == UserRole.admin || role == UserRole.superAdmin)) {
        final j = await _api.get('/api/operators') as List<dynamic>;
        operators = j.map((o) => Operator.fromJson(o as Map<String, dynamic>)).toList();
      }

      if (resources.contains('admins') &&
          (role == UserRole.admin || role == UserRole.superAdmin)) {
        final j = await _api.get('/api/admins') as List<dynamic>;
        users = j.map((a) {
          final m = a as Map<String, dynamic>;
          return AppUser(
            id: m['id'] as String,
            email: m['email'] as String,
            name: m['name'] as String,
            role: UserRoleX.fromApi(m['role'] as String),
          );
        }).toList();
      }

      if (resources.contains('config')) {
        final cfgJson = await _api.get('/api/config');
        if (cfgJson != null) {
          config = AppConfig.fromJson(cfgJson as Map<String, dynamic>);
        }
      }

      if (resources.contains('payment_methods') ||
          resources.contains('payment_method_fields') ||
          resources.contains('payment_method_values')) {
        await _refreshPaymentMethods();
      }

      if (resources.contains('rider_payouts') && role == UserRole.rider) {
        await _refreshMyPayouts();
      }

      if (resources.contains('app_lock')) {
        await _refreshAppLock();
      }

      // GPS: actualizar ubicaciones cuando cambien
      if (resources.contains('rider_locations')) {
        await _refreshLocations();
      }

      notifyListeners();
    } catch (_) {
      // Network blip - next sync tick will retry
    }
  }

  Future<void> _refreshStats() async {
    try {
      final statsJson = await _api.get('/api/orders/stats') as Map<String, dynamic>;
      _statsCache = {
        'revenue': (statsJson['revenue'] as num).toDouble(),
        'commissions': (statsJson['commissions'] as num).toDouble(),
        'central': (statsJson['central'] as num).toDouble(),
        'total': (statsJson['total'] as num).toDouble(),
        'delivered': (statsJson['delivered'] as num).toDouble(),
        'pending': (statsJson['pending'] as num).toDouble(),
      };
    } catch (_) {}
  }

  Future<void> _refreshPaymentMethods() async {
    try {
      final pmJson = await _api.get('/api/payment-methods/full') as List<dynamic>;
      paymentMethods = pmJson
          .map((m) => PaymentMethod.fromJson(m as Map<String, dynamic>))
          .toList();
    } catch (_) {}
  }

  Future<void> _refreshMyPayouts() async {
    try {
      final j = await _api.get('/api/payouts') as List<dynamic>;
      myPayouts = j
          .map((p) => RiderPayout.fromJson(p as Map<String, dynamic>))
          .toList();
    } catch (_) {}
  }

  Future<void> _refreshAppLock() async {
    try {
      final j = await _api.get('/api/app-lock') as Map<String, dynamic>;
      appLock = AppLock.fromJson(j);
    } catch (_) {}
  }

  Future<void> _refreshLocations() async {
    try {
      final j = await _api.get('/api/locations') as List<dynamic>;
      riderLocations = j
          .map((r) => RiderLocation.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (_) {}
  }

  // ============ DATA REFRESH ============
  Future<void> refresh() async {
    if (currentUser == null) return;
    _loading = true;
    notifyListeners();

    try {
      await _refreshAppLock();

      final cfgJson = await _api.get('/api/config');
      if (cfgJson != null) config = AppConfig.fromJson(cfgJson as Map<String, dynamic>);

      await _refreshPaymentMethods();

      final ordersJson = await _api.get('/api/orders') as List<dynamic>;
      orders = ordersJson
          .map((o) => DeliveryOrder.fromJson(o as Map<String, dynamic>))
          .toList();

      final role = currentUser!.role;
      final canSeeEntities = role == UserRole.admin ||
          role == UserRole.superAdmin ||
          role == UserRole.operator;

      if (canSeeEntities) {
        final companiesJson = await _api.get('/api/companies') as List<dynamic>;
        companies = companiesJson
            .map((c) => Company.fromJson(c as Map<String, dynamic>))
            .toList();

        final ridersJson = await _api.get('/api/riders') as List<dynamic>;
        riders = ridersJson
            .map((r) => Rider.fromJson(r as Map<String, dynamic>))
            .toList();
      } else {
        try {
          final profile = await _api.get('/api/me/profile');
          if (profile != null) {
            final p = profile as Map<String, dynamic>;
            final type = p['type'] as String?;
            final data = p['data'] as Map<String, dynamic>?;
            if (data != null) {
              if (type == 'company') {
                companies = [Company.fromJson(data)];
              } else if (type == 'rider') {
                riders = [Rider.fromJson(data)];
              } else if (type == 'operator') {
                operators = [Operator.fromJson(data)];
              }
            }
          }
        } catch (_) {}
      }

      if (role == UserRole.admin || role == UserRole.superAdmin) {
        final opsJson = await _api.get('/api/operators') as List<dynamic>;
        operators = opsJson
            .map((o) => Operator.fromJson(o as Map<String, dynamic>))
            .toList();

        final adminsJson = await _api.get('/api/admins') as List<dynamic>;
        users = adminsJson.map((a) {
          final m = a as Map<String, dynamic>;
          return AppUser(
            id: m['id'] as String,
            email: m['email'] as String,
            name: m['name'] as String,
            role: UserRoleX.fromApi(m['role'] as String),
          );
        }).toList();

        await _refreshStats();
      }

      if (role == UserRole.rider) {
        await _refreshMyPayouts();
      }

      // GPS: cargar ubicaciones para los roles que las pueden ver
      await _refreshLocations();

      lastError = null;
      _sync.reset();
    } on ApiException catch (e) {
      lastError = e.message;
    } catch (e) {
      lastError = 'Error de conexión: $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // ============ LOOKUPS ============
  Company? companyById(String? id) {
    if (id == null) return null;
    try { return companies.firstWhere((c) => c.id == id); } catch (_) { return null; }
  }

  Rider? riderById(String? id) {
    if (id == null) return null;
    try { return riders.firstWhere((r) => r.id == id); } catch (_) { return null; }
  }

  PaymentMethod? paymentMethodById(int? id) {
    if (id == null) return null;
    try { return paymentMethods.firstWhere((m) => m.id == id); } catch (_) { return null; }
  }

  RiderLocation? riderLocationById(String? id) {
    if (id == null) return null;
    try { return riderLocations.firstWhere((l) => l.riderId == id); } catch (_) { return null; }
  }

  bool emailExists(String email, {String? excludeUserId}) {
    final lc = email.trim().toLowerCase();
    return companies.any((c) => c.email.toLowerCase() == lc) ||
        riders.any((r) => r.email.toLowerCase() == lc) ||
        operators.any((o) => o.email.toLowerCase() == lc) ||
        users.any((u) => u.email.toLowerCase() == lc && u.id != excludeUserId);
  }

  // ============ ORDERS HELPERS ============
  List<DeliveryOrder> ordersByCompany(String companyId) =>
      orders.where((o) => o.companyId == companyId).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  List<DeliveryOrder> ordersByRider(String riderId) =>
      orders.where((o) => o.riderId == riderId).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  List<DeliveryOrder> pendingOrders() =>
      orders.where((o) => o.status == OrderStatus.pending).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  List<DeliveryOrder> activeOrders() => orders
      .where((o) => o.status == OrderStatus.assigned || o.status == OrderStatus.inTransit)
      .toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  List<DeliveryOrder> awaitingQuoteOrders() => orders
      .where((o) =>
          o.status == OrderStatus.awaitingQuote ||
          o.status == OrderStatus.rejected)
      .toList()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  List<DeliveryOrder> quotedOrders() => orders
      .where((o) => o.status == OrderStatus.quoted)
      .toList()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  List<DeliveryOrder> debtOrders({String? companyId}) {
    var list = orders.where((o) => o.isDebt);
    if (companyId != null) list = list.where((o) => o.companyId == companyId);
    return list.toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  // ============ COMPANY CRUD ============
  Future<void> addCompany({
    required String name,
    required String email,
    required String phone,
    required String address,
    required String password,
  }) async {
    await _api.post('/api/companies', {
      'name': name,
      'email': email,
      'phone': phone,
      'address': address,
      'password': password,
    });
    await refresh();
  }

  Future<void> deleteCompany(String id) async {
    await _api.delete('/api/companies/$id');
    await refresh();
  }

  Future<void> setCompanyPayLater(String companyId,
      {required bool enabled, double? creditLimit}) async {
    final body = <String, dynamic>{'enabled': enabled};
    if (creditLimit != null) body['creditLimit'] = creditLimit;
    await _api.put('/api/companies/$companyId/pay-later', body);
    await refresh();
  }

  /// Establece la ubicación GPS de una empresa.
  Future<void> setCompanyCoords(String companyId,
      {required double latitude, required double longitude}) async {
    await _api.put('/api/companies/$companyId/coords', {
      'latitude': latitude,
      'longitude': longitude,
    });
    await refresh();
  }

  // ============ RIDER CRUD ============
  Future<void> addRider({
    required String name,
    required String email,
    required String phone,
    required VehicleType vehicle,
    required String plate,
    required String password,
  }) async {
    await _api.post('/api/riders', {
      'name': name,
      'email': email,
      'phone': phone,
      'vehicle': vehicle.apiValue,
      'plate': plate,
      'password': password,
    });
    await refresh();
  }

  Future<void> deleteRider(String id) async {
    await _api.delete('/api/riders/$id');
    await refresh();
  }

  // ============ OPERATOR CRUD ============
  Future<void> addOperator({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) async {
    await _api.post('/api/operators', {
      'name': name,
      'email': email,
      'phone': phone,
      'password': password,
    });
    await refresh();
  }

  Future<void> deleteOperator(String id) async {
    await _api.delete('/api/operators/$id');
    await refresh();
  }

  // ============ ADMIN CRUD ============
  Future<void> addAdmin({
    required String name,
    required String email,
    required String password,
  }) async {
    await _api.post('/api/admins', {
      'name': name,
      'email': email,
      'password': password,
    });
    await refresh();
  }

  Future<void> deleteUser(String id) async {
    await _api.delete('/api/admins/$id');
    await refresh();
  }

  // ============ PAYMENT METHODS CRUD ============
  Future<void> addPaymentMethod({
    required String name,
    String icon = 'payment',
    int sortOrder = 0,
  }) async {
    await _api.post('/api/payment-methods', {
      'name': name,
      'icon': icon,
      'sortOrder': sortOrder,
    });
    await _refreshPaymentMethods();
    notifyListeners();
  }

  Future<void> deletePaymentMethod(int id) async {
    await _api.delete('/api/payment-methods/$id');
    await _refreshPaymentMethods();
    notifyListeners();
  }

  Future<void> savePaymentMethodFields(
      int methodId, List<PaymentMethodField> fields) async {
    await _api.put('/api/payment-methods/$methodId/fields', {
      'fields': fields.map((f) => f.toJson()).toList(),
    });
    await _refreshPaymentMethods();
    notifyListeners();
  }

  Future<void> savePaymentMethodValues(
      int methodId, Map<String, String> values) async {
    await _api.put('/api/payment-methods/$methodId/values', {
      'values': values,
    });
    await _refreshPaymentMethods();
    notifyListeners();
  }

  // ============ ORDER OPS ============
  Future<DeliveryOrder> createOrder({
    required String companyId,
    required String customer,
    required String customerPhone,
    required String address,
    required String description,
    double? pickupLat,
    double? pickupLng,
    double? dropoffLat,
    double? dropoffLng,
  }) async {
    final body = <String, dynamic>{
      'companyId': companyId,
      'customer': customer,
      'customerPhone': customerPhone,
      'address': address,
      'description': description,
    };
    if (pickupLat != null) body['pickupLat'] = pickupLat;
    if (pickupLng != null) body['pickupLng'] = pickupLng;
    if (dropoffLat != null) body['dropoffLat'] = dropoffLat;
    if (dropoffLng != null) body['dropoffLng'] = dropoffLng;

    final json = await _api.post('/api/orders', body) as Map<String, dynamic>;
    final order = DeliveryOrder.fromJson(json);
    await refresh();
    return order;
  }

  Future<void> quoteOrder(String orderId, double amount) async {
    await _api.post('/api/orders/$orderId/quote', {'amount': amount});
    await refresh();
  }

  Future<void> acceptQuote(String orderId, int paymentMethodId) async {
    await _api.post('/api/orders/$orderId/accept', {
      'paymentMethodId': paymentMethodId,
    });
    await refresh();
  }

  Future<void> acceptQuotePayLater(String orderId) async {
    await _api.post('/api/orders/$orderId/accept', {'payLater': true});
    await refresh();
  }

  Future<void> rejectQuote(String orderId) async {
    await _api.post('/api/orders/$orderId/reject');
    await refresh();
  }

  Future<void> cancelOrderByCompany(String orderId) async {
    await _api.post('/api/orders/$orderId/cancel');
    await refresh();
  }

  Future<void> assignOrder(String orderId, String riderId) async {
    await _api.post('/api/orders/$orderId/assign', {'riderId': riderId});
    await refresh();
  }

  Future<void> updateOrderStatus(String orderId, OrderStatus status) async {
    await _api.patch('/api/orders/$orderId/status', {'status': status.apiValue});
    await refresh();
  }

  Future<void> cancelOrder(String orderId) async {
    await updateOrderStatus(orderId, OrderStatus.cancelled);
  }

  Future<void> markOrderPaid(String orderId) async {
    await _api.post('/api/orders/$orderId/mark-paid');
    await refresh();
  }

  /// Establece las coordenadas de origen y/o destino de una orden.
  Future<void> setOrderCoords(
    String orderId, {
    double? pickupLat,
    double? pickupLng,
    double? dropoffLat,
    double? dropoffLng,
  }) async {
    final body = <String, dynamic>{};
    if (pickupLat != null) body['pickupLat'] = pickupLat;
    if (pickupLng != null) body['pickupLng'] = pickupLng;
    if (dropoffLat != null) body['dropoffLat'] = dropoffLat;
    if (dropoffLng != null) body['dropoffLng'] = dropoffLng;
    if (body.isEmpty) return;
    await _api.put('/api/orders/$orderId/coords', body);
    await refresh();
  }

  // ============ DEBTS ============
  Future<DebtSummary> fetchDebts() async {
    try {
      final j = await _api.get('/api/debts') as Map<String, dynamic>;
      return DebtSummary.fromJson(j);
    } catch (_) {
      return DebtSummary.empty();
    }
  }

  // ============ PAYOUTS ============
  Future<PayoutPreview> previewPayouts({
    required DateTime from,
    required DateTime to,
    String? riderId,
  }) async {
    final fromStr = _ymd(from);
    final toStr = _ymd(to);
    final qs = StringBuffer('?from=$fromStr&to=$toStr');
    if (riderId != null) qs.write('&riderId=$riderId');
    try {
      final j = await _api.get('/api/payouts/preview$qs') as Map<String, dynamic>;
      return PayoutPreview.fromJson(j);
    } catch (_) {
      return PayoutPreview.empty();
    }
  }

  Future<RiderPayout> createPayout({
    required String riderId,
    required DateTime periodStart,
    required DateTime periodEnd,
    required List<String> orderIds,
    Map<String, double>? orderDiscounts,
    double discountTotal = 0,
    String? note,
  }) async {
    final body = <String, dynamic>{
      'riderId': riderId,
      'periodStart': _ymd(periodStart),
      'periodEnd': _ymd(periodEnd),
      'orderIds': orderIds,
      'orderDiscounts': orderDiscounts ?? {},
      'discountTotal': discountTotal,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    };
    final j = await _api.post('/api/payouts', body) as Map<String, dynamic>;
    await refresh();
    return RiderPayout.fromJson(j);
  }

  Future<List<RiderPayout>> fetchPayouts() async {
    try {
      final j = await _api.get('/api/payouts') as List<dynamic>;
      return j
          .map((p) => RiderPayout.fromJson(p as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<RiderPayout?> fetchPayoutById(String id) async {
    try {
      final j = await _api.get('/api/payouts/$id') as Map<String, dynamic>;
      return RiderPayout.fromJson(j);
    } catch (_) {
      return null;
    }
  }

  // ============ APP LOCK ============
  Future<void> setAppLock({required bool locked, String? reason}) async {
    await _api.put('/api/app-lock', {
      'isLocked': locked,
      if (reason != null) 'reason': reason,
    });
    await _refreshAppLock();
    notifyListeners();
  }

  // ============ CONFIG ============
  Future<void> updateConfig({
    CommissionType? commissionType,
    double? commissionValue,
    String? currency,
    String? currencySymbol,
    bool? autoQuoteEnabled,
    double? pricePerKm,
    double? minPrice,
    double? distanceFactor,
    String? supportPhone,
    bool? routingEnabled,
    String? orsApiKey,
    bool? tiersEnabled,
    String? googleApiKey,
  }) async {
    final body = <String, dynamic>{};
    if (commissionType != null) body['commissionType'] = commissionType.apiValue;
    if (commissionValue != null) body['commissionValue'] = commissionValue;
    if (currency != null) body['currency'] = currency;
    if (currencySymbol != null) body['currencySymbol'] = currencySymbol;
    if (autoQuoteEnabled != null) body['autoQuoteEnabled'] = autoQuoteEnabled;
    if (pricePerKm != null) body['pricePerKm'] = pricePerKm;
    if (minPrice != null) body['minPrice'] = minPrice;
    if (distanceFactor != null) body['distanceFactor'] = distanceFactor;
    if (supportPhone != null) body['supportPhone'] = supportPhone;
    if (routingEnabled != null) body['routingEnabled'] = routingEnabled;
    if (orsApiKey != null) body['orsApiKey'] = orsApiKey;
    if (tiersEnabled != null) body['tiersEnabled'] = tiersEnabled;
    if (googleApiKey != null) body['googleApiKey'] = googleApiKey;
    final json = await _api.put('/api/config', body) as Map<String, dynamic>;
    config = AppConfig.fromJson(json);
    // Si se actualizo la Google key, recargarla en GeocodingService
    if (googleApiKey != null) {
      await _loadGoogleApiKey();
    }
    notifyListeners();
  }

  /// Prueba la API key de OpenRouteService configurada
  Future<Map<String, dynamic>> testRouting() async {
    final json = await _api.get('/api/routing/test') as Map<String, dynamic>;
    return json;
  }

  // ============ COMMISSION TIERS ============
  List<CommissionTier> tiers = [];

  Future<void> refreshTiers() async {
    final res = await _api.get('/api/admin/tiers');
    if (res is List) {
      tiers = res
          .whereType<Map<String, dynamic>>()
          .map((j) => CommissionTier.fromJson(j))
          .toList();
      tiers.sort((a, b) => a.minAmount.compareTo(b.minAmount));
      notifyListeners();
    }
  }

  Future<void> saveTiers(List<CommissionTier> newTiers) async {
    // Ordenar por minAmount antes de mandar
    final sorted = [...newTiers]
      ..sort((a, b) => a.minAmount.compareTo(b.minAmount));
    final body = {
      'tiers': sorted
          .map((t) => {
                'minAmount': t.minAmount,
                'companyAmount': t.companyAmount,
              })
          .toList(),
    };
    final res = await _api.put('/api/admin/tiers', body);
    if (res is List) {
      tiers = res
          .whereType<Map<String, dynamic>>()
          .map((j) => CommissionTier.fromJson(j))
          .toList();
      tiers.sort((a, b) => a.minAmount.compareTo(b.minAmount));
      notifyListeners();
    }
  }

  /// Calcula la comision de la empresa para un monto dado usando los tramos.
  /// Devuelve null si no hay tramos disponibles.
  double? calcTierCommission(double amount) {
    if (tiers.isEmpty) return null;
    // Buscar el tramo cuyo minAmount sea <= al monto, usando el mayor que aplique
    CommissionTier? best;
    for (final t in tiers) {
      if (t.minAmount <= amount) {
        if (best == null || t.minAmount > best.minAmount) {
          best = t;
        }
      }
    }
    // Si no hay tramo aplicable, usar el mas bajo
    best ??= tiers.first;
    return best.companyAmount;
  }

  // ============ COMMISSION CALC ============
  /// Calcula la comision del motorizado en preview (antes de enviar al servidor).
  /// Si los tramos estan activos, usa la tabla de tramos.
  /// Si no, usa el modo clasico (porcentaje o fijo).
  double calcCommission(double amount) {
    if (amount <= 0) return 0;
    if (config.tiersEnabled) {
      final companyAmt = calcTierCommission(amount);
      if (companyAmt != null) {
        final rider = amount - companyAmt;
        return rider < 0 ? 0 : double.parse(rider.toStringAsFixed(2));
      }
      // Si no hay tramos, fallback a comportamiento clasico
    }
    if (config.commissionType == CommissionType.percentage) {
      final v = (amount * config.commissionValue) / 100;
      return double.parse(v.toStringAsFixed(2));
    }
    final v = config.commissionValue > amount ? amount : config.commissionValue;
    return double.parse(v.toStringAsFixed(2));
  }

  // ============ STATS ============
  Map<String, double> globalStats() {
    if (_statsCache != null) return _statsCache!;
    final delivered = orders.where((o) => o.status == OrderStatus.delivered);
    final revenue = delivered.fold<double>(0, (s, o) => s + o.amount);
    final commissions = delivered.fold<double>(0, (s, o) => s + o.riderCommission);
    final central = delivered.fold<double>(0, (s, o) => s + o.centralProfit);
    return {
      'revenue': revenue,
      'commissions': commissions,
      'central': central,
      'total': orders.length.toDouble(),
      'delivered': delivered.length.toDouble(),
      'pending': orders.where((o) => o.status == OrderStatus.pending).length.toDouble(),
    };
  }

  Map<String, dynamic> riderStats(String riderId) {
    final mine = ordersByRider(riderId);
    final delivered = mine.where((o) => o.status == OrderStatus.delivered).toList();
    final earned = delivered.fold<double>(0, (s, o) => s + o.riderCommission);
    return {
      'total': mine.length,
      'delivered': delivered.length,
      'active': mine
          .where((o) =>
              o.status == OrderStatus.assigned ||
              o.status == OrderStatus.inTransit)
          .length,
      'earned': earned,
    };
  }

  // ============ HELPERS ============
  String _ymd(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$dd';
  }
}
