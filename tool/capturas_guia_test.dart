// Capturas con indicaciones para la guía (PDF) del dueño, versión 1.0.16.
//
// Se ejecuta con:
//   flutter test tool/capturas_guia_test.dart
//
// Dibuja las pantallas REALES de la app (tablet horizontal 1366x1024 a
// escala 1.5) contra un servidor SIMULADO (MockClient) con datos
// ficticios: nunca toca la API de producción. Además de capturar,
// PRUEBA cada función nueva: que la pantalla abra sin excepciones ni
// desbordes y que sus botones principales hagan lo que deben.
//
// Salida en build/capturas_guia/:
//   · NN_nombre.png  con recuadros rojos y círculos numerados encima.
//   · indice.json    archivo, título y qué señala cada número.
//   · problemas.txt  excepciones / desbordes detectados (si hubo).
//
// Mismo método que tool/capturas_ipad_test.dart.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tecno_lider/finanzas_tienda.dart';
import 'package:tecno_lider/main.dart';

// ═══════════════════════════════════════════════════════ datos ficticios
const _ancho = 1366.0, _alto = 1024.0, _escala = 1.5;
const _tasa = 87.5;
const _principal = 'Tecno Líder Principal', _geo = 'Geo Cell';
const _tiendas = [_principal, _geo];

