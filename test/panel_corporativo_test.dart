// ============================================================================
//  panel_corporativo_test.dart — El Panel Corporativo traído de Brizuela
//
//  Orden del dueño (16/10/2026): «agrega el panel corporativo tal cual lo
//  tiene Brizuela». Dueño, Gerente, Administrador y el Maestro entran
//  primero al panel; desde él ven las tiendas y los módulos, tocan una
//  tienda para vender en ella y vuelven al panel. Los demás roles no lo
//  ven. Todo contra un servidor SIMULADO (MockClient), que además anota
//  qué se le pidió: abrir el panel no puede escribir nada.
// ============================================================================

import 'dart:convert';

import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tecno_lider/main.dart';

const _principal = 'Tecno Líder Principal', _geo = 'Geo Cell';

final _hoy = DateTime.now();
String _f(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

final _productos = [
  {'id': 1, 'codigo': 'ACC-001', 'nombre': 'Cargador 33W', 'categoria': 'Accesorio',
   'marca': 'Genérico', 'modelo': 'N/A', 'precio_costo': 4, 'precio_venta': 9,
   'stock_manual': 40, 'tienda': _principal},
  {'id': 2, 'codigo': 'ACC-002', 'nombre': 'Audífonos Buds 6', 'categoria': 'Accesorio',
   'marca': 'Xiaomi', 'modelo': 'Buds 6', 'precio_costo': 6, 'precio_venta': 14,
   'stock_manual': 25, 'tienda': _geo},
];

final _facturas = [
  {'id': 1, 'nro_factura': 'F-1', 'cliente': 'María', 'cedula': 'V-1',
   'telefono': '', 'vendedor': 'Laura', 'tienda': _principal, 'fecha': _f(_hoy),
   'items': [{'codigo': 'ACC-001', 'vendedor': 'Laura'}],
   'equipos': [], 'pagos': [{'metodo': 'Divisas', 'monto': 9, 'tipo': 'Contado'}]},
  {'id': 2, 'nro_factura': 'F-2', 'cliente': 'José', 'cedula': 'V-2',
   'telefono': '', 'vendedor': 'Miguel', 'tienda': _geo, 'fecha': _f(_hoy),
   'items': [{'codigo': 'ACC-002', 'vendedor': 'Miguel'}],
   'equipos': [],
   'pagos': [{'metodo': 'Pago Móvil', 'monto': 2800, 'tipo': 'Contado', 'tasa_cambio': 200}]},
];

final _peticiones = <String>[];

http.Client _servidor() => MockClient((req) async {
      final r = req.url.queryParameters['resource'] ?? '';
      _peticiones.add('${req.method} $r');
      dynamic cuerpo = <dynamic>[];
      if (req.method == 'GET') {
        switch (r) {
          case 'facturas': cuerpo = _facturas; break;
          case 'productos': cuerpo = _productos; break;
          case 'configuracion': cuerpo = <String, dynamic>{}; break;
          case 'tiendas':
            cuerpo = [for (final t in [_principal, _geo]) {'nombre': t, 'activa': 1}];
            break;
          case 'traslados':
            cuerpo = [
              {'id': 1, 'fecha': _f(_hoy), 'producto_codigo': 'ACC-001',
               'producto_nombre': 'Cargador 33W', 'cantidad': 2,
               'tienda_origen': _principal, 'tienda_destino': _geo},
            ];
            break;
        }
      } else {
        cuerpo = {'ok': true};
      }
      return http.Response(jsonEncode(cuerpo), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });

Future<void> _esperar(WidgetTester t, [int n = 30]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void _sesion(String rol) => usuarioSesion = Usuario(
    nombre: 'Carolina', cedula: 'V-9', correo: 'c@ejemplo.com', clave: '',
    rol: rol, tienda: '');

const _modulos = [
  'Almacén / Inventario', 'Reportes', 'Reporte Vendedor', 'Comisiones',
  'Estadística Producto', 'Financiadoras', 'Usuarios', 'Cuentas x Cobrar',
  'Cuentas x Pagar', 'CxP Proveedores', 'Buscador IMEI', 'Clientes',
  'Listas de Precios', 'Consulta Rápida', 'Traslados', 'Configuración',
];

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ConfigSistema.tiendas = [_principal, _geo];
    ConfigSistema.tasaCambio = 200;
    catalogoGlobal = _productos.map((m) => Producto.fromMap(Map.of(m))).toList();
    for (final p in catalogoGlobal) {
      p.stockTotal = p.stockManual;
    }
    _peticiones.clear();
  });

  test('entran al panel Dueño, Gerente, Administrador y Maestro; nadie más', () {
    for (final rol in ['Dueño', 'Gerente', 'Administrador', 'Maestro']) {
      expect(debeEntrarAlPanelCorporativo(rol), isTrue, reason: rol);
    }
    for (final rol in ['Vendedor', 'Encargado', 'Cajero', 'Activador', '', null]) {
      expect(debeEntrarAlPanelCorporativo(rol), isFalse, reason: '$rol');
    }
  });

  for (final rol in ['Dueño', 'Maestro']) {
    testWidgets('$rol: el panel muestra las tiendas y los módulos, y una tienda '
        'abre ventas y vuelve al panel', (t) async {
      t.view.physicalSize = const Size(1200, 3200);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      _sesion(rol);
      await http.runWithClient(() async {
        await t.pumpWidget(const MaterialApp(home: PanelCorporativo()));
        await _esperar(t);

        expect(find.text('Panel corporativo'), findsOneWidget);
        expect(find.text('Hola, Carolina'), findsOneWidget);
        expect(find.text('Ventas de hoy'), findsOneWidget);
        expect(find.text('2 factura(s) hoy'), findsOneWidget);
        expect(find.text('1 traslado(s) hoy'), findsOneWidget);
        for (final m in _modulos) {
          expect(find.text(m), findsOneWidget, reason: m);
        }
        // Brizuela trae estos, pero Tecno Líder no tiene la pantalla.
        for (final m in ['Activación', 'Líneas', 'Movimientos', 'Financiamiento']) {
          expect(find.text(m), findsNothing, reason: m);
        }

        // Vista de tarjetas: una por tienda, con sus cifras.
        await t.tap(find.text('Tarjetas'));
        await _esperar(t, 15);
        expect(find.text(_principal), findsOneWidget);
        expect(find.text(_geo), findsOneWidget);
        expect(find.text('1 factura(s) este mes · 1 hoy'), findsNWidgets(2));

        // Abrir el panel solo LEE del servidor.
        expect(_peticiones.where((p) => !p.startsWith('GET ')), isEmpty,
            reason: '$_peticiones');

        // Tocar una tienda abre ventas de esa tienda, marcada como desde el panel.
        await t.tap(find.text(_geo));
        await _esperar(t, 20);
        final ventas = t.widget<VentasPrincipal>(find.byType(VentasPrincipal));
        expect(ventas.tienda, _geo);
        expect(ventas.desdePanel, isTrue);
        expect(usuarioSesion?.tienda, _geo);

        // Y se vuelve al panel con el botón de la barra.
        await t.tap(find.byTooltip('Volver al panel corporativo'));
        await _esperar(t, 20);
        expect(find.byType(VentasPrincipal), findsNothing);
        expect(find.byType(PanelCorporativo), findsOneWidget);
        expect(usuarioSesion?.tienda, '', reason: 'se restaura la tienda previa');

        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 1));
      }, _servidor);
    });
  }

  testWidgets('el menú de ventas ofrece el panel a los roles altos, no al vendedor',
      (t) async {
    t.view.physicalSize = const Size(1200, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await http.runWithClient(() async {
      for (final (rol, ve) in [('Dueño', true), ('Vendedor', false)]) {
        _sesion(rol);
        usuarioSesion!.tienda = _principal;
        await t.pumpWidget(MaterialApp(
            key: ValueKey(rol), home: const VentasPrincipal(tienda: _principal)));
        await _esperar(t, 20);
        t.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
        await _esperar(t, 10);
        expect(find.text('Panel Corporativo'), ve ? findsOneWidget : findsNothing,
            reason: rol);
        // Sin venir del panel no hay botón de volver a él.
        expect(find.byTooltip('Volver al panel corporativo'), findsNothing);
      }
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
    }, _servidor);
  });
}
