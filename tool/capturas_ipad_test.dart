// Capturas de iPad 13" para App Store Connect, sin abrir ninguna ventana.
//
// Se ejecuta con:
//   flutter test tool/capturas_ipad_test.dart
//
// Deja los PNG en build/capturas_ipad/ a 2752x2064 (iPad 13" horizontal,
// tamano aceptado por Apple). Dibuja las pantallas REALES de la app con un
// servidor simulado y datos de ejemplo (nombres ficticios): no toca la API
// de produccion ni muestra datos de clientes, y se puede rehacer cuando
// cambie la app. Mismo metodo que tool/capturas_app_store.dart de
// Transporte GG.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tecno_lider/main.dart';

// ------------------------------------------------------------ datos ficticios
final _hoy = DateTime.now();
String _f(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

const _tiendas = ['Tienda Centro', 'Tienda Norte', 'Almacén'];

final _productos = <Map<String, dynamic>>[
  _p('TEL-001', 'Honor Play 10 4/128', 'Telefono', 'Honor', 'Play 10', 95, 129),
  _p('TEL-002', 'Honor X5c 4/128', 'Telefono', 'Honor', 'X5c', 88, 119),
  _p('TEL-003', 'Honor X6c 6/256', 'Telefono', 'Honor', 'X6c', 125, 169),
  _p('TEL-004', 'Samsung Galaxy A16 4/128', 'Telefono', 'Samsung', 'Galaxy A16', 128, 175),
  _p('TEL-005', 'Samsung Galaxy A26 6/128', 'Telefono', 'Samsung', 'Galaxy A26', 175, 239),
  _p('TEL-006', 'Xiaomi Redmi 14C 4/128', 'Telefono', 'Xiaomi', 'Redmi 14C', 92, 125),
  _p('TEL-007', 'Xiaomi Redmi Note 14 8/256', 'Telefono', 'Xiaomi', 'Redmi Note 14', 170, 229),
  _p('ACC-001', 'Cargador rápido 33W', 'Accesorio', 'Genérico', 'N/A', 4, 12, stock: 40),
  _p('ACC-002', 'Audífonos Bluetooth', 'Accesorio', 'Genérico', 'N/A', 6, 18, stock: 25),
  _p('ACC-003', 'Forro antigolpe', 'Accesorio', 'Genérico', 'N/A', 1.5, 6, stock: 80),
];

Map<String, dynamic> _p(String c, String n, String cat, String marca,
        String modelo, double costo, double venta, {int stock = 0}) =>
    {
      'id': c.hashCode.abs() % 10000,
      'codigo': c, 'nombre': n, 'categoria': cat, 'marca': marca,
      'modelo': modelo, 'tipo': '', 'precio_costo': costo,
      'precio_venta': venta, 'stock_manual': stock, 'tienda': 'Tienda Centro',
      'producto_padre_codigo': '', 'variante': '',
    };

final _imeis = <Map<String, dynamic>>[];
final _facturas = <Map<String, dynamic>>[];

const _clientes = [
  'María González', 'José Pérez', 'Ana Rodríguez', 'Carlos Méndez',
  'Luisa Fernández', 'Pedro Castillo', 'Rosa Martínez', 'Andrés Suárez',
];
const _vendedores = ['Laura Ríos', 'Miguel Torres', 'Daniela Salas'];

void _generarDatos() {
  var serie = 350000000000000;
  var nro = 1001;
  // Por modelo: [vendidos por tienda..., en stock por tienda...]
  final plan = {
    'TEL-001': [9, 6, 0, 7, 5, 8], 'TEL-002': [7, 5, 0, 4, 6, 6],
    'TEL-003': [4, 3, 0, 2, 1, 3], 'TEL-004': [6, 4, 0, 5, 3, 4],
    'TEL-005': [3, 2, 0, 1, 0, 2], 'TEL-006': [5, 5, 0, 6, 4, 5],
    'TEL-007': [2, 1, 0, 3, 2, 1],
  };
  var dia = 0;
  plan.forEach((codigo, v) {
    for (var t = 0; t < 3; t++) {
      for (var k = 0; k < v[t]; k++) {
        final imei = '${serie++}';
        _imeis.add(_imei(imei, codigo, _tiendas[t], vendido: true));
        final fecha = DateTime(_hoy.year, _hoy.month, 1 + (dia++ % _hoy.day));
        final prod = _productos.firstWhere((p) => p['codigo'] == codigo);
        _facturas.add({
          'id': nro, 'nro_factura': 'F-${nro++}',
          'cliente': _clientes[dia % _clientes.length],
          'cedula': 'V-${12000000 + dia * 7919}', 'telefono': '0414-0000000',
          'vendedor': _vendedores[dia % _vendedores.length],
          'tienda': _tiendas[t], 'fecha': _f(fecha),
          'equipos': [
            {'imei': imei, 'producto_codigo': codigo,
             'vendedor': _vendedores[(dia + 1) % _vendedores.length]}
          ],
          'items': [
            if (dia % 3 == 0)
              {'codigo': 'ACC-003',
               'vendedor': _vendedores[dia % _vendedores.length]}
          ],
          'pagos': [
            {'metodo': dia % 2 == 0 ? 'Pago Móvil' : 'Divisas',
             'monto': prod['precio_venta'], 'tipo': 'Contado'}
          ],
        });
      }
      for (var k = 0; k < v[3 + t]; k++) {
        _imeis.add(_imei('${serie++}', codigo, _tiendas[t], vendido: false));
      }
    }
  });
}

Map<String, dynamic> _imei(String imei, String codigo, String ubicacion,
    {required bool vendido}) {
  final p = _productos.firstWhere((x) => x['codigo'] == codigo);
  return {
    'imei': imei, 'producto_codigo': codigo,
    'fecha_ingreso': _f(DateTime(_hoy.year, _hoy.month, 1)),
    'proveedor': 'Distribuidora Ejemplo', 'color': 'Negro',
    'ubicacion': ubicacion, 'porcentaje_bateria': null,
    'vendido': vendido ? 1 : 0,
    'producto_nombre': p['nombre'], 'categoria': p['categoria'],
    'marca': p['marca'], 'modelo': p['modelo'], 'tipo': '',
    'precio_costo': p['precio_costo'], 'precio_venta': p['precio_venta'],
  };
}

/// Servidor simulado: responde por `resource` con los datos de arriba y
/// con una lista vacia para todo lo demas.
http.Client _servidor() => MockClient((req) async {
      final r = req.url.queryParameters['resource'] ?? '';
      dynamic cuerpo = <dynamic>[];
      if (req.method == 'GET') {
        switch (r) {
          case 'productos': cuerpo = _productos; break;
          case 'stock_imei': cuerpo = _imeis; break;
          case 'facturas': cuerpo = _facturas; break;
          case 'tiendas':
            cuerpo = [for (final t in _tiendas) {'nombre': t, 'activa': 1}];
            break;
        }
      }
      return http.Response(jsonEncode(cuerpo), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });

// ---------------------------------------------------------------- captura
/// Las pruebas no tienen fuentes del sistema: sin esto los textos salen
/// como barras negras. Se usa Segoe UI de Windows para la fuente por
/// defecto y los iconos Material que trae Flutter.
Future<void> _cargarFuentes() async {
  const windows = 'C:/Windows/Fonts';
  final material =
      '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
  Future<void> familia(String nombre, List<String> archivos) async {
    final cargador = FontLoader(nombre);
    for (final a in archivos) {
      cargador.addFont(File(a).readAsBytes().then(
          (b) => ByteData.view(Uint8List.fromList(b).buffer)));
    }
    await cargador.load();
  }

  // Segoe UI no trae grosores 100, 200, 500 ni 800; para esos Flutter
  // volvia a su fuente de prueba (barras). build/fuentes_capturas tiene
  // copias de Segoe con esos grosores declarados (pip install fonttools):
  //   from fontTools.ttLib import TTFont
  //   for w, f in {100: 'segoeuil', 200: 'segoeuil', 500: 'seguisb',
  //                800: 'segoeuib'}.items():
  //       t = TTFont(f'C:/Windows/Fonts/{f}.ttf')
  //       t['OS/2'].usWeightClass = w
  //       t.save(f'build/fuentes_capturas/segoe_{w}.ttf')
  final segoe = [
    for (final f in ['segoeuil.ttf', 'segoeui.ttf', 'seguisb.ttf',
                     'segoeuib.ttf', 'seguibl.ttf'])
      '$windows/$f',
    for (final w in [100, 200, 500, 800])
      if (File('build/fuentes_capturas/segoe_$w.ttf').existsSync())
        'build/fuentes_capturas/segoe_$w.ttf',
  ];
  // Los estilos sin familia usan la fuente por defecto del sistema, que
  // en Windows es "Segoe UI": tambien se registra con ese nombre.
  for (final nombre in ['Roboto', 'Segoe UI', 'FlutterTest', 'Ahem',
                        '.SF UI Text', '.SF UI Display', 'sans-serif']) {
    await familia(nombre, segoe);
  }
  await familia('MaterialIcons', ['$material/materialicons-regular.otf']);
}

final _marco = GlobalKey();

/// Tema de la app con la familia de fuente explicita en los estilos que no
/// la traen (titulo de la barra, chips, etiquetas). En un telefono esos
/// estilos usan la fuente del sistema; en la prueba no hay fuente del
/// sistema y salian como barras.
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
          const TextStyle(fontFamily: 'Roboto'),
      toolbarTextStyle: r(t.appBarTheme.toolbarTextStyle),
    ),
    chipTheme: t.chipTheme.copyWith(
      labelStyle: r(t.chipTheme.labelStyle) ??
          const TextStyle(fontFamily: 'Roboto'),
      secondaryLabelStyle: r(t.chipTheme.secondaryLabelStyle),
    ),
    tabBarTheme: t.tabBarTheme.copyWith(
      labelStyle: r(t.tabBarTheme.labelStyle),
      unselectedLabelStyle: r(t.tabBarTheme.unselectedLabelStyle),
    ),
  );
}