final _hoy = DateTime.now();
String _f(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
DateTime _dia(int n) {
  // Días del mes en curso sin pasarse de hoy.
  final d = n.clamp(1, _hoy.day);
  return DateTime(_hoy.year, _hoy.month, d);
}

Map<String, dynamic> _p(String c, String n, String cat, String marca,
        String modelo, double costo, double venta,
        {int stock = 0, String tienda = _principal, int? id}) =>
    {
      'id': id ?? (c.hashCode.abs() % 100000),
      'codigo': c, 'nombre': n, 'categoria': cat, 'marca': marca,
      'modelo': modelo, 'tipo': '', 'precio_costo': costo,
      'precio_venta': venta, 'stock_manual': stock, 'tienda': tienda,
      'producto_padre_codigo': '', 'variante': '',
    };

final _productos = <Map<String, dynamic>>[
  _p('TEL-001', 'Honor Play 10 4/128', 'Telefono', 'Honor', 'Play 10', 95, 129),
  _p('TEL-002', 'Honor X6c 6/256', 'Telefono', 'Honor', 'X6c', 125, 169),
  _p('TEL-003', 'Samsung Galaxy A16 4/128', 'Telefono', 'Samsung', 'Galaxy A16', 128, 175),
  _p('TEL-004', 'Samsung Galaxy A26 6/128', 'Telefono', 'Samsung', 'Galaxy A26', 175, 239),
  _p('TEL-005', 'Xiaomi Redmi 14C 4/128', 'Telefono', 'Xiaomi', 'Redmi 14C', 92, 125),
  _p('TEL-006', 'Tecno Spark 30 8/256', 'Telefono', 'Tecno', 'Spark 30', 110, 155),
  _p('ACC-001', 'Cargador rápido 33W', 'Accesorio', 'Genérico', 'N/A', 4, 12, stock: 40),
  _p('ACC-002', 'Audífonos Bluetooth', 'Accesorio', 'Xiaomi', 'Buds 6', 6, 18, stock: 25),
  _p('ACC-003', 'Forro antigolpe', 'Accesorio', 'Genérico', 'N/A', 1.5, 6, stock: 80),
  _p('ACC-003', 'Forro antigolpe', 'Accesorio', 'Genérico', 'N/A', 1.5, 6,
      stock: 30, tienda: _geo, id: 90003),
  _p('ACC-004', 'Vidrio templado', 'Accesorio', 'Genérico', 'N/A', 0.8, 4, stock: 120),
];

double _venta(String c) =>
    (_productos.firstWhere((p) => p['codigo'] == c)['precio_venta'] as num)
        .toDouble();

// Precio por financiadora (lista Krece y Cashea) y BCV.
const _precioKrece = {
  'TEL-001': 165.0, 'TEL-002': 215.0, 'TEL-003': 225.0,
  'TEL-004': 305.0, 'TEL-005': 160.0, 'TEL-006': 199.0,
};
const _precioCashea = {
  'TEL-001': 155.0, 'TEL-002': 205.0, 'TEL-003': 215.0,
  'TEL-004': 289.0, 'TEL-005': 150.0, 'TEL-006': 189.0,
};
double _bcv(String c) => (_venta(c) * 1.18).roundToDouble();

final _imeis = <Map<String, dynamic>>[];
final _facturas = <Map<String, dynamic>>[];
final _servicios = <Map<String, dynamic>>[];
final _config = <String, dynamic>{};
final _pagosFinanciadora = <Map<String, dynamic>>[];
final _peticiones = <String>{};
var _sigId = 5000;

const _clientes = [
  'María González', 'José Pérez', 'Ana Rodríguez', 'Carlos Méndez',
  'Luisa Fernández', 'Pedro Castillo', 'Rosa Martínez', 'Andrés Suárez',
  'Yelitza Mora', 'Freddy Rangel',
];
const _vendedores = ['Laura Ríos', 'Miguel Torres', 'Daniela Salas'];

final _usuarios = <Map<String, dynamic>>[
  {'id': 1, 'nombre': 'Administrador', 'cedula': 'V-00000000',
   'correo': 'dueno@ejemplo.com', 'clave': '', 'rol': 'Dueño',
   'sueldo_base': 0, 'tienda': '', 'gana_comisiones': 0},
  {'id': 2, 'nombre': 'Laura Ríos', 'cedula': 'V-20111222',
   'correo': 'laura@ejemplo.com', 'clave': '', 'rol': 'Vendedor',
   'sueldo_base': 60, 'tienda': _principal, 'gana_comisiones': 1},
  {'id': 3, 'nombre': 'Miguel Torres', 'cedula': 'V-21333444',
   'correo': 'miguel@ejemplo.com', 'clave': '', 'rol': 'Vendedor',
   'sueldo_base': 60, 'tienda': _geo, 'gana_comisiones': 1},
  {'id': 4, 'nombre': 'Daniela Salas', 'cedula': 'V-22555666',
   'correo': 'daniela@ejemplo.com', 'clave': '', 'rol': 'Cajero',
   'sueldo_base': 50, 'tienda': _principal, 'gana_comisiones': 1},
];

var _serie = 350000000000000;
String _nuevoImei(String codigo, String tienda, {required bool vendido}) {
  final imei = '${_serie++}';
  final p = _productos.firstWhere((x) => x['codigo'] == codigo);
  _imeis.add({
    'imei': imei, 'producto_codigo': codigo,
    'fecha_ingreso': _f(DateTime(_hoy.year, _hoy.month, 1)),
    'proveedor': 'Distribuidora Maxi 2005', 'color': 'Negro',
    'ubicacion': tienda, 'porcentaje_bateria': null,
    'vendido': vendido ? 1 : 0,
    'producto_nombre': p['nombre'], 'categoria': p['categoria'],
    'marca': p['marca'], 'modelo': p['modelo'], 'tipo': '',
    'precio_costo': p['precio_costo'], 'precio_venta': p['precio_venta'],
  });
  return imei;
}

var _nro = 1001;
void _factura({
  required String tienda,
  required int dia,
  List<String> equipos = const [],
  List<String> items = const [],
  required List<Map<String, dynamic>> pagos,
  String? vendedor,
}) {
  final n = _nro++;
  final v = vendedor ?? _vendedores[n % _vendedores.length];
  _facturas.add({
    'id': n, 'nro_factura': 'F-$n',
    'cliente': _clientes[n % _clientes.length],
    'cedula': 'V-${12000000 + n * 7919}', 'telefono': '0414-55${n % 10}12${n % 7}3',
    'vendedor': v, 'tienda': tienda, 'fecha': _f(_dia(dia)),
    'creador_rol': 'Vendedor',
    'equipos': [
      for (final c in equipos)
        {'imei': _nuevoImei(c, tienda, vendido: true), 'producto_codigo': c,
         'vendedor': v}
    ],
    'items': [for (final c in items) {'codigo': c, 'vendedor': v}],
    'pagos': pagos,
  });
}

Map<String, dynamic> _usd(double m, {String metodo = 'Divisas'}) =>
    {'metodo': metodo, 'monto': m, 'tipo': 'Contado', 'tasa_cambio': _tasa};
Map<String, dynamic> _bs(double usd) => {
      'metodo': 'Pago Móvil', 'monto': (usd * _tasa), 'tipo': 'Contado',
      'tasa_cambio': _tasa, 'referencia': '0041${usd.toInt()}87',
      'cedula_pagador': 'V-15888777', 'telefono_pagador': '0412-1234567',
      'banco_origen': '0102', 'banco_destino': '0102',
    };
Map<String, dynamic> _inicial(String fin, double m,
        {int cuotas = 6, double cuota = 0, bool enBs = false}) =>
    {
      'metodo': enBs ? 'Pago Móvil' : 'Efectivo \$',
      'monto': enBs ? m * _tasa : m, 'tipo': 'Financiado',
      'financiadora': fin, 'financiador': '', 'es_inicial': 1,
      'numero_cuotas': cuotas > 0 && cuota > 0 ? cuotas : null,
      'monto_cuota': cuota > 0 ? cuota : null,
      'tasa_cambio': _tasa, 'nombre_lista': fin,
    };

void _generarDatos() {
  // ── Ventas del mes (contado, Krece y Cashea en las dos tiendas) ──
  _factura(tienda: _principal, dia: 1, equipos: ['TEL-003'],
      pagos: [_usd(_venta('TEL-003'))]);
  _factura(tienda: _geo, dia: 2, equipos: ['TEL-001'],
      pagos: [_bs(_bcv('TEL-001'))]);
  // Krece: inicial 40 % + 6 cuotas → concuerda.
  _factura(tienda: _principal, dia: 3, equipos: ['TEL-004'],
      items: ['ACC-003'],
      pagos: [
        _inicial('Krece', 122, cuotas: 6, cuota: 30.5),
        _usd(_venta('ACC-003')),
      ]);
  // Krece con la inicial corta → "Diferencia".
  _factura(tienda: _geo, dia: 4, equipos: ['TEL-002'],
      pagos: [_inicial('Krece', 70)]);
  // Cashea con la inicial en Bs → concuerda.
  _factura(tienda: _principal, dia: 5, equipos: ['TEL-006'],
      pagos: [_inicial('Cashea', 75.6, enBs: true)]);
  _factura(tienda: _principal, dia: 6, items: ['ACC-001', 'ACC-004'],
      pagos: [_usd(16)]);
  _factura(tienda: _geo, dia: 7, equipos: ['TEL-005'],
      pagos: [_inicial('Krece', 64)]);
  _factura(tienda: _principal, dia: 8, equipos: ['TEL-001'],
      pagos: [_usd(_venta('TEL-001'), metodo: 'Zelle')]);
  _factura(tienda: _geo, dia: 9, equipos: ['TEL-003'],
      pagos: [_inicial('Cashea', 86)]);
  _factura(tienda: _principal, dia: 10, equipos: ['TEL-005'],
      pagos: [_bs(_bcv('TEL-005'))]);
  _factura(tienda: _geo, dia: 11, items: ['ACC-002'],
      pagos: [_usd(18)]);
  _factura(tienda: _principal, dia: 12, equipos: ['TEL-004'],
      pagos: [_inicial('Krece', 122)]);
  // Ventas de esta semana de Laura (para su billetera).
  _factura(tienda: _principal, dia: _hoy.day, equipos: ['TEL-003'],
      items: ['ACC-004'], vendedor: 'Laura Ríos',
      pagos: [_usd(_venta('TEL-003') + _venta('ACC-004'))]);
  _factura(tienda: _principal, dia: _hoy.day, equipos: ['TEL-006'],
      vendedor: 'Laura Ríos', pagos: [_inicial('Cashea', 75.6)]);

  // Stock disponible
  for (final c in _precioKrece.keys) {
    for (var i = 0; i < 4; i++) {
      _nuevoImei(c, i.isEven ? _principal : _geo, vendido: false);
    }
  }

  // ── Servicio técnico ──
  ServicioTecnico st(int id, String cliente, String marca, String modelo,
          String falla, double monto, String tienda, int dia,
          List<PagoServicioTecnico> pagos, {String estado = 'Recibido'}) =>
      ServicioTecnico(
        id: id, monto: monto, fecha: _dia(dia), nombreCliente: cliente,
        telefono: '0424-7778899', marca: marca, modelo: modelo,
        descripcion: falla, tienda: tienda, pagos: pagos,
        abono: pagos.fold<double>(0, (t, p) => t + p.montoUsd),
        estado: estado,
      );
  final servicios = [
    st(1, 'Rosa Martínez', 'Samsung', 'Galaxy A15', 'Cambio de pantalla',
        45, _principal, 3, [
          PagoServicioTecnico(fecha: _dia(3), metodo: 'Efectivo \$',
              moneda: 'USD', monto: 20, tasa: _tasa, montoUsd: 20),
        ]),
    st(2, 'Freddy Rangel', 'Xiaomi', 'Redmi 13C', 'Pin de carga',
        15, _geo, 6, [
          PagoServicioTecnico(fecha: _dia(6), metodo: 'Pago Móvil',
              moneda: 'Bs', monto: 15 * _tasa, tasa: _tasa, montoUsd: 15,
              referencia: '558877', cedulaPagador: 'V18999000',
              telefonoPagador: '04141112233'),
        ], estado: 'Entregado'),
    st(3, 'Andrés Suárez', 'Honor', 'X8b', 'Batería', 25, _principal, 9, []),
  ];
  _servicios.addAll(servicios.map((s) => {...s.toMap(), 'id': s.id}));

  // ── Costos y Finanzas: gastos, nómina (en configuracion) ──
  final a = _hoy.year, m = _hoy.month;
  _config[claveGastosMes(a, m)] = jsonEncode([
    GastoCF(id: 'g1', fecha: _dia(1), tienda: _principal,
        categoria: 'Gastos fijos', concepto: 'Alquiler del local',
        monto: 350, registradoPor: 'Administrador').toJson(),
    GastoCF(id: 'g2', fecha: _dia(1), tienda: _geo,
        categoria: 'Gastos fijos', concepto: 'Alquiler del local',
        monto: 220, registradoPor: 'Administrador').toJson(),
    GastoCF(id: 'g3', fecha: _dia(5), tienda: _principal,
        categoria: 'Servicios', concepto: 'Internet y electricidad',
        monto: 45, registradoPor: 'Administrador').toJson(),
  ]);
  _config[claveNominaEmpleados] = jsonEncode([
    EmpleadoNomina(nombre: 'Laura Ríos', sueldo: 60).toJson(),
    EmpleadoNomina(nombre: 'Miguel Torres', sueldo: 60).toJson(),
  ]);
  _config[claveNominaPagosMes(a, m)] = jsonEncode([
    PagoNomina(id: 'p1', empleado: 'Laura Ríos', monto: 60,
        fechaPago: _dia(7), registradoPor: 'Administrador',
        registradoEn: _dia(7)).toJson(),
  ]);
}

// ── Listas de precios (se arman con los modelos de la app) ──
List<ListaPrecio> _listas() {
  ItemListaPrecio it(String c, Map<String, double> precios,
          {int? cuotas}) =>
      ItemListaPrecio(
          producto: catalogoGlobal.firstWhere((p) => p.codigo == c),
          preciosPorColumna: precios,
          stockDisponible: 4,
          cuotasOverride: cuotas);
  final tels = _precioKrece.keys;
  return [
    ListaPrecio(id: 11, nombre: 'Divisa', fechaCreacion: _f(_dia(1)),
        columnas: [ColumnaPrecio(nombre: 'Divisa')],
        items: [for (final c in tels) it(c, {'Divisa': _venta(c)})]),
    ListaPrecio(id: 12, nombre: 'BCV', fechaCreacion: _f(_dia(1)),
        columnas: [ColumnaPrecio(nombre: 'BCV')],
        items: [for (final c in tels) it(c, {'BCV': _bcv(c)})]),
    ListaPrecio(id: 13, nombre: 'Krece', fechaCreacion: _f(_dia(1)),
        categoria: 'Telefono',
        esFinanciamiento: true, financiadora: 'Krece',
        porcentajeInicial: 40, numeroCuotas: 6,
        columnas: [
          ColumnaPrecio(nombre: 'Krece'),
          ColumnaPrecio(nombre: 'Nivel 2'),
          ColumnaPrecio(nombre: 'Nivel 3'),
        ],
        items: [
          for (final c in tels)
            it(c, {
              'Krece': _precioKrece[c]!,
              'Nivel 2': (_precioKrece[c]! * 1.05).roundToDouble(),
              'Nivel 3': (_precioKrece[c]! * 1.10).roundToDouble(),
            }, cuotas: c == 'TEL-004' ? 8 : null),
        ]),
    ListaPrecio(id: 14, nombre: 'Cashea', fechaCreacion: _f(_dia(1)),
        categoria: 'Telefono',
        esFinanciamiento: true, financiadora: 'Cashea',
        porcentajeInicial: 40, numeroCuotas: 3,
        columnas: [ColumnaPrecio(nombre: 'Cashea')],
        items: [for (final c in tels) it(c, {'Cashea': _precioCashea[c]!})]),
  ];
}

List<Map<String, dynamic>> _listasJson = [];

final _cxpProveedores = <Map<String, dynamic>>[
  {
    'id': 6, 'rif': 'J-40123456-7', 'nombre': 'Distribuidora Maxi 2005',
    'telefono': '0212-5550000', 'correo': 'ventas@maxi.ejemplo',
    'monto_total': 11956.25, 'fecha_limite': '',
    'notas': 'Mercancía de septiembre [[comp:31]]\n'
        '[03/10/2026] +\$3,450.00 — 20 Galaxy A16\n'
        '[08/10/2026] +\$3,000.00 — repuestos y accesorios',
    'pagos': [
      {'monto': 4000, 'fecha': '05/10/2026', 'metodo': 'Zelle',
       'notas': '[[comp:32]]'},
      {'monto': 2500, 'fecha': '10/10/2026', 'metodo': 'Efectivo \$',
       'notas': ''},
    ],
    'cuotas': [],
  },
  {
    'id': 7, 'rif': 'J-50998877-1', 'nombre': 'Tech Land',
    'telefono': '0241-8887766', 'correo': '',
    'monto_total': 1800, 'fecha_limite': '', 'notas': '',
    'pagos': [
      {'monto': 1950, 'fecha': '07/10/2026', 'metodo': 'Zelle', 'notas': ''},
    ],
    'cuotas': [],
  },
  {
    'id': 8, 'rif': 'J-41222333-0', 'nombre': 'Celulares del Centro',
    'telefono': '0251-4443322', 'correo': '',
    'monto_total': 2600, 'fecha_limite': '', 'notas': '',
    'pagos': [
      {'monto': 1000, 'fecha': '02/10/2026', 'metodo': 'Transferencia',
       'notas': ''},
    ],
    'cuotas': [],
  },
];

late String _jpgBase64;

/// Servidor simulado: responde por `resource` con los datos de arriba.
/// Guarda en memoria lo que la app envía (configuración, cobros, pagos)
/// para que los botones se puedan probar de punta a punta.
http.Client _servidor() => MockClient((req) async {
      final q = req.url.queryParameters;
      final r = q['resource'] ?? '';
      _peticiones.add('${req.method} $r');
      // Cinturón: nada que no sea la API simulada.
      if (!req.url.path.endsWith('api.php')) {
        return http.Response('{}', 404);
      }
      dynamic cuerpo = <dynamic>[];
      Map<String, dynamic> enviado() {
        try {
          final b = jsonDecode(req.body);
          return b is Map ? Map<String, dynamic>.from(b) : {};
        } catch (_) {
          return {};
        }
      }

      switch (req.method) {
        case 'GET':
          switch (r) {
            case 'productos': cuerpo = _productos; break;
            case 'stock_imei': cuerpo = _imeis; break;
            case 'facturas': cuerpo = _facturas; break;
            case 'usuarios': cuerpo = _usuarios; break;
            case 'servicios': cuerpo = _servicios; break;
            case 'listas_precios': cuerpo = _listasJson; break;
            case 'configuracion': cuerpo = _config; break;
            case 'pagos_financiadora': cuerpo = _pagosFinanciadora; break;
            case 'cuentas_pagar_proveedor': cuerpo = _cxpProveedores; break;
            case 'comprobantes':
              cuerpo = q['cuenta_id'] == '6'
                  ? [
                      {'id': 31, 'entidad_tipo': 'factura', 'cuenta_id': 6,
                       'ambito': 'cuentas_pagar_proveedor',
                       'imagen_ext': 'jpg', 'imagen_base64': _jpgBase64,
                       'created_at': '2026-09-28 10:00:00'},
                      {'id': 32, 'entidad_tipo': 'pago', 'cuenta_id': 6,
                       'ambito': 'cuentas_pagar_proveedor',
                       'imagen_ext': 'jpg', 'imagen_base64': _jpgBase64,
                       'created_at': '2026-10-05 15:20:00'},
                    ]
                  : [];
              break;
            case 'tiendas':
              cuerpo = [for (final t in _tiendas) {'nombre': t, 'activa': 1}];
              break;
          }
          break;
        case 'POST':
          final b = enviado();
          if (r == 'configuracion') {
            _config.addAll(b);
            cuerpo = {'ok': true};
          } else if (r == 'pagos_financiadora') {
            final id = _sigId++;
            _pagosFinanciadora.add({...b, 'id': id});
            cuerpo = {'ok': true, 'id': id};
          } else {
            cuerpo = {'ok': true, 'id': _sigId++};
          }
          break;
        case 'PUT':
          final b = enviado();
          if (r == 'servicios') {
            final i = _servicios.indexWhere((s) => '${s['id']}' == q['id']);
            if (i >= 0) _servicios[i] = {...b, 'id': _servicios[i]['id']};
          }
          cuerpo = {'ok': true};
          break;
        default:
          cuerpo = {'ok': true};
      }
      return http.Response(jsonEncode(cuerpo), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });

// ═══════════════════════════════════════════════════════════ fuentes
/// Cambia el grosor declarado (OS/2.usWeightClass) de una fuente TTF en
/// memoria: Segoe UI no trae 500 ni 800 y sin esto esos textos salían
/// con la fuente de prueba (barras).
Uint8List _conPeso(Uint8List b, int peso) {
  final d = ByteData.sublistView(b);
  final n = d.getUint16(4);
  for (var i = 0; i < n; i++) {
    final rec = 12 + i * 16;
    final tag = String.fromCharCodes(b.sublist(rec, rec + 4));
    if (tag == 'OS/2') {
      d.setUint16(d.getUint32(rec + 8) + 4, peso);
    }
  }
  return b;
}

Future<void> _cargarFuentes() async {
  const w = 'C:/Windows/Fonts';
  final material =
      '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
  Uint8List leer(String f) => Uint8List.fromList(File(f).readAsBytesSync());
  final segoe = <Uint8List>[
    for (final f in ['segoeuil.ttf', 'segoeui.ttf', 'seguisb.ttf',
                     'segoeuib.ttf', 'seguibl.ttf', 'segoeuii.ttf',
                     'segoeuiz.ttf', 'seguisbi.ttf', 'seguisym.ttf'])
      leer('$w/$f'),
    _conPeso(leer('$w/segoeuil.ttf'), 100),
    _conPeso(leer('$w/segoeuisl.ttf'), 200),
    _conPeso(leer('$w/seguisb.ttf'), 500),
    _conPeso(leer('$w/segoeuib.ttf'), 800),
  ];
  for (final nombre in ['Roboto', 'Segoe UI', 'FlutterTest', 'Ahem',
                        '.SF UI Text', '.SF UI Display', 'sans-serif',
                        'monospace']) {
    final c = FontLoader(nombre);
    for (final s in segoe) {
      c.addFont(Future.value(ByteData.sublistView(Uint8List.fromList(s))));
    }
    await c.load();
  }
  final mi = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(
        leer('$material/materialicons-regular.otf'))));
  await mi.load();
}

