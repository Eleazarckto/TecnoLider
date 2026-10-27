// Listas en Bs que toman sus precios de una lista en divisas.
//
// Orden del dueño (19/10/2026): «en las listas de precios en bolívares tome
// el precio de las listas en divisas y sea a esa lista la que se le aumente
// el porcentaje». Precio en Bs = precio en la lista base × (1 + % de la
// lista en Bs) × tasa; lo que no esté en la base sale del precio de venta;
// los precios marcados ✎ no se tocan.
import 'package:flutter_test/flutter_test.dart';
import 'package:tecno_lider/main.dart';

Producto _p(String codigo, {double venta = 100}) => Producto(
      codigo: codigo,
      nombre: 'Prod $codigo',
      categoria: 'Telefono',
      marca: 'Xiaomi',
      modelo: 'M',
      tipo: 'Nuevo',
      precioCosto: 50,
      precioVenta: venta,
      stockManual: 1,
    );

ListaPrecio _divisas({int id = 1, Map<String, double> precios = const {}}) =>
    ListaPrecio(
      id: id,
      nombre: 'Equipos Divisas',
      fechaCreacion: '2026-10-19',
      categoria: 'Telefono',
      columnas: [ColumnaPrecio(nombre: 'Precio')],
      items: [
        for (final e in precios.entries)
          ItemListaPrecio(
              producto: _p(e.key), preciosPorColumna: {'Precio': e.value}),
      ],
    );

ListaPrecio _bs({int? base = 1, double pct = 10, List<String> codigos = const []}) =>
    ListaPrecio(
      id: 2,
      nombre: 'Equipos Bs',
      fechaCreacion: '2026-10-19',
      categoria: 'Telefono',
      esEnBolivares: true,
      tasaDelDia: 90,
      porcentajeAdicional: pct,
      listaBaseId: base,
      columnas: [ColumnaPrecio(nombre: 'Precio')],
      items: [
        for (final c in codigos)
          ItemListaPrecio(producto: _p(c), preciosPorColumna: {'Precio': 1}),
      ],
    );

void main() {
  setUp(() => ConfigSistema.tasaCambio = 100);
  tearDown(() => listasPreciosGlobal = []);

  test('precio en Bs = precio en divisas + % de la lista Bs, × tasa', () {
    final d = _divisas(precios: {'A': 80});
    final b = _bs();
    listasPreciosGlobal = [d, b];
    // 80 + 10 % = 88 → × 100 = 8.800 (no la venta de 100).
    expect(b.precioPorDefecto(_p('A')), 8800);
  });

  test('producto que no está en la base: sale del precio de venta', () {
    listasPreciosGlobal = [_divisas(precios: {'A': 80}), _bs()];
    expect(listasPreciosGlobal[1].precioPorDefecto(_p('Z', venta: 100)), 11000);
  });

  test('precio 0 en la base cuenta como «no está»', () {
    listasPreciosGlobal = [_divisas(precios: {'A': 0}), _bs()];
    expect(listasPreciosGlobal[1].precioPorDefecto(_p('A')), 11000);
  });

  test('sin lista base todo sigue como antes (venta + % × tasa)', () {
    final b = _bs(base: null);
    listasPreciosGlobal = [_divisas(precios: {'A': 80}), b];
    expect(b.precioPorDefecto(_p('A')), 11000);
    expect(seguirListaBase(b), 0);
    expect(b.items, isEmpty);
  });

  test('una lista en Bs no puede ser base de otra', () {
    final otraBs = _bs(base: null)..id = 1;
    final b = _bs()..id = 3;
    listasPreciosGlobal = [otraBs, b];
    expect(listaBaseDe(b), isNull);
  });

  test('seguirListaBase: recalcula lo no marcado, respeta ✎ y pone la tasa',
      () {
    final b = _bs(codigos: ['A', 'B', 'Z']);
    b.items[1].marcarManual('Precio');
    b.items[1].preciosPorColumna['Precio'] = 5000;
    listasPreciosGlobal = [_divisas(precios: {'A': 80, 'B': 60}), b];
    final n = seguirListaBase(b);
    expect(n, greaterThan(0));
    expect(b.tasaDelDia, 100);
    expect(b.items[0].preciosPorColumna['Precio'], 8800);
    expect(b.items[1].preciosPorColumna['Precio'], 5000); // ✎
    expect(b.items[2].preciosPorColumna['Precio'], 11000); // venta
    expect(seguirListaBase(b), 0, reason: 'segunda pasada no cambia nada');
  });

  test('tasa fija de la lista Bs manda sobre la del sistema', () {
    final b = _bs(codigos: ['A'])
      ..tasaFija = true
      ..tasaDelDia = 50;
    listasPreciosGlobal = [_divisas(precios: {'A': 80}), b];
    seguirListaBase(b);
    expect(b.items[0].preciosPorColumna['Precio'], 4400);
    expect(b.tasaDelDia, 50);
  });

  test('lista_base_id viaja de ida y vuelta; sin base viaja 0', () {
    final b = _bs();
    expect(b.toMap()['lista_base_id'], 1);
    expect(ListaPrecio.fromMap(b.toMap()).listaBaseId, 1);
    final sin = _bs(base: null);
    expect(sin.toMap()['lista_base_id'], 0);
    expect(ListaPrecio.fromMap(sin.toMap()).listaBaseId, isNull);
    expect(ListaPrecio.fromMap({'nombre': 'vieja'}).listaBaseId, isNull);
    final copia = _bs(base: null)..adoptar(b);
    expect(copia.listaBaseId, 1);
  });

  test('cambio de precio en el inventario: la lista Bs sigue a la base', () {
    final d = _divisas(precios: {'A': 80});
    final b = _bs(codigos: ['A']);
    listasPreciosGlobal = [d, b];
    seguirListaBase(b);
    // La lista en divisas ya subió a 90; la venta del producto cambia.
    d.items[0].preciosPorColumna['Precio'] = 90;
    final n = recalcularItemPorCambioDePrecio(
        b, 0, _p('A', venta: 100), _p('A', venta: 120), [d, b]);
    expect(n, greaterThan(0));
    expect(b.items[0].preciosPorColumna['Precio'], 9900); // 90 + 10 % × 100
  });

  test('la migración de marcas ✎ no toca listas con base', () {
    final b = _bs(codigos: ['A']);
    listasPreciosGlobal = [_divisas(precios: {'A': 80}), b];
    expect(migrarMarcasManuales(b), 0);
    expect(b.items[0].columnasManuales, isEmpty);
  });

  test('sugerida: la de divisas de la misma categoría y marca', () {
    final d = _divisas(precios: {});
    final acc = ListaPrecio(
        id: 9, nombre: 'Accesorios', fechaCreacion: '', categoria: 'Accesorio');
    final b = _bs();
    expect(listaBaseSugerida(b, [acc, d]), same(d));
    expect(listasBaseElegibles(b, [acc, d, b]).first, same(d));
    expect(listasBaseElegibles(b, [acc, d, b]), isNot(contains(b)));
  });
}
