// % especial por tipo de producto, redondeo hacia arriba y quién ve los
// porcentajes (pedido del 15/10/2026). Los casos son los mismos que
// backend/tests/precios_listas_test.php: la app y el servidor tienen que dar
// el mismo número.

import 'package:flutter_test/flutter_test.dart';
import 'package:tecno_lider/reglas_porcentaje.dart';

void main() {
  final reglasAccesorios = [
    ReglaPorcentaje(nombre: 'Cornetas', palabras: ['corneta', 'parlante'], pct: 100),
    ReglaPorcentaje(nombre: 'Vidrios', palabras: ['VIDRIO', ' Templado '], pct: 150),
  ];

  group('qué regla le toca a un producto', () {
    test('por palabra del nombre, sin mayúsculas ni tildes', () {
      expect(reglaPara(reglasAccesorios, 'Corneta JBL Go 3', 'JBL')?.nombre, 'Cornetas');
      expect(reglaPara(reglasAccesorios, 'CORNÉTA Xtreme', '')?.pct, 100);
      expect(reglaPara(reglasAccesorios, 'Vidrio Templado iPhone 14', '')?.nombre, 'Vidrios');
    });

    test('sin regla que calce: null (se usa el % de la lista)', () {
      expect(reglaPara(reglasAccesorios, 'Forro silicone', ''), isNull);
    });

    test('por marca, sin importar mayúsculas', () {
      final r = [ReglaPorcentaje(nombre: 'iPhone', marca: 'apple', pct: 12)];
      expect(reglaPara(r, 'iPhone 15 128GB', 'Apple')?.pct, 12);
      expect(reglaPara(r, 'Redmi 13', 'Xiaomi'), isNull);
    });

    test('gana la primera que calce', () {
      final r = [
        ReglaPorcentaje(nombre: 'A', palabras: ['cargador'], pct: 90),
        ReglaPorcentaje(nombre: 'B', palabras: ['cargador'], pct: 50),
      ];
      expect(reglaPara(r, 'Cargador 20W', '')?.nombre, 'A');
    });

    test('una regla sin palabras ni marca no calza con nada', () {
      final r = [ReglaPorcentaje(nombre: 'Vacía', palabras: [' ', ''], pct: 50)];
      expect(r.first.esValida, isFalse);
      expect(reglaPara(r, 'Cualquier cosa', ''), isNull);
    });
  });

  group('lo que viaja al servidor', () {
    test('ida y vuelta por JSON, con las palabras normalizadas', () {
      final json = reglasAJson(reglasAccesorios)!;
      final vuelta = reglasDesdeJson(json);
      expect(vuelta.map((r) => r.nombre), ['Cornetas', 'Vidrios']);
      expect(vuelta[1].palabras, ['vidrio', 'templado']);
      expect(vuelta[1].pct, 150);
    });

    test('sin reglas válidas se manda null', () {
      expect(reglasAJson([]), isNull);
      expect(reglasAJson([ReglaPorcentaje(nombre: 'x', pct: 10)]), isNull);
    });

    test('lo que guarda el servidor (texto, lista, null o roto) se lee sin romper', () {
      expect(reglasDesdeJson(null), isEmpty);
      expect(reglasDesdeJson(''), isEmpty);
      expect(reglasDesdeJson('{roto'), isEmpty);
      expect(reglasDesdeJson([
        {'nombre': 'C', 'palabras': 'corneta, parlante', 'pct': '90'}
      ]).single.palabras, ['corneta', 'parlante']);
    });
  });

  group('redondeo hacia arriba, sin decimales', () {
    test('casos del pedido', () {
      expect(aEnteroArriba(22.3), 23);
      expect(aEnteroArriba(22.01), 23);
      expect(aEnteroArriba(26.3), 27);
      expect(aEnteroArriba(25686.99), 25687);
    });

    test('un entero exacto no sube por un error de coma flotante', () {
      expect(aEnteroArriba(23.0000001), 23);
      expect(aEnteroArriba(0.1 + 0.2 + 22.7), 23);
      expect(aEnteroArriba(23), 23);
    });
  });

  group('quién ve el % que se le suma al costo', () {
    test('solo Dueño, Administrador y Gerente (y el maestro)', () {
      for (final rol in ['Dueño', 'Dueno', 'Administrador', 'Gerente', 'Maestro', ' gerente ']) {
        expect(puedeVerPorcentajesListas(rol), isTrue, reason: rol);
      }
      for (final rol in ['Vendedor', 'Cajero', 'Encargado', 'Contador', 'Técnico',
          'Redes', 'Activador', '', null]) {
        expect(puedeVerPorcentajesListas(rol), isFalse, reason: '$rol');
      }
      expect(puedeVerPorcentajesListas('Vendedor', esMaestro: true), isTrue);
    });
  });
}