/// Tema de la app con la familia de fuente explícita (ver
/// tool/capturas_ipad_test.dart).
ThemeData _tema() {
  final t = temaAppClaro();
  TextStyle? r(TextStyle? s) => s?.copyWith(fontFamily: 'Roboto');
  ButtonStyle? b(ButtonStyle? s) {
    final ts = s?.textStyle;
    if (s == null || ts == null) return s;
    return s.copyWith(
        textStyle: WidgetStateProperty.resolveWith((e) => r(ts.resolve(e))));
  }
  return t.copyWith(
    elevatedButtonTheme:
        ElevatedButtonThemeData(style: b(t.elevatedButtonTheme.style)),
    filledButtonTheme:
        FilledButtonThemeData(style: b(t.filledButtonTheme.style)),
    outlinedButtonTheme:
        OutlinedButtonThemeData(style: b(t.outlinedButtonTheme.style)),
    textButtonTheme: TextButtonThemeData(style: b(t.textButtonTheme.style)),
    listTileTheme: t.listTileTheme.copyWith(
      titleTextStyle: r(t.listTileTheme.titleTextStyle) ??
          r(t.textTheme.titleMedium),
      subtitleTextStyle: r(t.listTileTheme.subtitleTextStyle) ??
          r(t.textTheme.bodyMedium),
      leadingAndTrailingTextStyle:
          r(t.listTileTheme.leadingAndTrailingTextStyle),
    ),
    textTheme: t.textTheme.apply(fontFamily: 'Roboto'),
    primaryTextTheme: t.primaryTextTheme.apply(fontFamily: 'Roboto'),
    appBarTheme: t.appBarTheme.copyWith(
      titleTextStyle: r(t.appBarTheme.titleTextStyle) ??
          const TextStyle(fontFamily: 'Roboto', fontSize: 20),
      toolbarTextStyle: r(t.appBarTheme.toolbarTextStyle),
    ),
    dialogTheme: t.dialogTheme.copyWith(
      titleTextStyle: r(t.dialogTheme.titleTextStyle),
      contentTextStyle: r(t.dialogTheme.contentTextStyle),
    ),
    snackBarTheme: t.snackBarTheme.copyWith(
      contentTextStyle: r(t.snackBarTheme.contentTextStyle) ??
          const TextStyle(fontFamily: 'Roboto', color: Colors.white),
    ),
    chipTheme: t.chipTheme.copyWith(
      labelStyle: r(t.chipTheme.labelStyle) ??
          const TextStyle(fontFamily: 'Roboto'),
      secondaryLabelStyle: r(t.chipTheme.secondaryLabelStyle),
    ),
    tabBarTheme: t.tabBarTheme.copyWith(
      labelStyle: r(t.tabBarTheme.labelStyle) ??
          const TextStyle(fontFamily: 'Roboto'),
      unselectedLabelStyle: r(t.tabBarTheme.unselectedLabelStyle) ??
          const TextStyle(fontFamily: 'Roboto'),
    ),
  );
}

