// Pruebas del motor de funciones de las columnas de las listas de
// precios: el evaluador de fórmulas y el cálculo de cada columna.
import 'package:flutter_test/flutter_test.dart';
import 'package:tecno_lider/main.dart';

Producto _producto({double costo = 100, double venta = 200}) => Producto(
      codigo: 'P1',
      nombre: 'Equipo demo',
      categoria: 'Telefonos',
      marca: 'Demo',
      modelo: 'X',
      tipo: 'Nuevo',
      precioCosto: costo,
      precioVenta: venta,
      stockManual: 3,
    );

ListaPrecio _lista({
  List<ColumnaPrecio>? columnas,
  double tasa = 40,
  double adicional = 0,
  bool bolivares = false,
}) {
  final cols = columnas ?? [ColumnaPrecio(nombre: 'Precio')];
  final lista = ListaPrecio(
    nombre: 'Demo',
    fechaCreacion: '2026-01-01',
    columnas: cols,
    tasaDelDia: tasa,
    porcentajeAdicional: adicional,
    esEnBolivares: bolivares,
  );
  lista.items.add(ItemListaPrecio(
    producto: _producto(),
    preciosPorColumna: {for (final c in cols) c.nombre: 150.0},
    stockDisponible: 3,
  ));
  return lista;
}

