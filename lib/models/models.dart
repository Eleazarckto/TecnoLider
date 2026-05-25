import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

// ====================== ENUMS ======================
enum UserRole { superAdmin, admin, operator, company, rider }

enum OrderStatus { awaitingQuote, quoted, rejected, pending, assigned, inTransit, delivered, cancelled }

enum CommissionType { percentage, fixed }

enum VehicleType { motorcycle, bicycle, van }

enum PaymentFieldType { text, number, phone }

extension OrderStatusX on OrderStatus {
  String get label {
    switch (this) {
      case OrderStatus.awaitingQuote: return 'Esperando cotización';
      case OrderStatus.quoted: return 'Cotización enviada';
      case OrderStatus.rejected: return 'Rechazada';
      case OrderStatus.pending: return 'Por asignar';
      case OrderStatus.assigned: return 'Asignada';
      case OrderStatus.inTransit: return 'En camino';
      case OrderStatus.delivered: return 'Entregada';
      case OrderStatus.cancelled: return 'Cancelada';
    }
  }

  String get apiValue {
    switch (this) {
      case OrderStatus.awaitingQuote: return 'awaitingQuote';
      case OrderStatus.quoted: return 'quoted';
      case OrderStatus.rejected: return 'rejected';
      case OrderStatus.pending: return 'pending';
      case OrderStatus.assigned: return 'assigned';
      case OrderStatus.inTransit: return 'inTransit';
      case OrderStatus.delivered: return 'delivered';
      case OrderStatus.cancelled: return 'cancelled';
    }
  }

  static OrderStatus fromApi(String s) {
    switch (s) {
      case 'awaitingQuote': return OrderStatus.awaitingQuote;
      case 'quoted': return OrderStatus.quoted;
      case 'rejected': return OrderStatus.rejected;
      case 'pending': return OrderStatus.pending;
      case 'assigned': return OrderStatus.assigned;
      case 'inTransit': return OrderStatus.inTransit;
      case 'delivered': return OrderStatus.delivered;
      case 'cancelled': return OrderStatus.cancelled;
      default: return OrderStatus.awaitingQuote;
    }
  }
}

extension UserRoleX on UserRole {
  String get label {
    switch (this) {
      case UserRole.superAdmin: return 'Super Admin';
      case UserRole.admin: return 'Administrador';
      case UserRole.operator: return 'Operador';
      case UserRole.company: return 'Empresa';
      case UserRole.rider: return 'Motorizado';
    }
  }

  String get apiValue {
    switch (this) {
      case UserRole.superAdmin: return 'superAdmin';
      case UserRole.admin: return 'admin';
      case UserRole.operator: return 'operator';
      case UserRole.company: return 'company';
      case UserRole.rider: return 'rider';
    }
  }

  static UserRole fromApi(String s) {
    switch (s) {
      case 'superAdmin': return UserRole.superAdmin;
      case 'admin': return UserRole.admin;
      case 'operator': return UserRole.operator;
      case 'company': return UserRole.company;
      case 'rider': return UserRole.rider;
      default: return UserRole.admin;
    }
  }
}

extension VehicleTypeX on VehicleType {
  String get label {
    switch (this) {
      case VehicleType.motorcycle: return 'Motocicleta';
      case VehicleType.bicycle: return 'Bicicleta';
      case VehicleType.van: return 'Furgoneta';
    }
  }

  String get apiValue {
    switch (this) {
      case VehicleType.motorcycle: return 'motorcycle';
      case VehicleType.bicycle: return 'bicycle';
      case VehicleType.van: return 'van';
    }
  }

  static VehicleType fromApi(String s) {
    switch (s) {
      case 'motorcycle': return VehicleType.motorcycle;
      case 'bicycle': return VehicleType.bicycle;
      case 'van': return VehicleType.van;
      default: return VehicleType.motorcycle;
    }
  }
}

extension CommissionTypeX on CommissionType {
  String get apiValue =>
      this == CommissionType.percentage ? 'percentage' : 'fixed';

  static CommissionType fromApi(String s) =>
      s == 'fixed' ? CommissionType.fixed : CommissionType.percentage;
}

