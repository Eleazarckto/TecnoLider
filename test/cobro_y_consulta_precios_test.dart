import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tecno_lider/main.dart';

Producto _producto(String codigo) => Producto(
      codigo: codigo,
      nombre: 'Accesorio $codigo',
      categoria: 'Accesorio',
      marca: 'Demo',
      modelo: 'M',
      tipo: 'Nuevo',
      precioCosto: 50,
      precioVenta: 100,
      stockManual: 3,
    );

ListaPrecio _lista(String nombre, Producto p, double precio,
        {bool bs = false, bool financiada = false}) =>
    ListaPrecio(
      nombre: nombre,
      fechaCreacion: '',
      categoria: p.categoria,
      esEnBolivares: bs,
      tasaDelDia: bs ? 100 : 1,
      esFinanciamiento: financiada,
      columnas: [ColumnaPrecio(nombre: 'Precio')],
      items: [
        ItemListaPrecio(producto: p, preciosPorColumna: {'Precio': precio})
      ],
    );

Future<void> _conPrecios(List<Producto> productos, List<ListaPrecio> listas,
    Future<void> Function() prueba) {
  final original = FlutterError.onError;
  FlutterError.onError = (d) {
    if (d.exceptionAsString().contains('ListTile background color')) return;
    original?.call(d);
  };
  return http
      .runWithClient(
          prueba,
          () => MockClient((request) async {
                final data = switch (request.url.queryParameters['resource']) {
                  'productos' => productos.map((p) => p.toMap()).toList(),
                  'listas_precios' => listas.map((l) => l.toMap()).toList(),
                  _ => [],
                };
                return http.Response(jsonEncode(data), 200, headers: {
                  'content-type': 'application/json; charset=utf-8'
                });
              }))
      .whenComplete(() => FlutterError.onError = original);
}

Finder _selector(String rotulo) => find.ancestor(
    of: find.text(rotulo),
    matching: find.byWidgetPredicate((w) => w is DropdownButtonFormField));

Future<void> _abrirFacturaConProducto(WidgetTester t) async {
  t.view.physicalSize = const Size(900, 1600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: FormularioFactura(tienda: 'Principal')));
  await t.pumpAndSettle();
  final agregar = find.widgetWithText(TextButton, 'Agregar').first;
  await t.ensureVisible(agregar);
  await t.tap(agregar);
  await t.pumpAndSettle();
  final codigo = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == 'IMEI o código SKU');
  await t.enterText(codigo, 'A');
  await t.pumpAndSettle();
}

Future<void> _agregarProductoYAbrirPago(WidgetTester t) async {
  await t.tap(find.widgetWithText(ElevatedButton, 'Agregar'));
  await t.pumpAndSettle();
  final agregar = find.widgetWithText(TextButton, 'Agregar').last;
  await t.ensureVisible(agregar);
  await t.tap(agregar);
  await t.pumpAndSettle();
}

String _monto(WidgetTester t, String etiqueta) => t
    .widget<TextField>(find.widgetWithText(TextField, etiqueta))
    .controller!
    .text;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    usuarioSesion = Usuario(
        nombre: 'Prueba',
        cedula: 'V-1',
        correo: 'prueba@ejemplo.com',
        clave: '',
        rol: 'Administrador',
        tienda: 'Principal');
    ConfigSistema.tasaCambio = 200;
    catalogoGlobal = [];
    stockImeiGlobal = [];
    listasPreciosGlobal = [];
    invalidarStockListas();
  });

  testWidgets(r'Contado propone $100 o el equivalente en Bs de $120',
      (t) async {
    final p = _producto('A');
    await _conPrecios([p], [_lista('De contado', p, 12000, bs: true)],
        () async {
      await _abrirFacturaConProducto(t);
      await _agregarProductoYAbrirPago(t);
      expect(_monto(t, 'Monto (Bs)'), '24000.00');
      await t.tap(_selector('Método de pago'));
      await t.pumpAndSettle();
      await t.tap(find.text('Divisas').last);
      await t.pumpAndSettle();
      expect(_monto(t, r'Monto ($)'), '100.00');
      await t.tap(_selector('Método de pago'));
      await t.pumpAndSettle();
      await t.tap(find.text('Efectivo Bs').last);
      await t.pumpAndSettle();
      expect(_monto(t, 'Monto (Bs)'), '24000.00');
      await t.tap(find.widgetWithText(ElevatedButton, 'Confirmar'));
      await t.pumpAndSettle();
      expect(find.text('Cuadra: se puede guardar.'), findsOneWidget);
    });
  });

  testWidgets('Krece carga su lista y propone cobrar la inicial aprobada',
      (t) async {
    final p = _producto('A');
    await _conPrecios([p], [_lista('KRECE Normal', p, 145, financiada: true)],
        () async {
      await _abrirFacturaConProducto(t);
      await t.tap(_selector('F/D (Financiadora)'));
      await t.pumpAndSettle();
      await t.tap(find.text('Krece').last);
      await t.pumpAndSettle();
      expect(find.text('KRECE Normal'), findsOneWidget);
      await t.enterText(
          find.widgetWithText(TextField, r'Inicial aprobada ($, a BCV)'),
          '46,40');
      await _agregarProductoYAbrirPago(t);
      expect(_monto(t, 'Monto (Bs)'), '9280.00');
      await t.tap(find.widgetWithText(ElevatedButton, 'Confirmar'));
      await t.pumpAndSettle();
      expect(find.text('Cuadra: se puede guardar.'), findsOneWidget);
    });
  });

  testWidgets('Consulta Rápida muestra un alta con stock al abrir', (t) async {
    final anterior = _producto('A');
    final nuevo = _producto('B');
    catalogoGlobal = [anterior];
    final lista = _lista('Divisas', anterior, 120)..porcentajeAdicional = 25;
    await _conPrecios([anterior, nuevo], [lista], () async {
      await t
          .pumpWidget(const MaterialApp(home: VentanaConsultaRapidaPrecios()));
      await t.pumpAndSettle();
      await t.tap(find.text(nuevo.nombre));
      await t.pumpAndSettle();
      expect(find.text(formatCurrency(125)), findsOneWidget);
      expect(listasPreciosGlobal.single.items.length, 1);
    });
  });

  test('El margen de Krece sustituye el porcentaje sobre el precio de venta',
      () {
    final p = _producto('A');
    final lista = _lista('KRECE', p, 120, financiada: true);
    expect(lista.precioConMargenDeVenta(p, 20), 120);
    expect(lista.precioConMargenDeVenta(p, 25), 125);
  });

  test(
      'Una fuente sin fecha puede respaldar una tasa, pero prima la fecha real',
      () {
    final sinFecha = TasaBCV(
        valor: 103,
        fechaActualizacion: DateTime.utc(2026, 11, 20),
        fuente: 'Backend',
        fechaConfirmada: false);
    final vieja = TasaBCV(
        valor: 101,
        fechaActualizacion: DateTime.utc(2026, 11, 18, 4),
        fuente: 'BCV');
    final reciente = TasaBCV(
        valor: 102,
        fechaActualizacion: DateTime.utc(2026, 11, 19, 4),
        fuente: 'Referencia BCV');
    expect(
        ServicioBCV.masReciente([sinFecha, vieja, reciente]), same(reciente));
  });
}
