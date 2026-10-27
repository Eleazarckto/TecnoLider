// Capturas de las mejoras del 19/10/2026 (listas en Bs desde la lista en
// divisas y reporte de IMEIs por tienda, marca y modelo) para su PDF de
// notas. NO es parte de la batería de pruebas (vive fuera de test/). Los
// datos, el servidor simulado y las utilidades son los de
// capturas_1_0_18_test.dart.
//
//   flutter test tool/capturas/capturas_bs_imei_test.dart
//
// Deja los PNG en tool/capturas/salida_bs_imei/ (escala 2). Dibuja las pantallas de
// la app contra un servidor SIMULADO (MockClient) con datos de ejemplo de
// una tienda de celulares: ningún dato real de clientes y nunca toca la API
// de producción. Mismo método que tool/capturas_guia_test.dart (fuentes,
// tema y servidor) y que tool/capturas/ de Brizuela.
//
// Además de dibujar, comprueba lo que la captura tiene que mostrar (que el
// vendedor no vea los botones, que el cuadre diga lo que debe, etc.) y deja
// en salida/problemas.txt los desbordes o excepciones de dibujo, si hubo.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide Card; // Card: la de theme/neu.dart
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tecno_lider/actualizador.dart';
import 'package:tecno_lider/ficha_tecnica.dart';
import 'package:tecno_lider/main.dart';
import 'package:tecno_lider/reglas_porcentaje.dart';

const _salida = 'tool/capturas/salida_bs_imei';

// ═══════════════════════════════════════════════════════ datos de ejemplo
const _tasa = 203.74;
const _principal = 'Tecno Líder Principal', _geo = 'Geo Cell';
const _tiendas = [_principal, _geo];

