// Vista de las listas en Bs y dirección del cliente en la factura.
//
// Orden del dueño (23/10/2026): «modifica el sistema para que en la
// facturación le pida la dirección del cliente. Modifica las listas de
// bolívares para que tenga la opción de mostrar solo el precio BCV deseado
// usando porcentaje, ejemplo: si el precio en divisas es de 100$ y al BCV le
// quiero agregar 10% quedaría BCV = 110$ […] o la opción de que sí muestre
// también el equivalente a Bs».
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

ListaPrecio _divisas(Map<String, double> precios) => ListaPrecio(
      id: 1,
      nombre: 'Equipos Divisas',
      fechaCreacion: '2026-10-23',
      categoria: 'Telefono',
      columnas: [ColumnaPrecio(nombre: 'Precio')],
      items: [
        for (final e in precios.entries)
          ItemListaPrecio(
              producto: _p(e.key), preciosPorColumna: {'Precio': e.value}),
      ],
    );

ListaPrecio _bs({String vista = 'bs', bool arriba = false, String nombre = 'Equipos Bs'}) =>
    ListaPrecio(
      id: 2,
      nombre: nombre,
      fechaCreacion: '2026-10-23',
      categoria: 'Telefono',
      esEnBolivares: true,
      tasaDelDia: 36.57,
      porcentajeAdicional: 10,
      listaBaseId: 1,
      redondearArriba: arriba,
      vistaBs: vista,
      columnas: [ColumnaPrecio(nombre: 'Precio')],
      items: [
        ItemListaPrecio(producto: _p('A'), preciosPorColumna: {'Precio': 1}),
      ],
    );

void main() {
  setUp(() => ConfigSistema.tasaCambio = 36.57);
  tearDown(() => listasPreciosGlobal = []);

  test('el ejemplo del dueño: 100 \$ + 10 % = BCV 110 \$', () {
    final b = _bs(vista: 'bcv');
    listasPreciosGlobal = [_divisas({'A': 100}), b];
    seguirListaBase(b);
    final guardado = b.items[0].preciosPorColumna['Precio']!;
    // Lo guardado sigue en Bs (la 1.0.17 y el servidor no cambian).
    expect(guardado, 4022.7);
    expect(b.aVista(guardado), 110);
    expect(b.textoPrecio(guardado), '\$ 110.00');
    expect(b.monedaVista, '\$');
    expect(b.etiquetaVista, '\$ BCV');
  });

  test('vista BCV y Bs: el BCV y al lado su equivalente en Bs', () {
    final b = _bs(vista: 'bcv_bs');
    listasPreciosGlobal = [_divisas({'A': 100}), b];
    seguirListaBase(b);
    final g = b.items[0].preciosPorColumna['Precio']!;
    expect(b.textoPrecio(g), '\$ 110.00 · Bs 4022.70');
    expect(b.muestraBsAlLado, isTrue);
    expect(b.etiquetaVista, '\$ BCV y Bs');
  });

  test('vista de siempre: nada cambia', () {
    final b = _bs();
    listasPreciosGlobal = [_divisas({'A': 100}), b];
    seguirListaBase(b);
    final g = b.items[0].preciosPorColumna['Precio']!;
    expect(b.aVista(g), g);
    expect(b.textoPrecio(g), 'Bs 4022.70');
    expect(b.muestraBcv, isFalse);
    expect(b.desdeVista(123), 123);
  });

  test('una lista en divisas nunca se ve como BCV', () {
    final d = _divisas({'A': 100})..vistaBs = 'bcv';
    expect(d.muestraBcv, isFalse);
    expect(d.aVista(100), 100);
    expect(d.monedaVista, '\$');
  });

  test('sin decimales hacia arriba: vuelve al dólar entero', () {
    final b = _bs(vista: 'bcv', arriba: true);
    listasPreciosGlobal = [_divisas({'A': 100}), b];
    seguirListaBase(b);
    final g = b.items[0].preciosPorColumna['Precio']!;
    expect(g, 4023); // 110 × 36,57 = 4.022,7 → 4.023
    expect(b.aVista(g), 110);
  });

  test('lo que se escribe en \$ BCV se guarda en Bs', () {
    final b = _bs(vista: 'bcv');
    expect(b.desdeVista(110), 4022.7);
    expect(b.aVista(b.desdeVista(57.25)), 57.25);
  });

  test('vista_bs viaja de ida y vuelta; basura o nada = bs', () {
    final b = _bs(vista: 'bcv_bs');
    expect(b.toMap()['vista_bs'], 'bcv_bs');
    expect(ListaPrecio.fromMap(b.toMap()).vistaBs, 'bcv_bs');
    expect(ListaPrecio.fromMap({'nombre': 'vieja'}).vistaBs, 'bs');
    expect(normalizarVistaBs('xyz'), 'bs');
    expect(normalizarVistaBs('BCV'), 'bcv');
  });

  test('la factura toma el precio BCV en \$ de una lista «BCV» en Bs con vista BCV', () {
    final bcv = _bs(vista: 'bcv', nombre: 'BCV');
    listasPreciosGlobal = [_divisas({'A': 100}), bcv];
    seguirListaBase(bcv);
    final r = preciosReferenciaDe(
        codigo: 'A', precioVenta: 100, listas: listasPreciosGlobal);
    expect(r.bcv, 110);
  });

  test('la factura guarda y lee la dirección del cliente', () {
    final f = FacturaModel(
      cliente: 'Ana Pérez',
      cedula: '12345678',
      tienda: 'Centro',
      telefono: '0414',
      nroFactura: 'F-1',
      equipos: [],
      itemsSinImei: [],
      pagos: [],
      vendedor: 'Luis',
      fecha: '2026-10-23',
      direccion: 'Av. Lara, Barquisimeto',
    );
    final m = f.toApiMap();
    expect(m['direccion'], 'Av. Lara, Barquisimeto');
    expect(construirFacturaModelDesdeJson(m).direccion, 'Av. Lara, Barquisimeto');
    // Una factura vieja (sin el campo) se lee con la dirección vacía.
    expect(construirFacturaModelDesdeJson({'cliente': 'X'}).direccion, '');
  });

  test('el cliente recuerda su dirección', () {
    final c = ClienteModel.fromMap({
      'cedula': '1', 'nombre': 'A', 'telefono': '', 'correo': '',
      'direccion': 'Calle 1',
    });
    expect(c.direccion, 'Calle 1');
    expect(c.toMap()['direccion'], 'Calle 1');
  });
}