extension PaymentFieldTypeX on PaymentFieldType {
  String get apiValue {
    switch (this) {
      case PaymentFieldType.text: return 'text';
      case PaymentFieldType.number: return 'number';
      case PaymentFieldType.phone: return 'phone';
    }
  }

  String get label {
    switch (this) {
      case PaymentFieldType.text: return 'Texto';
      case PaymentFieldType.number: return 'Número';
      case PaymentFieldType.phone: return 'Teléfono';
    }
  }

  static PaymentFieldType fromApi(String s) {
    switch (s) {
      case 'number': return PaymentFieldType.number;
      case 'phone': return PaymentFieldType.phone;
      default: return PaymentFieldType.text;
    }
  }
}

// ===== HELPERS ROBUSTOS PARA PARSEAR JSON =====

double _asDouble(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

double? _asDoubleOrNull(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

/// Convierte cualquier tipo de valor (int, String, bool) a bool.
/// MySQL devuelve 0/1 que no se castea automáticamente a bool en Dart.
bool _asBool(dynamic v) {
  if (v == null) return false;
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final lc = v.toLowerCase();
    return lc == 'true' || lc == '1' || lc == 'yes';
  }
  return false;
}

int _asInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}

int? _asIntOrNull(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

String _asString(dynamic v, [String defaultValue = '']) {
  if (v == null) return defaultValue;
  return v.toString();
}

DateTime? _asDate(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  return DateTime.tryParse(v.toString());
}

// ====================== USER ======================
class AppUser {
  final String id;
  String email;
  String name;
  UserRole role;
  String? linkedEntityId;

  AppUser({
    String? id,
    required this.email,
    required this.name,
    required this.role,
    this.linkedEntityId,
  }) : id = id ?? _uuid.v4();

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: _asString(j['id']),
        email: _asString(j['email']),
        name: _asString(j['name']),
        role: UserRoleX.fromApi(_asString(j['role'])),
        linkedEntityId: j['linkedId']?.toString(),
      );
}

// ====================== COMPANY ======================
class Company {
  final String id;
  String name;
  String email;
  String phone;
  String address;
  bool active;
  bool payLaterEnabled;
  double creditLimit;
  double? latitude;
  double? longitude;
  final DateTime createdAt;

  Company({
    String? id,
    required this.name,
    required this.email,
    required this.phone,
    required this.address,
    this.active = true,
    this.payLaterEnabled = false,
    this.creditLimit = 0,
    this.latitude,
    this.longitude,
    DateTime? createdAt,
  })  : id = id ?? _uuid.v4(),
        createdAt = createdAt ?? DateTime.now();

  bool get hasLocation => latitude != null && longitude != null;

  factory Company.fromJson(Map<String, dynamic> j) => Company(
        id: _asString(j['id']),
        name: _asString(j['name']),
        email: _asString(j['email']),
        phone: _asString(j['phone']),
        address: _asString(j['address']),
        active: _asBool(j['active']),
        payLaterEnabled: _asBool(j['payLaterEnabled']),
        creditLimit: _asDouble(j['creditLimit']),
        latitude: _asDoubleOrNull(j['latitude']),
        longitude: _asDoubleOrNull(j['longitude']),
        createdAt: _asDate(j['createdAt']) ?? DateTime.now(),
      );
}

// ====================== RIDER ======================
class Rider {
  final String id;
  String name;
  String email;
  String phone;
  VehicleType vehicle;
  String plate;
  bool active;
  final DateTime createdAt;

  Rider({
    String? id,
    required this.name,
    required this.email,
    required this.phone,
    required this.vehicle,
    required this.plate,
    this.active = true,
    DateTime? createdAt,
  })  : id = id ?? _uuid.v4(),
        createdAt = createdAt ?? DateTime.now();

  factory Rider.fromJson(Map<String, dynamic> j) => Rider(
        id: _asString(j['id']),
        name: _asString(j['name']),
        email: _asString(j['email']),
        phone: _asString(j['phone']),
        vehicle: VehicleTypeX.fromApi(_asString(j['vehicle'], 'motorcycle')),
        plate: _asString(j['plate']),
        active: _asBool(j['active']),
        createdAt: _asDate(j['createdAt']) ?? DateTime.now(),
      );
}