final _hoy = DateTime.now();
String _f(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
DateTime _dia(int n) => DateTime(_hoy.year, _hoy.month, n.clamp(1, _hoy.day));

var _idProducto = 100;
Map<String, dynamic> _p(String c, String n, String cat, String marca,
        String modelo, double costo, double venta,
        {int stock = 0, String tienda = _principal}) =>
    {
      'id': _idProducto++,
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
  _p('TEL-007', 'Xiaomi Redmi Note 14 8/256', 'Telefono', 'Xiaomi', 'Redmi Note 14', 170, 229),
  _p('ACC-001', 'Cargador rápido 33W USB-C', 'Accesorio', 'Genérico', 'N/A', 4, 9, stock: 40),
  _p('ACC-002', 'Audífonos Bluetooth Buds 6', 'Accesorio', 'Xiaomi', 'Buds 6', 6, 14, stock: 25),
  _p('ACC-003', 'Forro antigolpe Galaxy A16', 'Accesorio', 'Genérico', 'N/A', 1.5, 5, stock: 80),
  _p('ACC-004', 'Vidrio templado 9D Redmi 14C', 'Accesorio', 'Genérico', 'N/A', 0.8, 3, stock: 120),
  _p('ACC-005', 'Vidrio templado privacidad iPhone 13', 'Accesorio', 'Genérico', 'N/A', 1.2, 4, stock: 60),
  _p('ACC-006', 'Corneta JBL Go 3', 'Accesorio', 'JBL', 'Go 3', 13.15, 27, stock: 8),
  _p('ACC-007', 'Corneta Xiaomi Sound Pocket', 'Accesorio', 'Xiaomi', 'Sound Pocket', 9.5, 19, stock: 6),
  _p('ACC-008', 'Parlante Bluetooth K-Party 8"', 'Accesorio', 'Genérico', 'K-Party', 22, 45, stock: 3),
];

double _venta(String c) =>
    (_productos.firstWhere((p) => p['codigo'] == c)['precio_venta'] as num)
        .toDouble();

const _precioKrece = {
  'TEL-001': 165.0, 'TEL-002': 215.0, 'TEL-003': 225.0, 'TEL-004': 305.0,
  'TEL-005': 160.0, 'TEL-006': 199.0, 'TEL-007': 289.0,
};
const _precioCashea = {
  'TEL-001': 155.0, 'TEL-002': 205.0, 'TEL-003': 215.0, 'TEL-004': 289.0,
  'TEL-005': 150.0, 'TEL-006': 189.0, 'TEL-007': 275.0,
};
double _bcv(String c) => (_venta(c) * 1.18).roundToDouble();

/// El equipo que se vende por Krece en la factura de ejemplo.
const _imeiA16 = '356789104512347';

final _imeis = <Map<String, dynamic>>[];
final _facturas = <Map<String, dynamic>>[];
final _config = <String, dynamic>{};
final _peticiones = <String>{};
var _sigId = 5000;

const _clientes = [
  'María González', 'José Pérez', 'Ana Rodríguez', 'Carlos Méndez',
  'Luisa Fernández', 'Pedro Castillo', 'Rosa Martínez', 'Andrés Suárez',
  'Yelitza Mora', 'Freddy Rangel',
];
const _vendedores = ['Laura Ríos', 'Miguel Torres', 'Daniela Salas'];

final _usuarios = <Map<String, dynamic>>[
  {'id': 1, 'nombre': 'Carolina Peña', 'cedula': 'V-14222333',
   'correo': 'administracion@ejemplo.com', 'clave': '', 'rol': 'Administrador',
   'sueldo_base': 0, 'tienda': '', 'gana_comisiones': 0},
  {'id': 2, 'nombre': 'Laura Ríos', 'cedula': 'V-20111222',
   'correo': 'laura@ejemplo.com', 'clave': '', 'rol': 'Vendedor',
   'sueldo_base': 60, 'tienda': _principal, 'gana_comisiones': 1},
  {'id': 3, 'nombre': 'Miguel Torres', 'cedula': 'V-21333444',
   'correo': 'miguel@ejemplo.com', 'clave': '', 'rol': 'Vendedor',
   'sueldo_base': 60, 'tienda': _geo, 'gana_comisiones': 1},
  {'id': 4, 'nombre': 'Daniela Salas', 'cedula': 'V-22555666',
   'correo': 'daniela@ejemplo.com', 'clave': '', 'rol': 'Encargado',
   'sueldo_base': 80, 'tienda': _principal, 'gana_comisiones': 1},
];

var _serie = 356938104520113;
String _nuevoImei(String codigo, String tienda,
    {required bool vendido, String? imei}) {
  final i = imei ?? '${_serie++}';
  final p = _productos.firstWhere((x) => x['codigo'] == codigo);
  _imeis.add({
    'imei': i, 'producto_codigo': codigo,
    'fecha_ingreso': _f(DateTime(_hoy.year, _hoy.month, 1)),
    'proveedor': 'Distribuidora Maxi 2005', 'color': 'Negro',
    'ubicacion': tienda, 'porcentaje_bateria': null,
    'vendido': vendido ? 1 : 0,
    'producto_nombre': p['nombre'], 'categoria': p['categoria'],
    'marca': p['marca'], 'modelo': p['modelo'], 'tipo': '',
    'precio_costo': p['precio_costo'], 'precio_venta': p['precio_venta'],
  });
  return i;
}

var _nro = 1001;
void _factura({
  required String tienda,
  required int dia,
  List<String> equipos = const [],
  List<String> items = const [],
  required List<Map<String, dynamic>> pagos,
}) {
  final n = _nro++;
  final v = _vendedores[n % _vendedores.length];
  _facturas.add({
    'id': n, 'nro_factura': 'F-$n',
    'cliente': _clientes[n % _clientes.length],
    'cedula': 'V-${12000000 + n * 7919}',
    'telefono': '0414-55${n % 10}12${n % 7}3',
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
Map<String, dynamic> _inicial(String fin, double m) => {
      'metodo': 'Efectivo \$', 'monto': m, 'tipo': 'Financiado',
      'financiadora': fin, 'financiador': '', 'es_inicial': 1,
      'tasa_cambio': _tasa, 'nombre_lista': fin,
    };

void _generarDatos() {
  _factura(tienda: _principal, dia: 1, equipos: ['TEL-003'],
      pagos: [_usd(_venta('TEL-003'))]);
  _factura(tienda: _geo, dia: 2, equipos: ['TEL-001'],
      pagos: [_bs(_bcv('TEL-001'))]);
  _factura(tienda: _principal, dia: 3, equipos: ['TEL-004'], items: ['ACC-003'],
      pagos: [_inicial('Krece', 122), _usd(_venta('ACC-003'))]);
  _factura(tienda: _principal, dia: 5, equipos: ['TEL-006'],
      pagos: [_inicial('Cashea', 75.6)]);
  _factura(tienda: _principal, dia: 6, items: ['ACC-001', 'ACC-004'],
      pagos: [_usd(12)]);
  _factura(tienda: _geo, dia: 7, equipos: ['TEL-005'],
      pagos: [_inicial('Krece', 64)]);
  _factura(tienda: _principal, dia: 8, equipos: ['TEL-001'],
      pagos: [_usd(_venta('TEL-001'), metodo: 'Zelle')]);
  _factura(tienda: _principal, dia: 10, equipos: ['TEL-005'],
      pagos: [_bs(_bcv('TEL-005'))]);
  _factura(tienda: _principal, dia: 11, items: ['ACC-006'],
      pagos: [_usd(27)]);
  _factura(tienda: _principal, dia: 12, equipos: ['TEL-007'],
      pagos: [_inicial('Krece', 115.6)]);
  _factura(tienda: _principal, dia: 14, equipos: ['TEL-002'], items: ['ACC-002'],
      pagos: [_usd(_venta('TEL-002') + _venta('ACC-002'), metodo: 'Efectivo \$')]);
  _factura(tienda: _principal, dia: 15, equipos: ['TEL-003'],
      pagos: [_bs(_bcv('TEL-003'))]);

  // Stock disponible de cada teléfono, en las dos tiendas.
  for (final c in _precioKrece.keys) {
    for (var i = 0; i < 4; i++) {
      _nuevoImei(c, i.isEven ? _principal : _geo, vendido: false);
    }
  }
  _nuevoImei('TEL-003', _principal, vendido: false, imei: _imeiA16);
}

// ── Listas de precios (con los modelos de la app) ──
const _idCosto = 15;

List<ListaPrecio> _listas() {
  ItemListaPrecio it(String c, Map<String, double> precios) => ItemListaPrecio(
      producto: catalogoGlobal.firstWhere((p) => p.codigo == c),
      preciosPorColumna: precios,
      stockDisponible: 4);
  final tels = _precioKrece.keys;
  final accesorios = [
    for (final p in _productos)
      if (p['categoria'] == 'Accesorio') p['codigo'] as String
  ];
  final costo = ListaPrecio(
    id: _idCosto, nombre: 'Accesorios Divisas', fechaCreacion: _f(_dia(1)),
    categoria: 'Accesorio',
    modoPrecios: 'costo', pctSobreCosto: 60, redondearArriba: true,
    reglasPct: [
      ReglaPorcentaje(nombre: 'Cornetas', palabras: ['corneta', 'parlante'], pct: 100),
      ReglaPorcentaje(nombre: 'Vidrios', palabras: ['vidrio', 'templado', 'mica'], pct: 120),
    ],
    columnas: [ColumnaPrecio(nombre: 'Divisa')],
  );
  costo.items.addAll([
    for (final c in accesorios)
      it(c, {
        'Divisa': costo.precioPorDefecto(
            catalogoGlobal.firstWhere((p) => p.codigo == c)),
      }),
  ]);
  return [
    ListaPrecio(id: 11, nombre: 'Divisa', fechaCreacion: _f(_dia(1)),
        categoria: 'Telefono',
        columnas: [ColumnaPrecio(nombre: 'Divisa')],
        items: [for (final c in tels) it(c, {'Divisa': _venta(c)})]),
    ListaPrecio(id: 12, nombre: 'BCV', fechaCreacion: _f(_dia(1)),
        categoria: 'Telefono',
        columnas: [ColumnaPrecio(nombre: 'BCV')],
        items: [for (final c in tels) it(c, {'BCV': _bcv(c)})]),
    ListaPrecio(id: 13, nombre: 'Krece', fechaCreacion: _f(_dia(1)),
        categoria: 'Telefono',
        esFinanciamiento: true, financiadora: 'Krece',
        porcentajeInicial: 40, numeroCuotas: 6,
        columnas: [ColumnaPrecio(nombre: 'Krece')],
        items: [for (final c in tels) it(c, {'Krece': _precioKrece[c]!})]),
    ListaPrecio(id: 14, nombre: 'Cashea', fechaCreacion: _f(_dia(1)),
        categoria: 'Telefono',
        esFinanciamiento: true, financiadora: 'Cashea',
        porcentajeInicial: 40, numeroCuotas: 3,
        columnas: [ColumnaPrecio(nombre: 'Cashea')],
        items: [for (final c in tels) it(c, {'Cashea': _precioCashea[c]!})]),
    costo,
    ListaPrecio(id: _idBs, nombre: 'Equipos Bs', fechaCreacion: _f(_dia(1)),
        categoria: 'Telefono',
        esEnBolivares: true, tasaDelDia: 190, porcentajeAdicional: 5,
        listaBaseId: 11,
        columnas: [ColumnaPrecio(nombre: 'Precio Bs')],
        // Precios viejos (venta × 5 % × una tasa de hace días).
        items: [for (final c in tels) it(c, {'Precio Bs': (_venta(c) * 1.05 * 190).roundToDouble()})]),
  ];
}

const _idBs = 16;

/// Las listas tal como las tiene el «servidor» (id → mapa).
final _listasServidor = <int, Map<String, dynamic>>{};

// ── Fichas técnicas ──
const _origenFichas = {'TEL-003': 'manual', 'TEL-004': 'auto', 'TEL-007': 'auto'};

Map<String, dynamic> _fichaA16() => {
      'codigo': 'TEL-003', 'nombre': 'Samsung Galaxy A16 4/128',
      'titulo': 'Teléfono / tablet', 'origen': 'manual',
      'por': 'Carolina Peña', 'actualizado': '2026-10-14 16:20:00',
      'campos': [
        {'grupo': 'Pantalla', 'campo': 'Tamaño', 'valor': '6,7 pulgadas'},
        {'grupo': 'Pantalla', 'campo': 'Tipo', 'valor': 'Super AMOLED, 90 Hz'},
        {'grupo': 'Pantalla', 'campo': 'Resolución', 'valor': '1080 × 2340 (FHD+)'},
        {'grupo': 'Rendimiento', 'campo': 'Procesador', 'valor': 'MediaTek Helio G99'},
        {'grupo': 'Rendimiento', 'campo': 'Memoria RAM', 'valor': '4 GB'},
        {'grupo': 'Rendimiento', 'campo': 'Almacenamiento', 'valor': '128 GB (microSD hasta 1,5 TB)'},
        {'grupo': 'Cámaras', 'campo': 'Principal', 'valor': '50 MP + 5 MP + 2 MP'},
        {'grupo': 'Cámaras', 'campo': 'Frontal', 'valor': '13 MP'},
        {'grupo': 'Batería', 'campo': 'Capacidad', 'valor': '5000 mAh'},
        {'grupo': 'Batería', 'campo': 'Carga', 'valor': '25 W'},
        {'grupo': 'Conectividad', 'campo': 'Red', 'valor': '4G LTE'},
        {'grupo': 'Conectividad', 'campo': 'SIM', 'valor': 'Dual SIM'},
        {'grupo': 'Conectividad', 'campo': 'NFC', 'valor': 'Sí'},
        {'grupo': 'General', 'campo': 'Sistema', 'valor': 'Android 14 (One UI 6)'},
        {'grupo': 'General', 'campo': 'Colores', 'valor': 'Negro, Gris, Verde claro'},
      ],
    };

/// Servidor simulado: responde por `resource` con los datos de arriba.
http.Client _servidor() => MockClient((req) async {
      final q = req.url.queryParameters;
      final r = q['resource'] ?? '';
      _peticiones.add('${req.method} $r${q['accion'] != null ? '&accion=${q['accion']}' : ''}');
      if (!req.url.path.endsWith('api.php')) {
        return http.Response('{}', 404);
      }
      Map<String, dynamic> enviado() {
        try {
          final b = jsonDecode(req.body);
          return b is Map ? Map<String, dynamic>.from(b) : {};
        } catch (_) {
          return {};
        }
      }

      dynamic cuerpo = <dynamic>[];
      switch (req.method) {
        case 'GET':
          switch (r) {
            case 'productos': cuerpo = _productos; break;
            case 'stock_imei': cuerpo = _imeis; break;
            case 'facturas': cuerpo = _facturas; break;
            case 'usuarios': cuerpo = _usuarios; break;
            case 'traslados':
              cuerpo = [
                {'id': 1, 'fecha': _f(_hoy), 'producto_codigo': 'ACC-001',
                 'producto_nombre': 'Cargador rápido 33W USB-C', 'cantidad': 5,
                 'tienda_origen': _principal, 'tienda_destino': _geo,
                 'nota': '', 'usuario': 'administracion@ejemplo.com'},
              ];
              break;
            case 'configuracion': cuerpo = _config; break;
            case 'tiendas':
              cuerpo = [for (final t in _tiendas) {'nombre': t, 'activa': 1}];
              break;
            case 'listas_precios':
              final id = int.tryParse(q['id'] ?? '');
              if (q['solo_marcas'] == '1') {
                cuerpo = [
                  for (final e in _listasServidor.entries)
                    if (id == null || e.key == id)
                      {'id': e.key, 'actualizado_en': '2026-10-16 08:00:00'}
                ];
              } else if (id != null) {
                cuerpo = _listasServidor[id] ?? {};
              } else {
                cuerpo = _listasServidor.values.toList();
              }
              break;
            case 'ficha_tecnica':
              if (q['codigo'] == 'TEL-003') {
                cuerpo = _fichaA16();
              } else if (q['codigo'] != null) {
                cuerpo = {'codigo': q['codigo'], 'nombre': '', 'origen': '', 'campos': []};
              } else {
                cuerpo = {
                  'fichas': [
                    for (final e in _origenFichas.entries)
                      {'codigo': e.key, 'origen': e.value}
                  ]
                };
              }
              break;
          }
          break;
        case 'POST':
          final b = enviado();
          if (r == 'configuracion') {
            _config.addAll(b);
            cuerpo = {'ok': true};
          } else if (r == 'listas_precios' && q['accion'] == 'precios_costo') {
            cuerpo = {'ok': true, 'listas': []};
          } else {
            cuerpo = {'ok': true, 'id': _sigId++};
          }
          break;
        case 'PUT':
          final b = enviado();
          final id = int.tryParse(q['id'] ?? '');
          if (r == 'listas_precios' && id != null) {
            _listasServidor[id] = {...b, 'id': id};
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
/// Cambia el grosor declarado (OS/2.usWeightClass) de una TTF en memoria:
/// Segoe UI no trae 500 ni 800 (ver tool/capturas_guia_test.dart).
Uint8List _conPeso(Uint8List b, int peso) {
  final d = ByteData.sublistView(b);
  final n = d.getUint16(4);
  for (var i = 0; i < n; i++) {
    final rec = 12 + i * 16;
    final tag = String.fromCharCodes(b.sublist(rec, rec + 4));
    if (tag == 'OS/2') d.setUint16(d.getUint32(rec + 8) + 4, peso);
  }
  return b;
}

Future<void> _cargarFuentes() async {
  const w = 'C:/Windows/Fonts';
  final raiz = Platform.environment['FLUTTER_ROOT'] ?? 'C:/src/flutter';
  final material = '$raiz/bin/cache/artifacts/material_fonts';
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
  // Símbolos y emojis que Segoe UI no trae (✎, 📋…): van como respaldo.
  for (final (nombre, archivo) in [('Simbolos', 'seguisym.ttf'), ('Emoji', 'seguiemj.ttf')]) {
    if (!File('$w/$archivo').existsSync()) continue;
    final c = FontLoader(nombre)
      ..addFont(Future.value(ByteData.sublistView(leer('$w/$archivo'))));
    await c.load();
  }
  final mi = FontLoader('MaterialIcons')
    ..addFont(Future.value(
        ByteData.sublistView(leer('$material/materialicons-regular.otf'))));
  await mi.load();
}

/// Tema de la app con la familia de fuente explícita en los estilos que no
/// la traen (en la prueba no hay fuente del sistema y salían barras).
ThemeData _tema() {
  final t = temaAppClaro();
  const respaldo = ['Simbolos', 'Emoji'];
  TextStyle? r(TextStyle? s) =>
      s?.copyWith(fontFamily: 'Roboto', fontFamilyFallback: respaldo);
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
      titleTextStyle:
          r(t.listTileTheme.titleTextStyle) ?? r(t.textTheme.titleMedium),
      subtitleTextStyle:
          r(t.listTileTheme.subtitleTextStyle) ?? r(t.textTheme.bodyMedium),
      leadingAndTrailingTextStyle:
          r(t.listTileTheme.leadingAndTrailingTextStyle),
    ),
    textTheme:
        t.textTheme.apply(fontFamily: 'Roboto', fontFamilyFallback: respaldo),
    primaryTextTheme: t.primaryTextTheme
        .apply(fontFamily: 'Roboto', fontFamilyFallback: respaldo),
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
      labelStyle:
          r(t.chipTheme.labelStyle) ?? const TextStyle(fontFamily: 'Roboto'),
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

// ═════════════════════════════════════════════════════════ utilidades
final _marco = GlobalKey();

/// La app como la arma MyApp (tema, escala de texto y, si se pide, el aviso
/// de actualización), sin pedir permisos ni arrancar el actualizador.
Widget _app(Widget inicio, {bool conAviso = false}) => RepaintBoundary(
      key: _marco,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _tema(),
        builder: (context, hijo) {
          Widget w = DefaultTextStyle.merge(
              style: const TextStyle(fontFamily: 'Roboto'), child: hijo!);
          if (conAviso) w = AvisoActualizacion(child: w);
          return w;
        },
        home: inicio,
      ),
    );

final _problemas = <String>[];
final _detalleProblemas = StringBuffer();
final _hechas = <String>[];

Future<void> _esperar(WidgetTester t, [int n = 30]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// Tamaño lógico de la ventana (escala 2 en el PNG).
void _vista(WidgetTester t, double ancho, double alto) {
  t.view.physicalSize = Size(ancho * 2, alto * 2);
  t.view.devicePixelRatio = 2;
}

/// Los textos con estilo propio sin familia (p. ej. el desplegable del
/// login) caen en la fuente de prueba del motor y salen como barras: se les
/// pone Roboto (la Segoe UI cargada arriba) solo para la foto. A todos se
/// les da de respaldo Segoe UI Symbol y Emoji (✎ salía como cajita).
void _arreglarFuentes(RenderObject o) {
  if (o is RenderParagraph) {
    var hayHueco = false;
    o.text.visitChildren((s) {
      if (s is PlaceholderSpan) hayHueco = true;
      return !hayHueco;
    });
    final st = o.text.style;
    final yaArreglado = st?.fontFamilyFallback?.contains('Simbolos') ?? false;
    if (!hayHueco && !yaArreglado) {
      o.text = TextSpan(
          style: TextStyle(
              fontFamily: st?.fontFamily == null ? 'Roboto' : null,
              fontFamilyFallback: const ['Simbolos', 'Emoji']),
          children: [o.text]);
    }
  }
  o.visitChildren(_arreglarFuentes);
}

Future<void> _guardar(WidgetTester t, String nombre) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await _esperar(t, 10);
  _arreglarFuentes(_marco.currentContext!.findRenderObject()!);
  await t.pump();
  final limite =
      _marco.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final bytes = await t.runAsync(() async {
    final imagen = await limite.toImage(pixelRatio: 2);
    final datos = await imagen.toByteData(format: ui.ImageByteFormat.png);
    return datos!.buffer.asUint8List();
  });
  final archivo = File('$_salida/$nombre.png')..createSync(recursive: true);
  archivo.writeAsBytesSync(bytes!);
  _hechas.add('$nombre.png');
  // ignore: avoid_print
  print('  ${archivo.path}');
}

/// Corre [cuerpo] con el servidor simulado, junta las excepciones de dibujo
/// (desbordes) y al final desmonta y deja correr los temporizadores.
Future<void> _seccion(WidgetTester t, String pantalla,
    Future<void> Function() cuerpo) async {
  final antes = _problemas.length;
  final original = FlutterError.onError;
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

Future<void> _tocar(WidgetTester t, Finder f) async {
  await t.ensureVisible(f.first);
  await t.pump();
  await t.tap(f.first);
  await _esperar(t, 10);
}

Usuario _usuario(String rol) {
  final m = _usuarios.firstWhere((u) => u['rol'] == rol,
      orElse: () => _usuarios.first);
  // Como tras el login: con el punto de venta elegido.
  return Usuario.fromMap({
    ...m,
    if ((m['tienda'] as String).isEmpty) 'tienda': _principal,
  });
}

void _sesion(String rol) => usuarioSesion = _usuario(rol);

/// Elige [opcion] del desplegable cuyo rótulo es [rotulo].
Future<void> _elegir(WidgetTester t, String rotulo, String opcion) async {
  final campo = find.ancestor(
      of: find.text(rotulo),
      matching: find.byWidgetPredicate((w) => w is DropdownButtonFormField));
  await _tocar(t, campo);
  await t.tap(find.text(opcion).last);
  await _esperar(t, 10);
}

/// Escribe en el campo de texto cuyo rótulo es [rotulo].
Future<void> _escribir(WidgetTester t, String rotulo, String texto) async {
  var campo = find.ancestor(
      of: find.text(rotulo), matching: find.byType(TextField));
  if (campo.evaluate().isEmpty) {
    // Rótulo encima del campo (los de la factura): el TextField de su Column.
    campo = find.descendant(
        of: find.ancestor(of: find.text(rotulo), matching: find.byType(Column)).first,
        matching: find.byType(TextField));
  }
  campo = campo.first;
  await t.ensureVisible(campo);
  await t.enterText(campo, texto);
  await _esperar(t, 3);
}

/// Lleva la pantalla (la primera lista desplazable) al final o al inicio.
Future<void> _desplazar(WidgetTester t, {required bool alFinal}) async {
  // La lista de la pantalla: la vertical con más recorrido (los TextField
  // también tienen un Scrollable adentro).
  final pos = t
      .stateList<ScrollableState>(find.byType(Scrollable))
      .map((s) => s.position)
      .where((p) => p.axis == Axis.vertical && p.hasContentDimensions)
      .reduce((a, b) => b.maxScrollExtent > a.maxScrollExtent ? b : a);
  pos.jumpTo(alFinal ? pos.maxScrollExtent : 0);
  await _esperar(t, 5);
}

/// Carga las listas «del servidor» en la memoria de la app.
void _reponerListas() {
  catalogoGlobal = _productos.map((m) => Producto.fromMap(Map.of(m))).toList();
  final listas = _listas();
  _listasServidor
    ..clear()
    ..addAll({for (final l in listas) l.id!: {...l.toMap(), 'id': l.id}});
  listasPreciosGlobal = listas;
}

// ═════════════════════════════════════════════════════════════ pruebas
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _cargarFuentes();
    SharedPreferences.setMockInitialValues({});
    final dir = Directory(_salida);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);
    _generarDatos();
    ConfigSistema.tiendas = List.of(_tiendas);
    ConfigSistema.tasaCambio = _tasa;
    TasaBCVScheduler.ultimaTasa = TasaBCV(
        valor: _tasa,
        fechaActualizacion: DateTime(_hoy.year, _hoy.month, _hoy.day, 8, 0),
        fuente: 'BCV');
    ConfigSistema.nombreEmpresa = 'Tecno Líder';
    usuariosSistema = _usuarios.map((m) => Usuario.fromMap(m)).toList();
    _reponerListas();
    _sesion('Administrador');
  });

  tearDownAll(() {
    final p = File('$_salida/problemas.txt');
    p.writeAsStringSync(_problemas.isEmpty
        ? 'Sin problemas de dibujo.\n'
        : '${_problemas.join('\n')}\n\n$_detalleProblemas');
    // ignore: avoid_print
    print('\nCapturas (${_hechas.length}): ${_hechas.join(', ')}');
    // ignore: avoid_print
    print('Problemas (${_problemas.length}):\n${_problemas.join('\n')}');
  });

  // ── 1. Editar lista en Bs: «Tomar precios de» ───────────────────
  testWidgets('editar lista en Bs', (t) async {
    _vista(t, 1200, 1250);
    addTearDown(t.view.reset);
    _sesion('Administrador');
    _reponerListas();
    await _seccion(t, 'Editar lista Bs', () async {
      await t.pumpWidget(_app(const VentanaListasPrecios()));
      await _esperar(t, 30);
      // El lápiz de «Equipos Bs»: se prueban en orden hasta dar con ella.
      final lapices = find.byTooltip('Editar configuración de la lista');
      var abierta = false;
      for (var i = 0; i < lapices.evaluate().length && !abierta; i++) {
        await _tocar(t, lapices.at(i));
        if (find.text('Tomar precios de (lista en divisas)').evaluate().isNotEmpty) {
          abierta = true;
        } else {
          await _tocar(t, find.text('Cancelar'));
        }
      }
      expect(abierta, isTrue);
      expect(find.text('Divisa'), findsWidgets);
      await _guardar(t, 'bs_editar_lista');
      // El desplegable abierto: la sugerida primero.
      await _tocar(t, find.ancestor(
          of: find.text('Tomar precios de (lista en divisas)'),
          matching: find.byWidgetPredicate((w) => w is DropdownButtonFormField)));
      expect(find.textContaining('(sugerida)'), findsWidgets);
      await _guardar(t, 'bs_selector_abierto');
    });
  });

  // ── 2. La lista en Bs al día con su base ────────────────────────
  testWidgets('lista en Bs con base', (t) async {
    _vista(t, 1200, 700);
    addTearDown(t.view.reset);
    _sesion('Administrador');
    _reponerListas();
    await _seccion(t, 'Lista Bs', () async {
      final bs = listasPreciosGlobal.firstWhere((l) => l.id == _idBs);
      final divisa = listasPreciosGlobal.firstWhere((l) => l.id == 11);
      // Un precio en Divisas distinto de la venta, para que se note de dónde sale.
      divisa.items.firstWhere((i) => i.producto.codigo == 'TEL-003')
          .preciosPorColumna['Divisa'] = 169;
      await t.pumpWidget(_app(DetalleListaPrecio(lista: bs)));
      await _esperar(t, 40);
      final a16 = bs.items.firstWhere((i) => i.producto.codigo == 'TEL-003');
      // 169 + 5 % = 177,45 → × tasa.
      expect(a16.preciosPorColumna['Precio Bs'],
          closeTo((177.45 * _tasa * 100).roundToDouble() / 100, 0.01));
      expect(bs.tasaDelDia, _tasa);
      await _guardar(t, 'bs_lista_detalle');
    });
  });

  // ── 3. Reporte de IMEIs: filtros ────────────────────────────────
  testWidgets('reporte de IMEIs: filtros', (t) async {
    _vista(t, 1100, 1300);
    addTearDown(t.view.reset);
    _sesion('Administrador');
    await _seccion(t, 'Filtros IMEI', () async {
      await t.pumpWidget(_app(const VentanaReportes()));
      await _esperar(t, 30);
      // Los filtros arriba de la pantalla, con la tarjeta debajo.
      Future<void> alFiltro() async {
        await t.runAsync(() async {});
        Scrollable.ensureVisible(
            t.element(find.text('Tienda', skipOffstage: false)),
            alignment: 0.05);
        await _esperar(t, 5);
      }
      await alFiltro();
      await _elegir(t, 'Tienda', _principal);
      await _elegir(t, 'Marca', 'Samsung');
      await alFiltro();
      expect(find.textContaining('Filtrado:'), findsOneWidget);
      await _guardar(t, 'imei_filtros');
      await alFiltro();
      await _tocar(t, find.ancestor(
          of: find.text('Modelo'),
          matching: find.byWidgetPredicate((w) => w is DropdownButtonFormField)));
      await _guardar(t, 'imei_modelos');
    });
  });

  // ── 4. Reporte de IMEIs: totales por tienda, marca y modelo ─────
  testWidgets('reporte de IMEIs: resumen', (t) async {
    _vista(t, 1300, 900);
    addTearDown(t.view.reset);
    _sesion('Administrador');
    await _seccion(t, 'Resumen IMEI', () async {
      HistorialReportes.entradas.clear();
      await t.runAsync(() => generarReporteIMEI());
      final todo = HistorialReportes.entradas.first;
      expect((todo.resumen['por_tienda'] as Map).length, greaterThanOrEqualTo(2));
      await t.pumpWidget(_app(VisorReporteScreen(entrada: todo)));
      await _esperar(t, 20);
      await _guardar(t, 'imei_resumen_todo');

      HistorialReportes.entradas.clear();
      await t.runAsync(() => generarReporteIMEI(
          filtro: const FiltroReporteImei(tienda: _geo, marca: 'Xiaomi')));
      final filtrado = HistorialReportes.entradas.first;
      for (final d in filtrado.detalles) {
        expect(d['ubicacion'], _geo);
        expect(d['marca'], 'Xiaomi');
      }
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(_app(VisorReporteScreen(entrada: filtrado)));
      await _esperar(t, 20);
      await _guardar(t, 'imei_resumen_filtrado');
    });
  });
}