Widget _app(Widget inicio) => RepaintBoundary(
      key: _marco,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _tema(),
        // Los textos que no toman estilo del tema heredan de aqui.
        builder: (context, hijo) => DefaultTextStyle.merge(
            style: const TextStyle(fontFamily: 'Roboto'), child: hijo!),
        home: inicio,
      ),
    );

Future<void> _esperar(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _guardar(WidgetTester tester, String nombre) async {
  await _esperar(tester);
  final limite =
      _marco.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final bytes = await tester.runAsync(() async {
    final imagen = await limite.toImage(pixelRatio: 2);
    final datos = await imagen.toByteData(format: ui.ImageByteFormat.png);
    return datos!.buffer.asUint8List();
  });
  final archivo = File('build/capturas_ipad/$nombre.png')
    ..createSync(recursive: true);
  archivo.writeAsBytesSync(bytes!);
  // ignore: avoid_print
  print('  ${archivo.path}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _cargarFuentes();
    SharedPreferences.setMockInitialValues({});
    _generarDatos();
    usuarioSesion = Usuario(
        id: 1, nombre: 'Administrador', cedula: 'V-00000000',
        correo: 'admin@ejemplo.com', clave: '', rol: 'Dueño');
  });

  testWidgets('capturas iPad 13 horizontal', (tester) async {
    // 1376x1032 puntos a escala 2 = 2752x2064 pixeles.
    tester.view.physicalSize = const Size(2752, 2064);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await http.runWithClient(() async {
      await tester.pumpWidget(_app(const VentanaEstadisticasProductos()));
      await _guardar(tester, '01_estadisticas_productos');

      await tester.pumpWidget(_app(const VentanaReportes()));
      await _guardar(tester, '02_reportes');

      await tester.pumpWidget(_app(const VentanaInventario()));
      await _guardar(tester, '03_inventario');
    }, _servidor);
  });
}