// ====================== OPERATOR ======================
class Operator {
  final String id;
  String name;
  String email;
  String phone;
  bool active;
  final DateTime createdAt;

  Operator({
    String? id,
    required this.name,
    required this.email,
    required this.phone,
    this.active = true,
    DateTime? createdAt,
  })  : id = id ?? _uuid.v4(),
        createdAt = createdAt ?? DateTime.now();

  factory Operator.fromJson(Map<String, dynamic> j) => Operator(
        id: _asString(j['id']),
        name: _asString(j['name']),
        email: _asString(j['email']),
        phone: _asString(j['phone']),
        active: _asBool(j['active']),
        createdAt: _asDate(j['createdAt']) ?? DateTime.now(),
      );
}

// ====================== ORDER ======================
class DeliveryOrder {
  final String id;
  final int number;
  String companyId;
  String? riderId;
  String customer;
  String customerPhone;
  String address;
  String description;
  double amount;
  double riderCommission;
  double centralProfit;
  CommissionType commissionType;
  double commissionValue;
  OrderStatus status;
  final DateTime createdAt;
  DateTime updatedAt;
  DateTime? assignedAt;
  DateTime? deliveredAt;
  DateTime? quotedAt;
  DateTime? acceptedAt;
  DateTime? rejectedAt;
  DateTime? cancelledAt;
  DateTime? paidAt;
  String? companyName;
  String? riderName;
  String? paymentMethodName;
  int? paymentMethodId;
  bool payLater;
  String? payoutId;
  double? pickupLat;
  double? pickupLng;
  double? dropoffLat;
  double? dropoffLng;

  DeliveryOrder({
    String? id,
    required this.number,
    required this.companyId,
    this.riderId,
    required this.customer,
    required this.customerPhone,
    required this.address,
    required this.description,
    required this.amount,
    required this.riderCommission,
    required this.centralProfit,
    required this.commissionType,
    required this.commissionValue,
    this.status = OrderStatus.awaitingQuote,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.assignedAt,
    this.deliveredAt,
    this.quotedAt,
    this.acceptedAt,
    this.rejectedAt,
    this.cancelledAt,
    this.paidAt,
    this.companyName,
    this.riderName,
    this.paymentMethodName,
    this.paymentMethodId,
    this.payLater = false,
    this.payoutId,
    this.pickupLat,
    this.pickupLng,
    this.dropoffLat,
    this.dropoffLng,
  })  : id = id ?? _uuid.v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  bool get isDebt =>
      payLater && paidAt == null && status != OrderStatus.cancelled;

  bool get hasPickupLocation => pickupLat != null && pickupLng != null;
  bool get hasDropoffLocation => dropoffLat != null && dropoffLng != null;
  bool get hasBothLocations => hasPickupLocation && hasDropoffLocation;

  factory DeliveryOrder.fromJson(Map<String, dynamic> j) => DeliveryOrder(
        id: _asString(j['id']),
        number: _asInt(j['number']),
        companyId: _asString(j['companyId']),
        riderId: j['riderId']?.toString(),
        customer: _asString(j['customer']),
        customerPhone: _asString(j['customerPhone']),
        address: _asString(j['address']),
        description: _asString(j['description']),
        amount: _asDouble(j['amount']),
        riderCommission: _asDouble(j['riderCommission']),
        centralProfit: _asDouble(j['centralProfit']),
        commissionType:
            CommissionTypeX.fromApi(_asString(j['commissionType'], 'percentage')),
        commissionValue: _asDouble(j['commissionValue']),
        status: OrderStatusX.fromApi(_asString(j['status'], 'awaitingQuote')),
        createdAt: _asDate(j['createdAt']) ?? DateTime.now(),
        updatedAt: _asDate(j['updatedAt']) ?? DateTime.now(),
        assignedAt: _asDate(j['assignedAt']),
        deliveredAt: _asDate(j['deliveredAt']),
        quotedAt: _asDate(j['quotedAt']),
        acceptedAt: _asDate(j['acceptedAt']),
        rejectedAt: _asDate(j['rejectedAt']),
        cancelledAt: _asDate(j['cancelledAt']),
        paidAt: _asDate(j['paidAt']),
        companyName: j['companyName']?.toString(),
        riderName: j['riderName']?.toString(),
        paymentMethodName: j['paymentMethodName']?.toString(),
        paymentMethodId: _asIntOrNull(j['paymentMethodId']),
        payLater: _asBool(j['payLater']),
        payoutId: j['payoutId']?.toString(),
        pickupLat: _asDoubleOrNull(j['pickupLat']),
        pickupLng: _asDoubleOrNull(j['pickupLng']),
        dropoffLat: _asDoubleOrNull(j['dropoffLat']),
        dropoffLng: _asDoubleOrNull(j['dropoffLng']),
      );
}

