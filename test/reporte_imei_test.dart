// Reporte de IMEIs por tienda, marca y modelo (pedido del dueño 19/10/2026):
// filtros antes de generar + totales por tienda, marca y modelo.
import 'package:flutter_test/flutter_test.dart';
import 'package:tecno_lider/main.dart';

void main() {
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
