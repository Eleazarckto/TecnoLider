// Reporte de IMEIs por tienda, marca y modelo (pedido del dueño 19/10/2026):
// filtros antes de generar + totales por tienda, marca y modelo.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tecno_lider/main.dart';

void main() {
  testWidgets('el ingreso de IMEIs permite buscar y elegir un equipo', (t) async {
    final catalogoAnterior = catalogoGlobal;
    final tiendasAnteriores = ConfigSistema.tiendas;
    final imeisAnteriores = stockImeiGlobal;
    catalogoGlobal = [];
    addTearDown(() {
      catalogoGlobal = catalogoAnterior;
      ConfigSistema.tiendas = tiendasAnteriores;
      stockImeiGlobal = imeisAnteriores;
    });

    await http.runWithClient(() async {
      await t.pumpWidget(const MaterialApp(home: VentanaImei()));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Registrar IMEI'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(OutlinedButton, 'Buscar equipo'));
      await t.pumpAndSettle();

      final buscador = find.widgetWithText(TextField, 'Nombre, marca, modelo o SKU');
      await t.enterText(buscador, 'inexistente');
      await t.pumpAndSettle();
      expect(find.text('No se encontraron equipos'), findsOneWidget);

      await t.enterText(buscador, '  SAMSUNG  sm-a155 ');
      await t.pumpAndSettle();
      expect(find.text('Galaxy A15'), findsOneWidget);
      expect(find.text('Redmi 13'), findsNothing);

      await t.enterText(buscador, 'rd13');
      await t.pumpAndSettle();
      await t.tap(find.text('Redmi 13'));
      await t.pumpAndSettle();
      expect(find.widgetWithText(OutlinedButton, 'Redmi 13'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'IMEI 1'), findsOneWidget);
    }, () => MockClient((request) async {
      final datos = switch (request.url.queryParameters['resource']) {
        'productos' => [
            {
              'codigo': 'GA15',
              'nombre': 'Galaxy A15',
              'marca': 'Samsung',
              'modelo': 'SM-A155',
              'categoria': 'Telefono',
            },
            {
              'codigo': 'RD13',
              'nombre': 'Redmi 13',
              'marca': 'Xiaomi',
              'modelo': 'Redmi 13',
              'categoria': 'Telefono',
            },
          ],
        'tiendas' => [{'nombre': 'Principal'}],
        _ => [],
      };
      return http.Response(jsonEncode(datos), 200, headers: {
        'content-type': 'application/json; charset=utf-8',
      });
    }));
  });

  test('tienda vacía = «Sin asignar»; modelo vacío = nombre del equipo', () {
    expect(tiendaDeImei('  '), kImeiSinAsignar);
    expect(tiendaDeImei(' Sucursal '), 'Sucursal');
    expect(modeloDeImei('SM-A155', 'Galaxy A15'), 'SM-A155');
    expect(modeloDeImei('', 'Galaxy A15'), 'Galaxy A15');
    expect(modeloDeImei('N/D', 'Galaxy A15'), 'Galaxy A15');
    expect(modeloDeImei('', ''), 'N/D');
  });

  test('sin filtro entra todo', () {
    const f = FiltroReporteImei();
    expect(f.esTodo, isTrue);
    expect(f.sufijo, '');
    expect(f.acepta(tienda: 'X', marca: 'Y', modelo: 'Z'), isTrue);
  });

  test('los tres filtros se cumplen a la vez, sin distinguir mayúsculas', () {
    const f = FiltroReporteImei(
        tienda: 'Sucursal', marca: 'samsung', modelo: 'Galaxy A15');
    expect(f.esTodo, isFalse);
    expect(
        f.acepta(tienda: 'sucursal', marca: 'Samsung', modelo: 'galaxy a15'),
        isTrue);
    expect(f.acepta(tienda: 'Principal', marca: 'Samsung', modelo: 'Galaxy A15'),
        isFalse);
    expect(f.acepta(tienda: 'Sucursal', marca: 'Xiaomi', modelo: 'Galaxy A15'),
        isFalse);
    expect(f.acepta(tienda: 'Sucursal', marca: 'Samsung', modelo: 'Galaxy A25'),
        isFalse);
    expect(f.sufijo, ' — Sucursal · samsung · Galaxy A15');
  });

  test('solo marca: todas las tiendas y modelos de esa marca', () {
    const f = FiltroReporteImei(marca: 'Xiaomi');
    expect(f.acepta(tienda: 'A', marca: 'Xiaomi', modelo: 'Redmi 13'), isTrue);
    expect(f.acepta(tienda: 'B', marca: 'Xiaomi', modelo: 'Note 14'), isTrue);
    expect(f.acepta(tienda: 'A', marca: 'Samsung', modelo: 'A15'), isFalse);
  });

  test('totales por tienda, marca y modelo con disponibles y vendidos', () {
    final r = ResumenImei()
      ..sumar(tienda: 'Principal', marca: 'Xiaomi', modelo: 'Redmi 13', vendido: false)
      ..sumar(tienda: 'Principal', marca: 'Xiaomi', modelo: 'Redmi 13', vendido: true)
      ..sumar(tienda: 'Sucursal', marca: 'Xiaomi', modelo: 'Note 14', vendido: false)
      ..sumar(tienda: 'Sucursal', marca: 'Samsung', modelo: 'A15', vendido: false);
    expect(r.porTienda['Principal']!.disponibles, 1);
    expect(r.porTienda['Principal']!.vendidos, 1);
    expect(r.porTienda['Sucursal']!.total, 2);
    expect(r.porMarca['Xiaomi']!.total, 3);
    expect(r.porMarca['Samsung']!.disponibles, 1);
    expect(r.porModelo['Redmi 13']!.texto, '1 disp. · 1 vend.');
    // De mayor a menor total; a igual total, por nombre.
    expect(ResumenImei.comoTexto(r.porModelo).keys.toList(),
        ['Redmi 13', 'A15', 'Note 14']);
  });

  test('el Excel saca los totales de los detalles guardados', () {
    final r = ResumenImei.deDetalles([
      {'ubicacion': '', 'marca': 'Xiaomi', 'modelo': 'N/D', 'nombre': 'Redmi 13', 'vendido': false},
      {'ubicacion': 'Sucursal', 'marca': 'Xiaomi', 'grupo_modelo': 'Redmi 13', 'vendido': true},
    ]);
    expect(r.porTienda.keys, containsAll([kImeiSinAsignar, 'Sucursal']));
    expect(r.porModelo['Redmi 13']!.total, 2);
    expect(r.porModelo['Redmi 13']!.vendidos, 1);
  });

  test('opciones: tiendas de la configuración y marcas/modelos con IMEI', () {
    final o = OpcionesFiltroImei.desde(
      tiendasConfig: ['Sucursal', 'Principal', 'Principal', ''],
      productos: [
        {'categoria': 'Telefono', 'marca': 'Xiaomi', 'modelo': '', 'nombre': 'Redmi 13'},
        {'categoria': 'Telefono', 'marca': 'Samsung', 'modelo': 'SM-A155', 'nombre': 'A15'},
        {'categoria': 'Telefono', 'marca': '', 'modelo': '', 'nombre': 'Genérico'},
        {'categoria': 'Accesorio', 'marca': 'Anker', 'modelo': 'C1', 'nombre': 'Cargador'},
      ],
      usaImei: (c) => c == 'Telefono',
    );
    expect(o.tiendas, [kImeiTodas, 'Principal', 'Sucursal', kImeiSinAsignar]);
    expect(o.marcas, [kImeiTodas, 'N/D', 'Samsung', 'Xiaomi']);
    expect(o.modelosDe('Xiaomi'), [kImeiTodos, 'Redmi 13']);
    expect(o.modelosDe(kImeiTodas),
        [kImeiTodos, 'Genérico', 'Redmi 13', 'SM-A155']);
    expect(o.modelosDe('Anker'), o.modelosDe(kImeiTodas),
        reason: 'una marca sin IMEI no se ofrece; cae a todos los modelos');
  });
}
