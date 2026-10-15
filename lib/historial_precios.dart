// ════════════════════════════════════════════════════════════════════
//  HISTORIAL DE PRECIOS Y PRECIOS GUARDADOS CON LA FACTURA
// ════════════════════════════════════════════════════════════════════
//  Lógica pura (sin UI ni backend), probada en
//  test/historial_precios_test.dart.
//
//  ¿Por qué existe? El dueño actualizó el precio de un producto y la
//  "ganancia real" de una venta ANTERIOR de ese producto cambió. La
//  base de datos no guarda el precio por renglón (factura_items y
//  factura_pagos no lo tienen), así que finanzas tomaba el precio y el
//  costo ACTUALES del catálogo para ventas viejas.
//
//  Ahora, sin tocar el servidor (todo va en la tabla `configuracion`):
//   1. Cada vez que cambia el costo o el precio de venta de un producto
//      se guarda el precio ANTERIOR con su vigencia ("valió hasta tal
//      momento") en `hist_precio_<codigo>`, junto con el precio que
//      tenía en cada lista de precios (Krece, Cashea…).
//   2. Al facturar se guarda una foto de los precios de esa factura
//      (costo, contado, lista de la financiadora, tasa BCV y divisa del
//      día) en `snap_fac_<nro>`. Si existe, manda sobre el historial.
//   3. Una venta sin foto ni historial usa el precio actual (es lo único
//      que hay) y se marca así en pantalla.
// ════════════════════════════════════════════════════════════════════

import 'finanzas_tienda.dart';