// ====================== APP CONFIG ======================
class AppConfig {
  CommissionType commissionType;
  double commissionValue;
  String currency;
  String currencySymbol;
  bool autoQuoteEnabled;
  double pricePerKm;
  double minPrice;
  double distanceFactor;
  String supportPhone;
  bool routingEnabled;
  bool orsApiKeyConfigured;
  String orsApiKeyHint;
  bool tiersEnabled;
  bool googleApiKeyConfigured;
  String googleApiKeyHint;

  AppConfig({
    this.commissionType = CommissionType.percentage,
    this.commissionValue = 70,
    this.currency = 'USD',
    this.currencySymbol = '\$',
    this.autoQuoteEnabled = true,
    this.pricePerKm = 1.50,
    this.minPrice = 3.00,
    this.distanceFactor = 1.40,
    this.supportPhone = '',
    this.routingEnabled = false,
    this.orsApiKeyConfigured = false,
    this.orsApiKeyHint = '',
    this.tiersEnabled = false,
    this.googleApiKeyConfigured = false,
    this.googleApiKeyHint = '',
  });

  factory AppConfig.fromJson(Map<String, dynamic> j) => AppConfig(
        commissionType:
            CommissionTypeX.fromApi(_asString(j['commissionType'], 'percentage')),
        commissionValue: _asDouble(j['commissionValue']),
        currency: _asString(j['currency'], 'USD'),
        currencySymbol: _asString(j['currencySymbol'], '\$'),
        autoQuoteEnabled: _asBool(j['autoQuoteEnabled']),
        pricePerKm: _asDouble(j['pricePerKm']),
        minPrice: _asDouble(j['minPrice']),
        distanceFactor: _asDouble(j['distanceFactor']),
        supportPhone: _asString(j['supportPhone']),
        routingEnabled: _asBool(j['routingEnabled']),
        orsApiKeyConfigured: _asBool(j['orsApiKeyConfigured']),
        orsApiKeyHint: _asString(j['orsApiKeyHint']),
        tiersEnabled: _asBool(j['tiersEnabled']),
        googleApiKeyConfigured: _asBool(j['googleApiKeyConfigured']),
        googleApiKeyHint: _asString(j['googleApiKeyHint']),
      );
}

// ====================== COMMISSION TIER ======================
class CommissionTier {
  final String id;
  double minAmount;
  double companyAmount;

  CommissionTier({
    required this.id,
    required this.minAmount,
    required this.companyAmount,
  });

  factory CommissionTier.fromJson(Map<String, dynamic> j) => CommissionTier(
        id: _asString(j['id']),
        minAmount: _asDouble(j['minAmount']),
        companyAmount: _asDouble(j['companyAmount']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'minAmount': minAmount,
        'companyAmount': companyAmount,
      };

  // Cuanto le toca al motorizado segun este tramo
  double get riderAmount => minAmount - companyAmount;
}

// ====================== PAYMENT METHOD FIELD ======================
class PaymentMethodField {
  final int id;
  final String fieldKey;
  String label;
  PaymentFieldType fieldType;
  bool required;
  int sortOrder;

  PaymentMethodField({
    required this.id,
    required this.fieldKey,
    required this.label,
    this.fieldType = PaymentFieldType.text,
    this.required = true,
    this.sortOrder = 0,
  });