// ═══════════════════════════════════════════════ marcas e indicaciones
class _Marca {
  final Rect rect;
  final int numero;
  const _Marca(this.rect, this.numero);
}

final _marcas = ValueNotifier<List<_Marca>>(const []);
final _marco = GlobalKey();

class _PintorMarcas extends CustomPainter {
  final List<_Marca> marcas;
  _PintorMarcas(this.marcas);

  @override
  void paint(Canvas canvas, Size size) {
    const rojo = Color(0xFFE00000);
    final borde = Paint()
      ..color = rojo
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    final halo = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8;
    for (final m in marcas) {
      final r = RRect.fromRectAndRadius(m.rect, const Radius.circular(10));
      canvas.drawRRect(r, halo);
      canvas.drawRRect(r, borde);
    }
    const radio = 17.0;
    final puestos = <Offset>[];
    for (final m in marcas) {
      // El círculo va en la esquina superior izquierda, por fuera del
      // recuadro. Si choca con otro número se prueba a la izquierda, a
      // la derecha o debajo del recuadro.
      Offset ajustar(Offset c) => Offset(
          c.dx.clamp(radio + 2, size.width - radio - 2),
          c.dy.clamp(radio + 2, size.height - radio - 2));
      final r = m.rect;
      final opciones = [
        r.topLeft + const Offset(-radio + 4, -radio + 4),
        Offset(r.left - radio - 6, r.center.dy),
        Offset(r.right + radio + 6, r.center.dy),
        r.bottomLeft + const Offset(-radio + 4, radio - 4),
        r.topRight + const Offset(radio - 4, -radio + 4),
      ].map(ajustar).toList();
      final c = opciones.firstWhere(
          (o) => puestos.every((q) => (q - o).distance > radio * 2 + 6),
          orElse: () => opciones.first);
      puestos.add(c);
      canvas.drawCircle(c, radio + 3, Paint()..color = Colors.white);
      canvas.drawCircle(c, radio, Paint()..color = rojo);
      final tp = TextPainter(
        text: TextSpan(
            text: '${m.numero}',
            style: const TextStyle(
                fontFamily: 'Roboto', color: Colors.white,
                fontSize: 20, fontWeight: FontWeight.bold)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_PintorMarcas old) => old.marcas != marcas;
}

Widget _app(Widget inicio) => RepaintBoundary(
      key: _marco,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(children: [
          Positioned.fill(
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: _tema(),
              builder: (context, hijo) => DefaultTextStyle.merge(
                  style: const TextStyle(fontFamily: 'Roboto'), child: hijo!),
              home: inicio,
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: ValueListenableBuilder<List<_Marca>>(
                valueListenable: _marcas,
                builder: (_, m, __) =>
                    CustomPaint(painter: _PintorMarcas(m)),
              ),
            ),
          ),
        ]),
      ),
    );

// ═════════════════════════════════════════════════════════ utilidades
final _indice = <Map<String, dynamic>>[];
final _problemas = <String>[];
final _detalleProblemas = StringBuffer();
var _numCaptura = 0;

Future<void> _esperar(WidgetTester t, [int n = 30]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// Un punto a señalar: el widget y la frase para el dueño.
typedef _Punto = (Finder, String);

Future<void> _capturar(WidgetTester t, String nombre, String titulo,
    List<_Punto> puntos) async {
  await _esperar(t, 10);
  final marcas = <_Marca>[];
  final textos = <String>[];
  for (final (finder, frase) in puntos) {
    expect(finder, findsWidgets, reason: '$nombre: no se encontró $finder');
    final r = t.getRect(finder.first).inflate(5);
    marcas.add(_Marca(r, marcas.length + 1));
    textos.add('${marcas.length}: $frase');
  }
  _marcas.value = marcas;
  await t.pump();
  final limite =
      _marco.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final bytes = await t.runAsync(() async {
    final imagen = await limite.toImage(pixelRatio: _escala);
    final datos = await imagen.toByteData(format: ui.ImageByteFormat.png);
    return datos!.buffer.asUint8List();
  });
  _marcas.value = const [];
  await t.pump();
  _numCaptura++;
  final archivo =
      '${_numCaptura.toString().padLeft(2, '0')}_$nombre.png';
  File('build/capturas_guia/$archivo')
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes!);
  _indice.add({'archivo': archivo, 'titulo': titulo, 'indicaciones': textos});
  // ignore: avoid_print
  print('  build/capturas_guia/$archivo');
}

/// Corre [cuerpo] con el servidor simulado y junta las excepciones de
/// dibujo (desbordes, aserciones) en vez de cortar la prueba, para que
/// se generen todas las capturas y el informe diga dónde falló cada una.
Future<void> _seccion(WidgetTester t, String pantalla,
    Future<void> Function() cuerpo) async {
  final antes = _problemas.length;
  final original = FlutterError.onError;
  // flutter_test dibuja las sombras como bordes negros gruesos.
  final sombras = debugDisableShadows;
  debugDisableShadows = false;
  FlutterError.onError = (d) {
    final lineas = d.exceptionAsString().trim().split('\n');
    _problemas.add('[$pantalla] ${lineas.take(2).join(' ')}');
    _detalleProblemas
      ..writeln('════ $pantalla')
      ..writeln(d.toString())
      ..writeln();
  };
  try {
    await http.runWithClient(() async {
      await cuerpo();
      // Desmontar y dejar correr los temporizadores (guardados con
      // retardo, sincronizaciones) antes de pasar a la siguiente.
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 30));
    }, _servidor);
  } finally {
    FlutterError.onError = original;
    debugDisableShadows = sombras;
  }
  final nuevos = _problemas.length - antes;
  // ignore: avoid_print
  print('[$pantalla] ${nuevos == 0 ? 'sin problemas' : '$nuevos problema(s)'}');
}