double _n(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0;

/// Clave de `configuracion` con el historial de precios de un producto.
String claveHistorialPrecio(String codigo) => 'hist_precio_${codigo.trim()}';

/// Clave de `configuracion` con la foto de precios de una factura.
String claveSnapshotFactura(String nroFactura) =>
    'snap_fac_${nroFactura.trim()}';

/// Precio de un producto en una lista de precios en un momento dado.
class PrecioListaCF {
  final String lista;
  final String financiadora;
  final double precio;
  const PrecioListaCF(
      {required this.lista, this.financiadora = '', required this.precio});
  factory PrecioListaCF.fromJson(Map m) => PrecioListaCF(
        lista: (m['n'] ?? '').toString(),
        financiadora: (m['f'] ?? '').toString(),
        precio: _n(m['p']),
      );
  Map<String, dynamic> toJson() =>
      {'n': lista, if (financiadora.isNotEmpty) 'f': financiadora, 'p': precio};
}

/// Los precios que tuvo un producto HASTA [vigenteHasta] (el momento en
/// que alguien los cambió).
class CambioPrecioCF {
  final DateTime vigenteHasta;
  final double costo;
  final double venta;
  final List<PrecioListaCF> listas;
  /// Quién hizo el cambio (para auditoría).
  final String usuario;
  const CambioPrecioCF({
    required this.vigenteHasta,
    required this.costo,
    required this.venta,
    this.listas = const [],
    this.usuario = '',
  });

  factory CambioPrecioCF.fromJson(Map m) => CambioPrecioCF(
        vigenteHasta:
            DateTime.tryParse((m['h'] ?? '').toString()) ?? DateTime(2000),
        costo: _n(m['c']),
        venta: _n(m['v']),
        listas: [
          for (final x in (m['l'] is List ? m['l'] as List : const []))
            if (x is Map) PrecioListaCF.fromJson(x),
        ],
        usuario: (m['u'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {
        'h': vigenteHasta.toIso8601String(),
        'c': costo,
        'v': venta,
        if (listas.isNotEmpty) 'l': [for (final l in listas) l.toJson()],
        if (usuario.isNotEmpty) 'u': usuario,
      };
}

/// Lee el historial guardado (lista JSON ya decodificada).
List<CambioPrecioCF> leerHistorialPrecio(dynamic lista) => [
      for (final x in (lista is List ? lista : const []))
        if (x is Map) CambioPrecioCF.fromJson(x),
    ]..sort((a, b) => a.vigenteHasta.compareTo(b.vigenteHasta));

/// Agrega [cambio] al historial [actual] (lista JSON) y lo devuelve
/// ordenado. Se guardan los [maximo] cambios más recientes para que el
/// valor en `configuracion` no crezca sin límite.
List<Map<String, dynamic>> agregarCambioPrecio(
    dynamic actual, CambioPrecioCF cambio,
    {int maximo = 200}) {
  final h = leerHistorialPrecio(actual)..add(cambio);
  h.sort((a, b) => a.vigenteHasta.compareTo(b.vigenteHasta));
  final desde = h.length > maximo ? h.length - maximo : 0;
  return [for (final c in h.sublist(desde)) c.toJson()];
}

/// Precios con que se valora una venta hecha en [momento].
class PreciosVigentesCF {
  final double costo;
  final double venta;
  /// [origenPrecioFactura], [origenPrecioHistorial] u [origenPrecioActual].
  final String origen;
  /// Precios en las listas en ese momento (null = usar las actuales).
  final List<PrecioListaCF>? listas;
  const PreciosVigentesCF({
    required this.costo,
    required this.venta,
    required this.origen,
    this.listas,
  });
}

/// Precio y costo VIGENTES en [momento]: el primer cambio posterior a
/// la venta guarda lo que valía en ese momento. Si después de la venta
/// no hubo cambios, valen los actuales.
PreciosVigentesCF preciosVigentesEn(
  List<CambioPrecioCF> historial,
  DateTime momento, {
  required double costoActual,
  required double ventaActual,
}) {
  final h = [...historial]
    ..sort((a, b) => a.vigenteHasta.compareTo(b.vigenteHasta));
  for (final c in h) {
    if (c.vigenteHasta.isAfter(momento)) {
      return PreciosVigentesCF(
        costo: c.costo,
        venta: c.venta,
        origen: origenPrecioHistorial,
        listas: c.listas.isEmpty ? null : c.listas,
      );
    }
  }
  return PreciosVigentesCF(
      costo: costoActual, venta: ventaActual, origen: origenPrecioActual);
}

/// Un renglón de la foto de precios de una factura.
class ItemSnapshotCF {
  final String codigo;
  final String imei;
  final double costo;
  final double venta;
  /// Precio en la lista de la financiadora (null = contado / sin lista).
  final double? precioFinanciadora;
  const ItemSnapshotCF({
    required this.codigo,
    this.imei = '',
    required this.costo,
    required this.venta,
    this.precioFinanciadora,
  });
  factory ItemSnapshotCF.fromJson(Map m) => ItemSnapshotCF(
        codigo: (m['c'] ?? '').toString(),
        imei: (m['i'] ?? '').toString(),
        costo: _n(m['co']),
        venta: _n(m['v']),
        precioFinanciadora: m['pf'] == null ? null : _n(m['pf']),
      );
  Map<String, dynamic> toJson() => {
        'c': codigo,
        if (imei.isNotEmpty) 'i': imei,
        'co': costo,
        'v': venta,
        if (precioFinanciadora != null) 'pf': precioFinanciadora,
      };
}

/// Foto de los precios y tasas con que se hizo una factura.
class SnapshotFacturaCF {
  final DateTime momento;
  final double tasaBcv;
  /// Tasa divisa del día si el dueño ya la había cargado (0 = no).
  final double tasaDivisa;
  final String financiadora;
  final String lista;
  final List<ItemSnapshotCF> items;
  const SnapshotFacturaCF({
    required this.momento,
    this.tasaBcv = 0,
    this.tasaDivisa = 0,
    this.financiadora = '',
    this.lista = '',
    required this.items,
  });

  factory SnapshotFacturaCF.fromJson(Map m) => SnapshotFacturaCF(
        momento: DateTime.tryParse((m['t'] ?? '').toString()) ?? DateTime(2000),
        tasaBcv: _n(m['bcv']),
        tasaDivisa: _n(m['div']),
        financiadora: (m['fin'] ?? '').toString(),
        lista: (m['l'] ?? '').toString(),
        items: [
          for (final x in (m['it'] is List ? m['it'] as List : const []))
            if (x is Map) ItemSnapshotCF.fromJson(x),
        ],
      );

  Map<String, dynamic> toJson() => {
        't': momento.toIso8601String(),
        if (tasaBcv > 0) 'bcv': tasaBcv,
        if (tasaDivisa > 0) 'div': tasaDivisa,
        if (financiadora.isNotEmpty) 'fin': financiadora,
        if (lista.isNotEmpty) 'l': lista,
        'it': [for (final i in items) i.toJson()],
      };

  /// El renglón de un equipo (por IMEI) o artículo (por código).
  ItemSnapshotCF? item(String codigo, String imei) {
    if (imei.isNotEmpty) {
      for (final i in items) {
        if (i.imei == imei) return i;
      }
    }
    for (final i in items) {
      if (i.codigo == codigo) return i;
    }
    return null;
  }
}