  factory PaymentMethodField.fromJson(Map<String, dynamic> j) =>
      PaymentMethodField(
        id: _asInt(j['id']),
        fieldKey: _asString(j['fieldKey']),
        label: _asString(j['label']),
        fieldType: PaymentFieldTypeX.fromApi(_asString(j['fieldType'], 'text')),
        required: _asBool(j['required']),
        sortOrder: _asInt(j['sortOrder']),
      );

  Map<String, dynamic> toJson() => {
        'fieldKey': fieldKey,
        'label': label,
        'fieldType': fieldType.apiValue,
        'required': required,
      };
}

// ====================== PAYMENT METHOD ======================
class PaymentMethod {
  final int id;
  String name;
  String icon;
  bool active;
  int sortOrder;
  List<PaymentMethodField> fields;
  Map<String, String> values;

  PaymentMethod({
    required this.id,
    required this.name,
    this.icon = 'payment',
    this.active = true,
    this.sortOrder = 0,
    List<PaymentMethodField>? fields,
    Map<String, String>? values,
  })  : fields = fields ?? [],
        values = values ?? {};

  factory PaymentMethod.fromJson(Map<String, dynamic> j) {
    final fieldsList = (j['fields'] as List<dynamic>?)
            ?.map((f) =>
                PaymentMethodField.fromJson(f as Map<String, dynamic>))
            .toList() ??
        [];
    final valuesMap = <String, String>{};
    final rawValues = j['values'];
    if (rawValues is Map) {
      rawValues.forEach((k, v) {
        valuesMap[k.toString()] = v?.toString() ?? '';
      });
    }
    return PaymentMethod(
      id: _asInt(j['id']),
      name: _asString(j['name']),
      icon: _asString(j['icon'], 'payment'),
      active: _asBool(j['active']),
      sortOrder: _asInt(j['sortOrder']),
      fields: fieldsList,
      values: valuesMap,
    );
  }

  bool get hasAllRequiredValues {
    for (final f in fields) {
      if (f.required && (values[f.fieldKey]?.trim().isEmpty ?? true)) {
        return false;
      }
    }
    return true;
  }

  static IconData iconFor(String name) {
    switch (name) {
      case 'payments': return Icons.payments;
      case 'account_balance': return Icons.account_balance;
      case 'phone_android': return Icons.phone_android;
      case 'credit_card': return Icons.credit_card;
      case 'attach_money': return Icons.attach_money;
      case 'qr_code': return Icons.qr_code;
      case 'schedule': return Icons.schedule;
      default: return Icons.payment;
    }
  }
}

// ====================== DEBT SUMMARY ======================
class DebtSummary {
  final List<DeliveryOrder> orders;
  final List<DebtByCompany> byCompany;
  final double grandTotal;
  final int totalCount;

  DebtSummary({
    required this.orders,
    required this.byCompany,
    required this.grandTotal,
    required this.totalCount,
  });

  factory DebtSummary.fromJson(Map<String, dynamic> j) => DebtSummary(
        orders: (j['orders'] as List<dynamic>?)
                ?.map((o) => DeliveryOrder.fromJson(o as Map<String, dynamic>))
                .toList() ??
            [],
        byCompany: (j['byCompany'] as List<dynamic>?)
                ?.map((c) => DebtByCompany.fromJson(c as Map<String, dynamic>))
                .toList() ??
            [],
        grandTotal: _asDouble(j['grandTotal']),
        totalCount: _asInt(j['totalCount']),
      );

  static DebtSummary empty() =>
      DebtSummary(orders: [], byCompany: [], grandTotal: 0, totalCount: 0);
}

class DebtByCompany {
  final String companyId;
  final String companyName;
  final int count;
  final double total;

  DebtByCompany({
    required this.companyId,
    required this.companyName,
    required this.count,
    required this.total,
  });

  factory DebtByCompany.fromJson(Map<String, dynamic> j) => DebtByCompany(
        companyId: _asString(j['companyId']),
        companyName: _asString(j['companyName'], '—'),
        count: _asInt(j['count']),
        total: _asDouble(j['total']),
      );
}

// ====================== PAYOUT PREVIEW ======================
class PayoutPreview {
  final String from;
  final String to;
  final List<RiderPayoutPreview> riders;
  final double grandTotal;
  final int totalOrders;