void main() {
  group('EvaluadorFormula', () {
    final vars = {'costo': 100.0, 'venta': 200.0, 'tasa': 40.0, '[detal]': 250.0};

    test('aritmética y precedencia', () {
      expect(EvaluadorFormula.evaluar('2 + 3 * 4', vars), 14);
      expect(EvaluadorFormula.evaluar('(2 + 3) * 4', vars), 20);
      expect(EvaluadorFormula.evaluar('2 ^ 3', vars), 8);
      expect(EvaluadorFormula.evaluar('-5 + 10', vars), 5);
      expect(EvaluadorFormula.evaluar('10 mod 3', vars), 1);
    });

    test('variables y referencias a columnas', () {
      expect(EvaluadorFormula.evaluar('costo * 1.25', vars), 125);
      expect(EvaluadorFormula.evaluar('venta / tasa', vars), 5);
      expect(EvaluadorFormula.evaluar('[Detal] + 10', vars), 260);
    });

    test('funciones', () {
      expect(EvaluadorFormula.evaluar('techo(10.2)', vars), 11);
      expect(EvaluadorFormula.evaluar('piso(10.9)', vars), 10);
      expect(EvaluadorFormula.evaluar('redondear(10.567; 2)', vars), 10.57);
      expect(EvaluadorFormula.evaluar('min(3; 9)', vars), 3);
      expect(EvaluadorFormula.evaluar('max(3; 9)', vars), 9);
      expect(EvaluadorFormula.evaluar('abs(0 - 7)', vars), 7);
      expect(EvaluadorFormula.evaluar('raiz(16)', vars), 4);
    });

    test('condicionales', () {
      expect(
          EvaluadorFormula.evaluar('si(costo > 50; costo * 1.1; costo)', vars),
          closeTo(110, 0.001));
      expect(
          EvaluadorFormula.evaluar('si(costo > 500 o venta > 100; 1; 0)', vars),
          1);
      expect(
          EvaluadorFormula.evaluar('si(costo > 500 y venta > 100; 1; 0)', vars),
          0);
    });

    test('fórmulas inválidas devuelven null', () {
      expect(EvaluadorFormula.evaluar('costo * ', vars), isNull);
      expect(EvaluadorFormula.evaluar('(costo + 1', vars), isNull);
      expect(EvaluadorFormula.evaluar('inexistente + 1', vars), isNull);
      expect(EvaluadorFormula.evaluar('costo / 0', vars), isNull);
      expect(EvaluadorFormula.validar('costo * 2', vars), isNull);
      expect(EvaluadorFormula.validar('costo *', vars), isNotNull);
    });
  });

  group('Cálculo de columnas', () {
    test('porcentaje sobre el costo', () {
      final col = ColumnaPrecio(
        nombre: 'Mayorista',
        formula: FormulaColumna(
            modo: FormulaColumna.modoPorcentaje, origen: 'costo', valor: 12),
      );
      final lista = _lista(columnas: [ColumnaPrecio(nombre: 'Base'), col]);
      expect(lista.calcularColumna(col, lista.items.first), 112);
    });

    test('multiplicador sobre el precio de venta con redondeo a ,99', () {
      final col = ColumnaPrecio(
        nombre: 'Detal',
        formula: FormulaColumna(
            modo: FormulaColumna.modoMultiplicador,
            origen: 'venta',
            valor: 1.35,
            redondeo: 'psicologico'),
      );
      final lista = _lista(columnas: [ColumnaPrecio(nombre: 'Base'), col]);
      // 200 × 1.35 = 270 → 269.99
      expect(lista.calcularColumna(col, lista.items.first), closeTo(269.99, 0.001));
    });

    test('monto fijo restado a otra columna', () {
      final base = ColumnaPrecio(nombre: 'Base');
      final col = ColumnaPrecio(
        nombre: 'Contado',
        formula: FormulaColumna(
            modo: FormulaColumna.modoMonto,
            origen: 'columna',
            columnaOrigen: 'Base',
            valor: -20),
      );
      final lista = _lista(columnas: [base, col]);
      expect(lista.calcularColumna(col, lista.items.first), 130); // 150 − 20
    });

    test('fórmula libre con tasa y redondeo a múltiplos', () {
      final col = ColumnaPrecio(
        nombre: 'Bs',
        formula: FormulaColumna(
            modo: FormulaColumna.modoExpresion,
            expresion: 'base * tasa',
            redondeo: 'multiplo',
            multiplo: 100),
      );
      final lista = _lista(columnas: [ColumnaPrecio(nombre: 'Base'), col]);
      // 150 × 40 = 6000 → múltiplo de 100 = 6000
      expect(lista.calcularColumna(col, lista.items.first), 6000);
    });

    test('el % adicional de la lista se puede aplicar', () {
      final col = ColumnaPrecio(
        nombre: 'ConMargen',
        formula: FormulaColumna(
            modo: FormulaColumna.modoMultiplicador,
            origen: 'costo',
            valor: 1,
            aplicarAdicional: true),
      );
      final lista = _lista(
          columnas: [ColumnaPrecio(nombre: 'Base'), col], adicional: 10);
      expect(lista.calcularColumna(col, lista.items.first), 110);
    });

    test('una columna manual no se calcula', () {
      final col = ColumnaPrecio(nombre: 'Manual');
      final lista = _lista(columnas: [ColumnaPrecio(nombre: 'Base'), col]);
      expect(lista.calcularColumna(col, lista.items.first), isNull);
    });

    test('una columna no puede alimentarse de sí misma', () {
      final col = ColumnaPrecio(
        nombre: 'Loop',
        formula: FormulaColumna(
            modo: FormulaColumna.modoPorcentaje,
            origen: 'columna',
            columnaOrigen: 'Loop',
            valor: 10),
      );
      final lista = _lista(columnas: [col]);
      expect(lista.calcularColumna(col, lista.items.first), isNull);
    });

    test('aplicarFormulas escribe los precios y respeta el modo manual', () {
      final base = ColumnaPrecio(nombre: 'Base');
      final auto = ColumnaPrecio(
        nombre: 'Mayorista',
        formula: FormulaColumna(
            modo: FormulaColumna.modoPorcentaje, origen: 'costo', valor: 20),
      );
      final noAuto = ColumnaPrecio(
        nombre: 'Especial',
        formula: FormulaColumna(
            modo: FormulaColumna.modoPorcentaje,
            origen: 'costo',
            valor: 50,
            auto: false),
      );
      final lista = _lista(columnas: [base, auto, noAuto]);
      final it = lista.items.first;

      lista.aplicarFormulas(); // solo automáticas
      expect(it.preciosPorColumna['Mayorista'], 120);
      expect(it.preciosPorColumna['Especial'], 150); // sin tocar
      expect(it.preciosPorColumna['Base'], 150); // manual, sin tocar

      lista.aplicarFormulas(soloAutomaticas: false);
      expect(it.preciosPorColumna['Especial'], 150.0);
      expect(lista.tieneFormulas, isTrue);
    });
  });

  group('Persistencia de las funciones', () {
    test('ida y vuelta por toMap/fromMap conservando la función', () {
      catalogoGlobal
        ..clear()
        ..add(_producto());
      final col = ColumnaPrecio(
        nombre: 'Mayorista',
        formula: FormulaColumna(
            modo: FormulaColumna.modoPorcentaje,
            origen: 'costo',
            valor: 12,
            redondeo: 'entero',
            aplicarTasa: true,
            auto: false),
      );
      final lista = _lista(columnas: [ColumnaPrecio(nombre: 'Base'), col]);
      lista.id = 7;

      final mapa = lista.toMap();
      // Viajan las 2 columnas reales + 1 virtual con la función
      expect((mapa['columnas'] as List).length, 3);

      final vuelta = ListaPrecio.fromMap(Map<String, dynamic>.from(mapa));
      // Las columnas virtuales NO se muestran como columnas
      expect(vuelta.columnas.length, 2);
      final rec = vuelta.columnas.firstWhere((c) => c.nombre == 'Mayorista');
      expect(rec.formula.modo, FormulaColumna.modoPorcentaje);
      expect(rec.formula.origen, 'costo');
      expect(rec.formula.valor, 12);
      expect(rec.formula.redondeo, 'entero');
      expect(rec.formula.aplicarTasa, isTrue);
      expect(rec.formula.auto, isFalse);
    });

    test('un backend que solo guarda nombres igual recupera la función', () {
      catalogoGlobal
        ..clear()
        ..add(_producto());
      final col = ColumnaPrecio(
        nombre: 'Detal',
        formula: FormulaColumna(
            modo: FormulaColumna.modoMultiplicador,
            origen: 'venta',
            valor: 1.4),
      );
      final lista = _lista(columnas: [ColumnaPrecio(nombre: 'Base'), col]);
      final mapa = lista.toMap();
      // Simulamos un backend que descarta la clave `formula`
      mapa['columnas'] = (mapa['columnas'] as List)
          .map((c) => {'nombre': (c as Map)['nombre']})
          .toList();

      final vuelta = ListaPrecio.fromMap(Map<String, dynamic>.from(mapa));
      final rec = vuelta.columnas.firstWhere((c) => c.nombre == 'Detal');
      expect(rec.formula.modo, FormulaColumna.modoMultiplicador);
      expect(rec.formula.valor, 1.4);
    });

    test('los nombres reservados se reconocen como virtuales', () {
      expect(FormulaColumna.esNombreVirtual('__inicial_manual__'), isTrue);
      expect(FormulaColumna.esNombreVirtual('__fx__abc'), isTrue);
      expect(FormulaColumna.esNombreVirtual('Mayorista'), isFalse);
    });
  });
}