/// Botón (Elevated/Outlined/Text/Filled, con o sin ícono) por su texto.
Finder _boton(String texto) => find.ancestor(
    of: find.text(texto),
    matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)).first;

/// La caja visible del diálogo abierto (no la pantalla entera).
Finder _dialogo() => find.descendant(
    of: find.byType(Dialog), matching: find.byType(Material)).first;

/// La pastilla del resumen que contiene [texto].
Finder _chip(String texto) => find.ancestor(
    of: find.textContaining(texto), matching: find.byType(Container)).first;

/// Desplaza la lista para que [f] quede arriba (0.0) o abajo (1.0).
Future<void> _alinear(WidgetTester t, Finder f, double alineacion) async {
  Scrollable.ensureVisible(t.element(f.first), alignment: alineacion);
  await _esperar(t, 5);
}

Future<void> _tocar(WidgetTester t, Finder f) async {
  await t.ensureVisible(f.first);
  await t.pump();
  await t.tap(f.first);
  await _esperar(t, 10);
}

void _vista(WidgetTester t) {
  t.view.physicalSize = const Size(_ancho * _escala, _alto * _escala);
  t.view.devicePixelRatio = _escala;
}

// ═════════════════════════════════════════════════════════════ pruebas
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _cargarFuentes();
    SharedPreferences.setMockInitialValues({});
    final dir = Directory('build/capturas_guia');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);
    _jpgBase64 = base64Encode(img.encodeJpg(
        img.Image(width: 60, height: 80)..clear(img.ColorRgb8(230, 230, 240))));
    _generarDatos();
    ConfigSistema.tiendas = List.of(_tiendas);
    ConfigSistema.tasaCambio = _tasa;
    ConfigSistema.nombreEmpresa = 'Tecno Líder';
    catalogoGlobal =
        _productos.map((m) => Producto.fromMap(Map.of(m))).toList();
    final listas = _listas();
    _listasJson = [for (final l in listas) {...l.toMap(), 'id': l.id}];
    listasPreciosGlobal = listas;
    usuariosSistema = _usuarios.map((m) => Usuario.fromMap(m)).toList();
    usuarioSesion = usuariosSistema.first;
  });

  tearDownAll(() {
    File('build/capturas_guia/indice.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(_indice));
    final p = File('build/capturas_guia/problemas.txt');
    if (_problemas.isEmpty) {
      p.writeAsStringSync('Sin problemas de dibujo.\n');
    } else {
      p.writeAsStringSync('${_problemas.join('\n')}\n\n$_detalleProblemas');
    }
    // ignore: avoid_print
    print('\nPeticiones al servidor simulado: ${_peticiones.toList()..sort()}');
    // ignore: avoid_print
    print('Problemas (${_problemas.length}):\n${_problemas.join('\n')}');
  });

  // ── 1. Reporte de ventas con auditoría ──────────────────────────
  testWidgets('1. Reporte de ventas y auditoría', (t) async {
    _vista(t);
    addTearDown(t.view.reset);
    await _seccion(t, 'Reporte de ventas', () async {
      HistorialReportes.entradas.clear();
      await t.runAsync(() => generarReporteVentas(
          desde: DateTime(_hoy.year, _hoy.month, 1), hasta: _hoy));
      final e = HistorialReportes.entradas
          .firstWhere((x) => x.tipoReporte == 'ventas');
      expect(e.detalles.length, _facturas.length);
      expect(e.resumen['unidades_financiadas'], greaterThan(0));
      expect(e.resumen['unidades_de_contado'], greaterThan(0));

      await t.pumpWidget(_app(VisorReporteScreen(entrada: e)));
      await _esperar(t);
      await _capturar(t, 'reporte_ventas', 'Reporte de ventas: filtros de auditoría y resumen', [
        (_chip('Unidades de contado'),
            'Cuántos equipos se vendieron de contado'),
        (_chip('Unidades financiadas'),
            'Cuántos equipos se vendieron financiados'),
        (_chip('Krece:'), 'Financiados por cada financiadora (Krece, Cashea...)'),
        (find.textContaining('Pendientes de auditar'),
            'Muestra solo las facturas que faltan por auditar'),
        (find.text('Con diferencia (auto)'),
            'Muestra las facturas donde lo cobrado no cuadra con la lista de precios'),
        (find.text('Marcadas "no listo"'),
            'Muestra las facturas que marcaste con problema'),
      ]);

      // Filtro "Con diferencia": sólo queda la factura con la inicial corta.
      await _tocar(t, find.text('Con diferencia (auto)'));
      expect(find.textContaining('Fact. F-'), findsWidgets);
      expect(find.text('Fact. F-1001'), findsNothing);
      await _tocar(t, find.widgetWithText(ChoiceChip, 'Todas'));

      // Abrir la factura financiada por Krece (concuerda).
      await _tocar(t, find.text('Fact. F-1003'));
      final panel = find.ancestor(
          of: find.text('AUDITORÍA'), matching: find.byType(Container)).first;
      await _alinear(t, panel, 1.0);
      final listoPago = find.descendant(
          of: panel, matching: find.widgetWithText(OutlinedButton, 'Listo'));
      await _capturar(t, 'factura_auditoria', 'Detalle de una factura con el panel de AUDITORÍA', [
        (find.descendant(of: panel, matching: find.byType(ChipAuditoriaAuto)),
            'Revisión automática: "Concuerda" (verde) o "Diferencia de \$X" (rojo)'),
        (listoPago.at(0),
            'Toca "Listo" cuando confirmes que el pago llegó (Pago recibido)'),
        (listoPago.at(1),
            'Toca "Listo" cuando la factura esté bien (Auditoría correcta)'),
        (find.descendant(of: panel,
                matching: find.widgetWithText(OutlinedButton, 'No listo')).first,
            '"No listo" marca la factura con problema para revisarla luego'),
      ]);
      expect(find.descendant(of: panel, matching: find.text('Auto: Concuerda')),
          findsOneWidget);

      // Marcar "Pago recibido" → queda "Listo · Administrador · fecha"
      // y se guarda en el servidor (configuracion aud_fac_F-1003).
      await _tocar(t, listoPago.at(0));
      expect(find.textContaining('Listo · Administrador'), findsOneWidget);
      expect(find.text('Pago: listo'), findsOneWidget);
      expect(_config.keys, contains(claveAuditoriaFactura('F-1003')));
      await _tocar(t, listoPago.at(1));
      expect(find.text('Auditoría: listo'), findsOneWidget);
      await _alinear(t, panel, 1.0);
      await _capturar(t, 'factura_auditada', 'Factura ya auditada: queda quién y cuándo', [
        (find.textContaining('Listo · Administrador').at(0),
            'Pago recibido: queda guardado quién lo marcó y a qué hora'),
        (find.textContaining('Listo · Administrador').at(1),
            'Auditoría correcta: igual, con nombre y hora'),
      ]);

      // Cerrar la factura: en la lista se ve su estado sin abrirla.
      await _alinear(t, find.text('Fact. F-1003'), 0.0);
      await _tocar(t, find.text('Fact. F-1003'));
      await t.scrollUntilVisible(find.text('Fact. F-1001'), -300,
          scrollable: find.byType(Scrollable).last);
      await _alinear(t, find.text('Fact. F-1001'), 0.0);
      await _capturar(t, 'factura_estado_lista', 'Estado de auditoría visible en la lista', [
        (find.text('Pago: listo'), 'Pago recibido: listo'),
        (find.text('Auditoría: listo'), 'Auditoría correcta: lista'),
        (find.text('Pago: pendiente').first, 'Las que faltan dicen "pendiente"'),
      ]);

      // La factura con diferencia muestra el monto.
      await _tocar(t, find.text('Fact. F-1004'));
      final panel2 = find.ancestor(
          of: find.text('AUDITORÍA'), matching: find.byType(Container)).first;
      await _alinear(t, panel2, 1.0);
      await _capturar(t, 'factura_diferencia', 'Factura con diferencia detectada automáticamente', [
        (find.descendant(of: panel2, matching: find.byType(ChipAuditoriaAuto)),
            'Diferencia: la inicial cobrada no coincide con la lista de la financiadora'),
        (find.textContaining('esperada'),
            'Explica qué se cobró y qué se esperaba'),
      ]);
    });
  });

  // ── 3. Lista de precios ─────────────────────────────────────────
  testWidgets('3. Lista de precios: mover columnas y cuotas', (t) async {
    _vista(t);
    addTearDown(t.view.reset);
    await _seccion(t, 'Lista de precios', () async {
      final krece = ListaPrecio.fromMap(Map<String, dynamic>.from(
          _listasJson.firstWhere((l) => l['nombre'] == 'Krece')));
      krece.id = 13;
      await t.pumpWidget(_app(DetalleListaPrecio(lista: krece)));
      await _esperar(t);
      final cuotasTel4 = find.byTooltip('N° de cuotas de este modelo');
      await _capturar(t, 'lista_precios', 'Lista de precios de Krece', [
        (find.text('NIVEL 2').first,
            'Toca el título de una columna para ver sus opciones'),
        (cuotasTel4.first,
            'Número de cuotas propio de este modelo (si no, usa el de la lista)'),
      ]);

      await _tocar(t, find.text('NIVEL 2').first);
      await _capturar(t, 'lista_menu_columna', 'Menú de la columna: mover a la izquierda o a la derecha', [
        (find.text('Mover a la izquierda'), 'Pasa la columna un lugar a la izquierda'),
        (find.text('Mover a la derecha'), 'Pasa la columna un lugar a la derecha'),
      ]);
      await _tocar(t, find.text('Mover a la derecha'));
      expect(krece.columnas.map((c) => c.nombre).toList(),
          ['Krece', 'Nivel 3', 'Nivel 2']);

      // Cuotas de un modelo.
      await _tocar(t, cuotasTel4.first);
      await _capturar(t, 'lista_cuotas_modelo', 'Cuotas de un modelo en particular', [
        (_dialogo(), 'Escribe cuántas cuotas tiene este modelo (vacío = las de la lista)'),
      ]);
    });
  });

  // ── 4. Inventario ───────────────────────────────────────────────
  testWidgets('4. Inventario: exportar e ingreso rápido', (t) async {
    _vista(t);
    addTearDown(t.view.reset);
    await _seccion(t, 'Inventario', () async {
      await t.pumpWidget(_app(const VentanaInventario()));
      await _esperar(t);
      await _tocar(t, find.byTooltip('Exportar inventario'));
      await _capturar(t, 'inventario_exportar', 'Exportar inventario con filtros', [
        (find.widgetWithText(DropdownButtonFormField<String>, 'Tienda'),
            'Elige la tienda (o todas)'),
        (find.widgetWithText(DropdownButtonFormField<String>, 'Categoría'),
            'Filtra por categoría: teléfonos, accesorios...'),
        (find.widgetWithText(DropdownButtonFormField<String>, 'Marca'),
            'Filtra por marca'),
        (find.byType(SegmentedButton<String>), 'Elige Excel o PDF'),
        (_boton('Descargar'), 'Descarga el archivo'),
      ]);
      // Elegir la categoría "Accesorio" → la marca ofrece sólo las de
      // accesorios.
      await _tocar(t, find.widgetWithText(DropdownButtonFormField<String>, 'Categoría'));
      await _tocar(t, find.text('Accesorio').last);
      await _tocar(t, find.widgetWithText(DropdownButtonFormField<String>, 'Marca'));
      expect(find.text('Samsung'), findsNothing);
      expect(find.text('Genérico'), findsWidgets);
      await t.tapAt(const Offset(5, 5));
      await _esperar(t, 5);
      await _tocar(t, find.text('Cancelar'));

      await _tocar(t, find.byTooltip('Ingreso rápido de stock'));
      await _esperar(t);
      await _tocar(t, find.byTooltip('Cargar mercancía en otra tienda...'));
      await _capturar(t, 'ingreso_rapido_tienda', 'Ingreso rápido de stock: elegir la tienda', [
        (find.text(_geo).last, 'Elige a qué tienda entra la mercancía'),
      ]);
      await _tocar(t, find.text(_geo).last);
      expect(find.text('Ingreso de stock · $_geo'), findsOneWidget);
      await t.enterText(find.widgetWithText(TextField, 'Código o nombre'), 'ACC-003');
      await _esperar(t, 5);
      await _capturar(t, 'ingreso_rapido', 'Ingreso rápido de stock en Geo Cell', [
        (find.text('Ingreso de stock · $_geo'), 'Tienda donde entra la carga'),
        (find.byTooltip('Cargar mercancía en otra tienda...'), 'Cambiar de tienda'),
        (find.widgetWithText(TextField, 'Código o nombre'),
            'Escanea o escribe el código del producto'),
        (_boton('Agregar'), 'Agrega la cantidad a la carga'),
      ]);
      await _tocar(t, _boton('Agregar'));
      expect(find.text('Todavía no cargaste nada'), findsNothing);
    });
  });

  // ── 5. Panel Administrativo ─────────────────────────────────────
  testWidgets('5. Panel administrativo', (t) async {
    _vista(t);
    addTearDown(t.view.reset);
    await _seccion(t, 'Panel administrativo', () async {
      await t.pumpWidget(_app(const VentanaPanelAdmin()));
      await _esperar(t);
      final tarjeta = find.ancestor(
          of: find.textContaining('Divisas: \$'), matching: find.byType(Card)).first;
      expect(find.textContaining('Divisas: \$'), findsOneWidget);
      expect(find.textContaining('Bolívares: Bs'), findsOneWidget);
      await _capturar(t, 'panel_ventas_mes', 'Panel administrativo: ventas del mes en \$ y en Bs', [
        (tarjeta, 'Ventas del mes: lo cobrado en divisas y en bolívares por separado'),
      ]);
    });
  });

  // ── 6. Costos y Finanzas ────────────────────────────────────────
  testWidgets('6. Costos y finanzas', (t) async {
    _vista(t);
    addTearDown(t.view.reset);
    await _seccion(t, 'Costos y finanzas', () async {
      await t.pumpWidget(_app(const VentanaCostosFinanzas()));
      await _esperar(t, 40);
      Future<void> pestana(String nombre, String archivo, String titulo,
          List<_Punto> Function() extra) async {
        await _tocar(t, find.widgetWithText(Tab, nombre));
        await _esperar(t, 15);
        await _capturar(t, archivo, titulo, [
          (find.widgetWithText(Tab, nombre), 'Pestaña "$nombre"'),
          ...extra(),
        ]);
      }

      await pestana('Equilibrio', 'costos_equilibrio',
          'Costos: punto de equilibrio por tienda', () => [
            (find.textContaining('Desde ').first, 'Cambia el rango de fechas'),
            (find.textContaining('Quedamos en').first,
                'Ganancia menos gastos: en cuánto quedó cada tienda'),
            (find.textContaining('En positivo').first,
                'Día en que la tienda cubrió sus gastos'),
          ]);
      await pestana('Ganancia real', 'costos_ganancia_real',
          'Costos: ganancia real', () => [
            (find.textContaining('Ganancia real (contado').first,
                'Ganancia como si todo se hubiese vendido de contado'),
            (find.text('Diferencial cambiario').first,
                'Lo que se gana (o pierde) por financiamiento y tasa'),
            (find.text('Diferencial por financiadora'),
                'El detalle por Krece, Cashea y de contado'),
          ]);
      await pestana('Flujo Caja', 'costos_flujo_caja',
          'Costos: flujo de caja por tienda y moneda', () => [
            (find.text('Entró en \$'), 'Dólares que entraron'),
            (find.text('Entró en Bs'), 'Bolívares que entraron (nunca se suman con los \$)'),
            (find.text('Por tienda'), 'Entradas y salidas de cada tienda'),
          ]);
      await pestana('Nómina', 'costos_nomina', 'Costos: nómina', () => [
            (_boton('Agregar empleado'),
                'Agrega a la persona que cobra sueldo'),
            (_boton('Registrar pago'),
                'Registra lo que le pagaste y cuándo'),
          ]);
      // Registrar pago de nómina abre su formulario.
      await _tocar(t, _boton('Registrar pago'));
      await _capturar(t, 'costos_nomina_pago', 'Registrar un pago de nómina', [
        (_dialogo(), 'Elige a quién le pagas, el monto y la fecha'),
      ]);
      // Guardar el pago: queda en el historial del mes (servidor).
      final clavePagos = claveNominaPagosMes(_hoy.year, _hoy.month);
      final antes = (jsonDecode(_config[clavePagos] as String) as List).length;
      await _tocar(t, find.ancestor(
          of: find.descendant(of: find.byType(Dialog),
              matching: find.text('Registrar pago')),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)));
      await _esperar(t, 10);
      expect((jsonDecode(_config[clavePagos] as String) as List).length,
          antes + 1);
      await pestana('Gastos', 'costos_gastos', 'Costos: gastos del mes', () => [
            (_boton('Registrar gasto'),
                'Anota un gasto (alquiler, servicios...)'),
          ]);
    });
  });

  // ── 7. Cuentas por pagar a proveedores ──────────────────────────
  testWidgets('7. Cuentas por pagar proveedores', (t) async {
    _vista(t);
    addTearDown(t.view.reset);
    await _seccion(t, 'Cuentas por pagar', () async {
      await t.pumpWidget(_app(const VentanaCuentasPorPagarProveedor()));
      await _esperar(t);
      await _capturar(t, 'cxp_perfiles', 'Cuentas por pagar: un perfil por proveedor', [
        (find.ancestor(of: find.text('DEUDA TOTAL'),
                matching: find.byType(Container)).first,
            'Lo que debes en total a todos los proveedores'),
        (find.ancestor(of: find.text('SALDO A FAVOR'),
                matching: find.byType(Container)).first,
            'Lo que tienes a favor (pagaste de más)'),
        (find.ancestor(of: find.text('Distribuidora Maxi 2005'),
                matching: find.byType(InkWell)).first,
            'Toca un proveedor para ver su perfil con todas sus facturas y pagos'),
        (find.text('A favor \$150.00'), 'Proveedor al que le pagaste de más'),
      ]);
      await _tocar(t, find.text('Distribuidora Maxi 2005'));
      await _esperar(t);
      await _capturar(t, 'cxp_perfil', 'Perfil del proveedor con su historial', [
        (find.text('SALDO PENDIENTE'), 'Lo que le debes a este proveedor'),
        (find.byTooltip('Ver adjunto').first, 'Ver la foto o PDF ya adjuntado'),
        (find.byTooltip('Adjuntar foto o PDF').first,
            'Adjunta la foto o PDF de esa factura o pago'),
        (find.byTooltip('Agregar factura'), 'Agrega una factura nueva del proveedor'),
        (find.byType(FloatingActionButton), 'Registra un pago al proveedor'),
      ]);
    });
  });

  // ── 8. Billetera semanal de comisiones ──────────────────────────
  testWidgets('8. Billetera de comisiones', (t) async {
    _vista(t);
    addTearDown(t.view.reset);
    await _seccion(t, 'Billetera de comisiones', () async {
      await t.pumpWidget(_app(VentanaBilleteraComisiones(
          usuario: usuariosSistema.firstWhere((u) => u.nombre == 'Laura Ríos'))));
      await _esperar(t);
      expect(find.text('Aún no hay comisiones en este período.'), findsNothing);
      await _capturar(t, 'billetera', 'Billetera semanal de comisiones', [
        (find.byIcon(Icons.chevron_left).first, 'Semana anterior / siguiente'),
        (find.textContaining('Comisiones de la semana'),
            'Lo que lleva ganado en comisiones esta semana (lunes a domingo)'),
        (find.text('Detalle de comisiones'), 'Cada venta que le dio comisión'),
        (find.text('Rango'), 'Ver las comisiones entre dos fechas'),
      ]);
    });
  });

  // ── 9. Pago por lote de la financiadora ─────────────────────────
  testWidgets('9. Pago por lote de la financiadora', (t) async {
    _vista(t);
    addTearDown(t.view.reset);
    await _seccion(t, 'Pago por lote', () async {
      await t.pumpWidget(_app(const VentanaReporteFinanciadora()));
      await _esperar(t);
      final boton = _boton('Pago por lote');
      await _capturar(t, 'financiadora_reporte', 'Reporte por financiadora', [
        (boton.first, 'Registra de una vez el pago de todo el lote'),
      ]);
      await _tocar(t, boton.first);
      await _capturar(t, 'pago_lote', 'Pago por lote: equipos y monto', [
        (find.text('Usar este monto'), 'Copia el total de los equipos marcados'),
        (find.widgetWithText(TextField, 'Monto pagado por la financiadora (USD) *'),
            'O escribe el monto que pagó la financiadora'),
        (find.textContaining('Registrar ('), 'Guarda el pago repartido entre los equipos'),
        (find.byType(Checkbox).at(1), 'Desmarca los equipos que no entran en este pago'),
      ]);
      final antes = _pagosFinanciadora.length;
      await _tocar(t, find.text('Usar este monto'));
      await _tocar(t, find.textContaining('Registrar ('));
      await _esperar(t, 20);
      expect(_pagosFinanciadora.length, greaterThan(antes));
    });
  });

  // ── 10 y 11. Servicio técnico y calculadora ─────────────────────
  testWidgets('10-11. Calculadora y servicio técnico', (t) async {
    _vista(t);
    addTearDown(t.view.reset);
    await _seccion(t, 'Servicio técnico', () async {
      await t.pumpWidget(_app(const VentanaServicioTecnico()));
      await _esperar(t);
      // Calculadora
      await _tocar(t, find.byTooltip('Calculadora').first);
      for (final k in ['2', '0', '0', '+', '1', '0', '%']) {
        await _tocar(t, find.descendant(
            of: find.byType(Dialog), matching: find.text(k)).last);
      }
      expect(find.textContaining('220'), findsWidgets);
      await _capturar(t, 'calculadora', 'Calculadora rápida', [
        (find.byTooltip('Calculadora').first, 'Abre la calculadora desde la barra de arriba'),
        (_dialogo(), '200 + 10 % = 220; abajo lo pasa a Bs o a \$ con la tasa'),
      ]);
      await t.tapAt(const Offset(5, 1000));
      await _esperar(t, 5);

      // Registrar cobro
      await _tocar(t, find.text('Andrés Suárez').first);
      await _esperar(t);
      final registrar = _boton('Registrar cobro');
      await _capturar(t, 'servicio_detalle', 'Servicio técnico: cobros de la orden', [
        (registrar, 'Registra lo que pagó el cliente'),
      ]);
      await _tocar(t, registrar);
      await _capturar(t, 'servicio_cobro', 'Registrar cobro de servicio técnico', [
        (find.ancestor(of: find.text('Método de pago'),
                matching: find.byType(InputDecorator)).first,
            'Método: efectivo, pago móvil (pide referencia y cédula), Zelle...'),
        (find.ancestor(of: find.text('Monto en \$'),
                matching: find.byType(TextField)).first,
            'Monto cobrado (si es en Bs, se convierte con la tasa)'),
        (find.text('Cobrar\nresta'),'Pone de una vez todo lo que falta'),
        (_boton('Registrar'), 'Guarda el cobro'),
      ]);
      await t.enterText(
          find.descendant(of: find.byType(AlertDialog),
              matching: find.byType(TextField)).first, '10');
      await _esperar(t, 3);
      final guardar = find.descendant(of: find.byType(AlertDialog),
          matching: find.byType(ElevatedButton));
      await _tocar(t, guardar.last);
      await _esperar(t, 10);
      // El PUT llegó al servidor con el abono de $10.
      final guardado = ServicioTecnico.fromMap(
          Map<String, dynamic>.from(_servicios.firstWhere((s) => s['id'] == 3)));
      expect(guardado.abono, closeTo(10, 0.01));
      expect(guardado.pagos.length, 1);

      await t.pageBack();
      await _esperar(t);
      await _tocar(t, find.byTooltip('Ingresos de servicio técnico'));
      await _capturar(t, 'servicio_ingresos', 'Reporte de ingresos de servicio técnico', [
        (find.ancestor(of: find.textContaining(' – '),
                matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)).first,
            'Elige las fechas'),
        (find.text('Todas las tiendas'), 'Filtra por tienda'),
        (find.text('Ingresos cobrados'), 'Total cobrado por servicio técnico (aparte de las ventas)'),
        (find.text('Por método de pago'), 'Cuánto entró por cada método, en \$ y en Bs'),
        (find.text('Detalle de cobros'), 'Cada cobro con fecha, quién cobró y referencia'),
      ]);
    });
  });
}