  PayoutPreview({
    required this.from,
    required this.to,
    required this.riders,
    required this.grandTotal,
    required this.totalOrders,
  });

  factory PayoutPreview.fromJson(Map<String, dynamic> j) => PayoutPreview(
        from: _asString(j['from']),
        to: _asString(j['to']),
        riders: (j['riders'] as List<dynamic>?)
                ?.map((r) =>
                    RiderPayoutPreview.fromJson(r as Map<String, dynamic>))
                .toList() ??
            [],
        grandTotal: _asDouble(j['grandTotal']),
        totalOrders: _asInt(j['totalOrders']),
      );

  static PayoutPreview empty() =>
      PayoutPreview(from: '', to: '', riders: [], grandTotal: 0, totalOrders: 0);
}

class RiderPayoutPreview {
  final String riderId;
  final String riderName;
  final String vehicle;
  final String plate;
  final List<PayoutOrderPreview> orders;
  final int count;
  final double commissionsTotal;

  RiderPayoutPreview({
    required this.riderId,
    required this.riderName,
    required this.vehicle,
    required this.plate,
    required this.orders,
    required this.count,
    required this.commissionsTotal,
  });

  factory RiderPayoutPreview.fromJson(Map<String, dynamic> j) =>
      RiderPayoutPreview(
        riderId: _asString(j['riderId']),
        riderName: _asString(j['riderName'], '—'),
        vehicle: _asString(j['vehicle']),
        plate: _asString(j['plate']),
        orders: (j['orders'] as List<dynamic>?)
                ?.map((o) =>
                    PayoutOrderPreview.fromJson(o as Map<String, dynamic>))
                .toList() ??
            [],
        count: _asInt(j['count']),
        commissionsTotal: _asDouble(j['commissionsTotal']),
      );
}

class PayoutOrderPreview {
  final String id;
  final int number;
  final double amount;
  final double riderCommission;
  final DateTime? deliveredAt;
  final String customer;
  final String address;

  PayoutOrderPreview({
    required this.id,
    required this.number,
    required this.amount,
    required this.riderCommission,
    this.deliveredAt,
    this.customer = '',
    this.address = '',
  });

  factory PayoutOrderPreview.fromJson(Map<String, dynamic> j) =>
      PayoutOrderPreview(
        id: _asString(j['id']),
        number: _asInt(j['number']),
        amount: _asDouble(j['amount']),
        riderCommission: _asDouble(j['riderCommission']),
        deliveredAt: _asDate(j['deliveredAt']),
        customer: _asString(j['customer']),
        address: _asString(j['address']),
      );
}

// ====================== RIDER PAYOUT (saved) ======================
class RiderPayout {
  final String id;
  final String riderId;
  String? riderName;
  final DateTime periodStart;
  final DateTime periodEnd;
  final int ordersCount;
  final double commissionsTotal;
  final double discountTotal;
  final String? note;
  final double netAmount;
  final DateTime paidAt;
  final String? paidBy;
  List<PayoutItem> items;

  RiderPayout({
    required this.id,
    required this.riderId,
    this.riderName,
    required this.periodStart,
    required this.periodEnd,
    required this.ordersCount,
    required this.commissionsTotal,
    required this.discountTotal,
    this.note,
    required this.netAmount,
    required this.paidAt,
    this.paidBy,
    List<PayoutItem>? items,
  }) : items = items ?? [];

