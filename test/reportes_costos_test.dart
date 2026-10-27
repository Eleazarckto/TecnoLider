// El costo y la ganancia fuera de los reportes de quien no es Dueño,
// Administrador, Gerente ni Maestro (traído de Brizuela, pedido del
// 15/10/2026). Ver lib/reportes_costos.dart.

import 'package:flutter_test/flutter_test.dart';
import 'package:tecno_lider/reportes_costos.dart';

void main() {
  test('reconoce los datos de costo, con o sin tildes y mayúsculas', () {
    for (final n in ['Precio Costo', 'precio_costo', 'valor_total_costo',
        'Ganancia bruta', 'ganancia_neta', 'Margen %', 'Utilidad', 'COSTO UNIT.']) {
      expect(esDatoDeCosto(n), isTrue, reason: n);
    }
    for (final n in ['Precio Venta', 'Stock', 'Código', 'total_productos',
        'valor_total_venta', 'Cliente']) {
      expect(esDatoDeCosto(n), isFalse, reason: n);
    }
  });

  test('inventario: se va la columna Precio Costo y nada más', () {
    final t = quitarColumnasDeCosto(
      ['Código', 'Nombre', 'Categoría', 'Marca', 'Modelo', 'Stock', 'Precio Costo', 'Precio Venta'],
      [
        ['BC0101', 'Corneta JBL Go 3', 'Accesorio', 'JBL', '', 4, 13.15, 27],
        ['IPH15', 'iPhone 15', 'Telefono', 'Apple', '15', 1, 700, 784],
      ],
    );
    expect(t.encabezados, ['Código', 'Nombre', 'Categoría', 'Marca', 'Modelo', 'Stock', 'Precio Venta']);
    expect(t.filas.first, ['BC0101', 'Corneta JBL Go 3', 'Accesorio', 'JBL', '', 4, 27]);
    expect(t.filas.last.contains(700), isFalse);
  });

  test('sin columnas de costo, la tabla queda igual', () {
    final enc = ['Nro', 'Cliente', 'Total'];
    final filas = [
      [1, 'Ana', 20]
    ];
    final t = quitarColumnasDeCosto(enc, filas);
    expect(t.encabezados, same(enc));
    expect(t.filas, same(filas));
  });

  test('ventas: el costo anidado en los productos de cada factura también se va', () {
    final detalle = {
      'nro_factura': '66',
      'cliente': 'José',
      'productos': [
        {'nombre': 'Forro', 'precio_venta': 4.0, 'precio_costo': 2.3},
        {'nombre': 'Vidrio', 'precio_venta': 3.0, 'precio_costo': 1.5},
      ],
      'pagos': [
        {'metodo': 'Pago Móvil', 'monto': 7.0}
      ],
    };
    final limpio = quitarClavesDeCosto(detalle) as Map;
    expect(limpio['cliente'], 'José');
    for (final p in limpio['productos'] as List) {
      expect((p as Map).containsKey('precio_costo'), isFalse);
      expect(p.containsKey('precio_venta'), isTrue);
    }
    expect((limpio['pagos'] as List).single, {'metodo': 'Pago Móvil', 'monto': 7.0});
    // El original no se toca: el dueño sigue viendo su reporte completo.
    expect(((detalle['productos'] as List).first as Map).containsKey('precio_costo'), isTrue);
  });

  test('resumen: se van los totales al costo y las ganancias', () {
    final r = quitarClavesDeCosto({
      'total_productos': 2,
      'valor_total_costo': 713.15,
      'valor_total_venta': 811.0,
      'por_tienda': {'Centro': {'ingreso': 100, 'ganancia': 30}},
    }) as Map;
    expect(r.keys, ['total_productos', 'valor_total_venta', 'por_tienda']);
    expect(r['por_tienda'], {'Centro': {'ingreso': 100}});
  });
}
