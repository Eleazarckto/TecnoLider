// Pruebas de la sincronización de las listas de precios con el
// inventario: stock global (todas las tiendas + variantes), cambio de
// precio de un producto y montos fijos de financiamiento.
import 'package:flutter_test/flutter_test.dart';
import 'package:tecno_lider/main.dart';

Producto _p(String codigo,
        {double venta = 100,
        double costo = 50,
        int stock = 0,
        String padre = '',
        String tienda = '',
        String categoria = 'Accesorio'}) =>
    Producto(
      codigo: codigo,
      nombre: 'Prod $codigo',
      categoria: categoria,
      marca: 'Demo',
      modelo: 'M',
      tipo: 'Nuevo',
      precioCosto: costo,
      precioVenta: venta,
      stockManual: stock,
      productoPadreCodigo: padre,
      tienda: tienda,
    );

void main() {
  tearDown(() {
    catalogoGlobal = [];
    invalidarStockListas();
  });

  test('stock global suma tiendas y variantes', () {
    catalogoGlobal = [
      _p('A', stock: 0, tienda: 'Principal'),
      _p('A', stock: 2, tienda: 'Sucursal'),
      _p('A-1', stock: 3, padre: 'A'),
      _p('B', stock: 0),
    ];
    invalidarStockListas();
    expect(stockGlobalDeProducto(catalogoGlobal.first), 5);
    expect(stockGlobalDeProducto(catalogoGlobal.last), 0);
  });

  test('itemsConStock oculta agotados sin borrarlos', () {
    final a = _p('A', stock: 1);
    final b = _p('B', stock: 0);
    catalogoGlobal = [a, b];
    invalidarStockListas();
    final l = ListaPrecio(nombre: 'L', fechaCreacion: '', columnas: [
      ColumnaPrecio(nombre: 'Precio'),
    ]);
    l.items.addAll([
      ItemListaPrecio(producto: a, preciosPorColumna: {'Precio': 10}),
      ItemListaPrecio(producto: b, preciosPorColumna: {'Precio': 99}),
    ]);
    expect(l.itemsConStock.map((i) => i.producto.codigo), ['A']);
    expect(l.items.length, 2);
  });

  test('cambio de precio: actualiza lo automático y respeta lo manual', () {
    final viejo = _p('A', venta: 100, stock: 1);
    final nuevo = _p('A', venta: 120, stock: 1);
    final l = ListaPrecio(
      nombre: 'L',
      fechaCreacion: '',
      porcentajeAdicional: 10,
      columnas: [
        ColumnaPrecio(nombre: 'Contado'), // manual, seguía el defecto
        ColumnaPrecio(nombre: 'Especial'), // manual, editada a mano
        ColumnaPrecio(
            nombre: 'Cashea',
            formula: FormulaColumna(
                modo: FormulaColumna.modoPorcentaje, valor: 20)),
      ],
    );
    l.items.add(ItemListaPrecio(producto: viejo, preciosPorColumna: {
      'Contado': 110, // 100 + 10 %
      'Especial': 95,
      'Cashea': 120,
    }));
    final n = recalcularItemPorCambioDePrecio(l, 0, viejo, nuevo);
    expect(n, greaterThan(0));
    final it = l.items.first;
    expect(it.producto.precioVenta, 120);
    expect(it.preciosPorColumna['Contado'], 132); // 120 + 10 %
    expect(it.preciosPorColumna['Especial'], 95); // respetado
    expect(it.preciosPorColumna['Cashea'], 144); // 120 + 20 %
  });

  test('cambio de % inicial limpia montos fijos de quien usa el general', () {
    final p = _p('A', stock: 1);
    final l = ListaPrecio(
      nombre: 'F',
      fechaCreacion: '',
      esFinanciamiento: true,
      porcentajeInicial: 30,
      numeroCuotas: 6,
      columnas: [ColumnaPrecio(nombre: 'Precio')],
    );
    l.items.addAll([
      ItemListaPrecio(
          producto: p, preciosPorColumna: {'Precio': 100}, inicialManual: 30),
      ItemListaPrecio(
          producto: p,
          preciosPorColumna: {'Precio': 100},
          inicialManual: 50,
          pctInicialOverride: 50),
    ]);
    expect(l.contarMontosFijosAfectados(cambioPct: true), 1);
    l.porcentajeInicial = 40;
    expect(l.limpiarMontosFijosAfectados(cambioPct: true), 1);
    expect(l.items.first.inicialManual, isNull);
    expect(l.inicialDe(l.items.first, 100), 40);
    expect(l.items.last.inicialManual, 50); // condición propia: no se toca
  });
}