  factory RiderPayout.fromJson(Map<String, dynamic> j) => RiderPayout(
        id: _asString(j['id']),
        riderId: _asString(j['riderId']),
        riderName: j['riderName']?.toString(),
        periodStart: _asDate(j['periodStart']) ?? DateTime.now(),
        periodEnd: _asDate(j['periodEnd']) ?? DateTime.now(),
        ordersCount: _asInt(j['ordersCount']),
        commissionsTotal: _asDouble(j['commissionsTotal']),
        discountTotal: _asDouble(j['discountTotal']),
        note: j['note']?.toString(),
        netAmount: _asDouble(j['netAmount']),
        paidAt: _asDate(j['paidAt']) ?? DateTime.now(),
        paidBy: j['paidBy']?.toString(),
        items: (j['items'] as List<dynamic>?)
                ?.map((i) => PayoutItem.fromJson(i as Map<String, dynamic>))
                .toList() ??
            [],
      );
}

class PayoutItem {
  final String orderId;
  final int number;
  final double commission;
  final double orderDiscount;
  final double amount;
  final String customer;
  final String address;
  final DateTime? deliveredAt;

  PayoutItem({
    required this.orderId,
    required this.number,
    required this.commission,
    required this.orderDiscount,
    this.amount = 0,
    this.customer = '',
    this.address = '',
    this.deliveredAt,
  });

  factory PayoutItem.fromJson(Map<String, dynamic> j) => PayoutItem(
        orderId: _asString(j['orderId']),
        number: _asInt(j['number']),
        commission: _asDouble(j['commission']),
        orderDiscount: _asDouble(j['orderDiscount']),
        amount: _asDouble(j['amount']),
        customer: _asString(j['customer']),
        address: _asString(j['address']),
        deliveredAt: _asDate(j['deliveredAt']),
      );

  double get net => commission - orderDiscount;
}

// ====================== APP LOCK ======================
class AppLock {
  final bool isLocked;
  final String? reason;
  final DateTime? lockedAt;
  final String? lockedBy;

  AppLock({
    this.isLocked = false,
    this.reason,
    this.lockedAt,
    this.lockedBy,
  });

  factory AppLock.fromJson(Map<String, dynamic> j) => AppLock(
        isLocked: _asBool(j['isLocked']),
        reason: j['reason']?.toString(),
        lockedAt: _asDate(j['lockedAt']),
        lockedBy: j['lockedBy']?.toString(),
      );

  static AppLock unlocked() => AppLock();
}

// ====================== RIDER LOCATION ======================
/// Ubicación en tiempo real de un motorizado.
/// `isOnline` viene del backend basado en heartbeat (sesión activa).
/// `onlineStatus` da más detalle: 'online' / 'away' / 'offline'.
class RiderLocation {
  final String riderId;
  final String? riderName;
  final String? vehicle;
  final String? plate;
  final double latitude;
  final double longitude;
  final double? accuracy;
  final double? speed;
  final double? heading;
  final DateTime updatedAt;
  final bool isOnline; // basado en heartbeat del backend
  final String onlineStatus; // 'online' | 'away' | 'offline'

  RiderLocation({
    required this.riderId,
    this.riderName,
    this.vehicle,
    this.plate,
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.speed,
    this.heading,
    required this.updatedAt,
    this.isOnline = false,
    this.onlineStatus = 'offline',
  });

  /// True if the location was updated in the last 10 seconds (muy fresca)
  bool get isFresh =>
      DateTime.now().difference(updatedAt).inSeconds < 10;

  /// True if the location is too old (>30 seconds)
  bool get isStale =>
      DateTime.now().difference(updatedAt).inSeconds >= 30;

  /// True si el motorizado abrio la app recientemente pero no esta enviando
  /// heartbeats ahora (probablemente la app esta en segundo plano o cerrada).
  bool get isAway => onlineStatus == 'away';

  factory RiderLocation.fromJson(Map<String, dynamic> j) => RiderLocation(
        riderId: _asString(j['riderId']),
        riderName: j['riderName']?.toString(),
        vehicle: j['vehicle']?.toString(),
        plate: j['plate']?.toString(),
        latitude: _asDouble(j['latitude']),
        longitude: _asDouble(j['longitude']),
        accuracy: _asDoubleOrNull(j['accuracy']),
        speed: _asDoubleOrNull(j['speed']),
        heading: _asDoubleOrNull(j['heading']),
        updatedAt: _asDate(j['updatedAt']) ?? DateTime.now(),
        isOnline: _asBool(j['isOnline']),
        onlineStatus: _asString(j['onlineStatus'], 'offline'),
      );
}
