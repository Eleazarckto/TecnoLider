// Pruebas de las correcciones de listas de precios: orden de columnas
// al exportar, imagen sin transparencias, cuotas por modelo, precios
// retocados a mano que siguen al precio del producto y productos
// agregados a mano.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tecno_lider/main.dart';

Producto _p(String codigo, {double venta = 100, int stock = 1}) => Producto(
      codigo: codigo,
      nombre: 'Prod $codigo',
      categoria: 'Accesorio',
      marca: 'Demo',
      modelo: 'M',
      tipo: 'Nuevo',
      precioCosto: 50,
      precioVenta: venta,
      stockManual: stock,
    );

ListaPrecio _krece() => ListaPrecio(
      nombre: 'Krece',
      fechaCreacion: '',
      esFinanciamiento: true,
      porcentajeInicial: 30,
      numeroCuotas: 6,
      columnas: [
        ColumnaPrecio(nombre: 'Precio'),
        ColumnaPrecio(nombre: 'DIVISAS'),
        ColumnaPrecio(nombre: 'BCV'),
        ColumnaPrecio(nombre: 'CASHEA'),
      ],
    );

void main() {
  tearDown(() {
    catalogoGlobal = [];
    invalidarStockListas();
  });

  group('Orden de columnas al exportar', () {
    test('financiamiento: base, inicial/cuotas y luego el resto en orden',
        () {
      expect(ordenColumnasExport(_krece()), [
        'Precio',
        kColExportInicial,
        kColExportNCuotas,
        kColExportMontoCuota,
        'DIVISAS',
        'BCV',
        'CASHEA',
      ]);
    });

    test('sin columnas de precio sólo sale el bloque de financiamiento', () {
      final l = _krece()..tieneCuotas = false;
      expect(ordenColumnasExport(l, incluirColumnas: false),
          [kColExportInicial]);
    });

    test('lista normal respeta el orden y omite las virtuales', () {
      final l = ListaPrecio(nombre: 'N', fechaCreacion: '', columnas: [
        ColumnaPrecio(nombre: 'Divisa'),
        ColumnaPrecio(nombre: '__fx__abc'),
        ColumnaPrecio(nombre: 'BCV'),
      ]);
      expect(ordenColumnasExport(l), ['Divisa', 'BCV']);
    });

    test('mover columnas: la base queda fija', () {
      final l = _krece();
      expect(moverColumnaLista(l, 2, -1), isTrue); // BCV antes de DIVISAS
      expect(l.columnas.map((c) => c.nombre),
          ['Precio', 'BCV', 'DIVISAS', 'CASHEA']);
      expect(moverColumnaLista(l, 1, -1), isFalse); // no pasa a la base
      expect(moverColumnaLista(l, 0, 1), isFalse); // la base no se mueve
      expect(moverColumnaLista(l, 3, 1), isFalse); // fuera de rango
      expect(ordenColumnasExport(l).last, 'CASHEA');
    });
  });

  test('aplanarSobreBlanco quita la transparencia', () {
    final px = Uint8List.fromList([
      0, 0, 0, 0, // transparente → blanco
      10, 20, 30, 255, // opaco → igual
      0, 0, 0, 128, // negro a medias → gris
    ]);
    aplanarSobreBlanco(px);
    expect(px.sublist(0, 4), [255, 255, 255, 255]);
    expect(px.sublist(4, 8), [10, 20, 30, 255]);
    expect(px[11], 255);
    expect(px[8], inInclusiveRange(125, 129));
  });

  group('Precio manual que sigue al precio del producto', () {
    test('igual al defecto → defecto nuevo', () {
      expect(precioManualSegunDefecto(110, 110, 132), 132);
    });

    test('retocado a mano (redondeado) → proporcional y redondeado igual',
        () {
      // Krece: venta 130 + 27 % = 165,10 → el admin lo dejó en 168.
      // Venta pasa a 140: 177,80 → 168 × 177,8 / 165,1 = 180,9 → 181.
      expect(precioManualSegunDefecto(168, 165.1, 177.8), 181);
      // Múltiplo de 5 se conserva.
      expect(precioManualSegunDefecto(165, 165.1, 177.8), 180);
    });

    test('precio especial (lejos del defecto) se respeta', () {
      expect(precioManualSegunDefecto(95, 110, 132), isNull);
    });

    test('recalcular item: lista de Krece con precios redondeados', () {
      final viejo = _p('A', venta: 130);
      final nuevo = _p('A', venta: 140);
      final l = ListaPrecio(
        nombre: 'K',
        fechaCreacion: '',
        porcentajeAdicional: 27,
        columnas: [
          ColumnaPrecio(nombre: 'Precio'),
          ColumnaPrecio(
              nombre: 'BCV',
              formula: FormulaColumna(
                  modo: FormulaColumna.modoPorcentaje, valor: 20)),
        ],
      );
      l.items.add(ItemListaPrecio(
          producto: viejo, preciosPorColumna: {'Precio': 168, 'BCV': 156}));
      recalcularItemPorCambioDePrecio(l, 0, viejo, nuevo);
      expect(l.items.first.preciosPorColumna['Precio'], 181);
      expect(l.items.first.preciosPorColumna['BCV'], 168);
    });
  });

  test('sincronizarPrecioEnCatalogo y refrescarProductosDeLista', () {
    final viejo = _p('A', venta: 100);
    catalogoGlobal = [viejo, _p('B')];
    final l = ListaPrecio(
      nombre: 'L',
      fechaCreacion: '',
      columnas: [
        ColumnaPrecio(
            nombre: 'Precio',
            formula: FormulaColumna(
                modo: FormulaColumna.modoPorcentaje, valor: 10)),
      ],
    );
    l.items.add(ItemListaPrecio(producto: viejo, preciosPorColumna: {}));
    sincronizarPrecioEnCatalogo(viejo, _p('A', venta: 200));
    expect(catalogoGlobal.first.precioVenta, 200);
    expect(refrescarProductosDeLista(l), 1);
    l.aplicarFormulas();
    expect(l.items.first.preciosPorColumna['Precio'], 220);
  });

  test('cuotas por modelo', () {
    final l = _krece();
    final it = ItemListaPrecio(
        producto: _p('S'), preciosPorColumna: {'Precio': 100}, cuotaManual: 9);
    l.items.add(it);
    expect(fijarCuotasDeItem(l, it, 8), isTrue);
    expect(l.cuotasDe(it), 8);
    expect(it.cuotaManual, isNull); // el monto fijo era para 6 cuotas
    expect(l.cuotasUniformes, 8);
    expect(fijarCuotasDeItem(l, it, 6), isTrue); // igual al general
    expect(it.cuotasOverride, isNull);
    expect(fijarCuotasDeItem(l, it, null), isFalse);
  });
}
