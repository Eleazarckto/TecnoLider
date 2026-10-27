// Listas de precios: mejoras traídas de Brizuela (hasta 1.0.72).
//
// Adaptado de test/listas_precios_test.dart y test/lista_tasa_fija_test.dart
// de Brizuela (fusión a tres bandas, serialización de ida y vuelta, celdas
// manuales, repoblado, permisos) a cómo guarda las listas Tecno Líder (JSON
// con valores por nombre de columna y columnas virtuales __x__).
//
// La regla de oro: con los campos nuevos en su valor por defecto, una lista
// calcula y viaja EXACTAMENTE como en la app 1.0.17.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tecno_lider/main.dart';
import 'package:tecno_lider/reglas_porcentaje.dart';

Producto _p(String codigo,
        {double venta = 100,
        double costo = 50,
        int stock = 1,
        String nombre = '',
        String marca = 'Demo',
        String categoria = 'Accesorio',
        String padre = ''}) =>
    Producto(
      codigo: codigo,
      nombre: nombre.isEmpty ? 'Prod $codigo' : nombre,
      categoria: categoria,
      marca: marca,
      modelo: 'M',
      tipo: 'Nuevo',
      precioCosto: costo,
      precioVenta: venta,
      stockManual: stock,
      productoPadreCodigo: padre,
    );

ListaPrecio _lista({double pct = 10, bool bs = false, double tasa = 1}) =>
    ListaPrecio(
      id: 7,
      nombre: 'Accesorios',
      fechaCreacion: '2026-10-16',
      categoria: 'Accesorio',
      esEnBolivares: bs,
      tasaDelDia: tasa,
      porcentajeAdicional: pct,
      columnas: [ColumnaPrecio(nombre: 'Precio')],
    );

Usuario _u(String rol) =>
    Usuario(nombre: 'X', cedula: '1', correo: 'x@x.com', clave: '', rol: rol);

void main() {
  setUp(() {
    ConfigSistema.tasaCambio = 100;
  });
  tearDown(() {
    catalogoGlobal = [];
    usuarioSesion = null;
    invalidarStockListas();
  });

  group('con los valores por defecto todo es como en la 1.0.17', () {
    test('precio por defecto = venta × (1 + % adicional)', () {
      final l = _lista(pct: 15);
      expect(l.precioPorDefecto(_p('A', venta: 100)), 115);
      expect(precioPorDefectoEnLista(l, 100), 115);
    });

    test('en Bs, dos pasos con la tasa del sistema', () {
      final l = _lista(pct: 10, bs: true, tasa: 90);
      // USD 33,33 × 1,10 = 36,66 (redondeado) × 100 = 3.666
      expect(l.precioPorDefecto(_p('A', venta: 33.33)), 3666);
      expect(precioPorDefectoEnLista(l, 33.33), 3666);
    });

    test('una lista vieja (sin campos nuevos) se lee en modo manual', () {
      final l = ListaPrecio.fromMap({
        'id': 3, 'nombre': 'X', 'porcentaje_adicional': '20',
        'columnas': [{'nombre': 'Precio'}], 'items': []
      });
      expect(l.modoPrecios, 'manual');
      expect(l.esModoCosto, isFalse);
      expect(l.montoAdicionalDolares, 0);
      expect(l.redondearArriba, isFalse);
      expect(l.reglasPct, isEmpty);
      expect(l.tieneCuotas, isTrue);
      expect(l.porcentajePara(_p('A')), 20);
    });

    test('siguen viajando las columnas virtuales que lee la 1.0.17', () {
      final l = _lista();
      l.columnas.add(ColumnaPrecio(
          nombre: 'Cashea',
          formula: FormulaColumna(modo: FormulaColumna.modoPorcentaje, valor: 20)));
      l.items.add(ItemListaPrecio(
          producto: _p('A'),
          preciosPorColumna: {'Precio': 110, 'Cashea': 132},
          inicialManual: 30,
          pctInicialOverride: 40));
      final m = l.toMap();
      final cols = (m['columnas'] as List).map((c) => c['nombre'] as String);
      expect(cols.any((n) => n.startsWith('__fx__')), isTrue);
      final valores = ((m['items'] as List).first['valores'] as List)
          .map((v) => v['columna_nombre'])
          .toList();
      expect(valores, containsAll(['Precio', 'Cashea', '__inicial_manual__', '__pct_inicial__']));
      // Ida y vuelta.
      catalogoGlobal = [_p('A')];
      final v = ListaPrecio.fromMap(jsonDecode(jsonEncode(m)));
      expect(v.columnas.last.formula.modo, FormulaColumna.modoPorcentaje);
      expect(v.items.single.inicialManual, 30);
      expect(v.items.single.pctInicialOverride, 40);
    });
  });

  group('celdas fijadas a mano (es_manual)', () {
    test('ida y vuelta', () {
      catalogoGlobal = [_p('A')];
      final l = _lista();
      l.items.add(ItemListaPrecio(
          producto: _p('A'), preciosPorColumna: {'Precio': 99},
          columnasManuales: {'Precio'}));
      final v = ListaPrecio.fromMap(jsonDecode(jsonEncode(l.toMap())));
      expect(v.items.single.esManual('Precio'), isTrue);
      expect(v.items.single.esManual('precio'), isTrue); // sin mayúsculas
    });

    test('lo que guardó la app 1.0.17 (sin la bandera) no es manual', () {
      catalogoGlobal = [_p('A')];
      final v = ListaPrecio.fromMap({
        'id': 1, 'nombre': 'X', 'columnas': [{'nombre': 'Precio'}],
        'items': [
          {'producto_codigo': 'A', 'valores': [{'columna_nombre': 'Precio', 'precio': 5}]}
        ]
      });
      expect(v.items.single.esManual('Precio'), isFalse);
    });

    test('ninguna fórmula pisa una celda manual', () {
      final l = _lista();
      l.columnas.add(ColumnaPrecio(
          nombre: 'Mayor',
          formula: FormulaColumna(modo: FormulaColumna.modoPorcentaje, valor: -10)));
      l.items.addAll([
        ItemListaPrecio(producto: _p('A'), preciosPorColumna: {'Precio': 110, 'Mayor': 1},
            columnasManuales: {'Mayor'}),
        ItemListaPrecio(producto: _p('B'), preciosPorColumna: {'Precio': 110, 'Mayor': 1}),
      ]);
      l.aplicarFormulas(soloAutomaticas: false);
      expect(l.items[0].preciosPorColumna['Mayor'], 1);
      expect(l.items[1].preciosPorColumna['Mayor'], 90);
    });

    test('recalcular precios: respetar los fijados o rehacer todos', () {
      final l = _lista(pct: 10);
      l.items.addAll([
        ItemListaPrecio(producto: _p('A'), preciosPorColumna: {'Precio': 99},
            columnasManuales: {'Precio'}),
        ItemListaPrecio(producto: _p('B'), preciosPorColumna: {'Precio': 98}),
      ]);
      expect(l.recalcularPrecios(), 1);
      expect(l.items[0].preciosPorColumna['Precio'], 99);
      expect(l.items[1].preciosPorColumna['Precio'], 110);
      expect(l.recalcularPrecios(respetarManuales: false), 1);
      expect(l.items[0].preciosPorColumna['Precio'], 110);
      expect(l.items[0].esManual('Precio'), isFalse);
    });

    test('migración: marca solo lo que no es el precio por defecto, sin cambiar precios', () {
      final l = _lista(pct: 10);
      l.items.addAll([
        ItemListaPrecio(producto: _p('A'), preciosPorColumna: {'Precio': 110}),
        ItemListaPrecio(producto: _p('B'), preciosPorColumna: {'Precio': 120}),
      ]);
      expect(migrarMarcasManuales(l), 1);
      expect(l.items[0].esManual('Precio'), isFalse);
      expect(l.items[1].esManual('Precio'), isTrue);
      expect(l.items[1].preciosPorColumna['Precio'], 120);
      // Una vez con marcas, no se vuelve a migrar.
      expect(migrarMarcasManuales(l), 0);
    });

    test('migración en Bs: con la tasa de la lista y 1 Bs de tolerancia', () {
      final l = _lista(pct: 0, bs: true, tasa: 90);
      l.items.add(ItemListaPrecio(producto: _p('A', venta: 10), preciosPorColumna: {'Precio': 900.5}));
      expect(migrarMarcasManuales(l), 0);
    });
  });

  group('producto que no está en el catálogo de este equipo', () {
    test('se conserva (no se borra del servidor al guardar) pero no se muestra', () {
      catalogoGlobal = [_p('A')];
      final l = ListaPrecio.fromMap({
        'id': 1, 'nombre': 'X', 'columnas': [{'nombre': 'Precio'}],
        'items': [
          {'producto_codigo': 'A', 'stock_disponible': 3, 'valores': [{'columna_nombre': 'Precio', 'precio': 5}]},
          {'producto_codigo': 'ZZ', 'stock_disponible': 3, 'valores': [{'columna_nombre': 'Precio', 'precio': 7}]},
        ]
      });
      invalidarStockListas();
      expect(l.items.length, 2);
      expect(l.items.last.fueraDeCatalogo, isTrue);
      expect(l.itemsConStock.map((i) => i.producto.codigo), ['A']);
      final codigos = (l.toMap()['items'] as List).map((i) => i['producto_codigo']);
      expect(codigos, ['A', 'ZZ']);
      // Y ninguna fórmula lo recalcula desde un precio 0.
      l.columnas.add(ColumnaPrecio(
          nombre: 'Mayor', formula: FormulaColumna(modo: FormulaColumna.modoPorcentaje, valor: 5)));
      l.aplicarFormulas();
      expect(l.items.last.preciosPorColumna['Mayor'], isNull);
    });
  });

  group('fusión a tres bandas (Brizuela 1c84509)', () {
    ListaPrecio conItems(Map<String, double> precios, {double tasa = 200, bool fija = false}) {
      final l = _lista(bs: true, tasa: tasa)..tasaFija = fija;
      for (final e in precios.entries) {
        l.items.add(ItemListaPrecio(producto: _p(e.key), preciosPorColumna: {'Precio': e.value}));
      }
      return l;
    }

    test('lo que este equipo no tocó lo trae el servidor', () {
      final base = InstantaneaLista.de(conItems({'A': 10, 'B': 20}));
      final local = InstantaneaLista.de(conItems({'A': 11, 'B': 20}));
      final remota = InstantaneaLista.de(conItems({'A': 10, 'B': 25, 'C': 30}));
      final f = InstantaneaLista.fusionar(local: local, base: base, remota: remota).aLista();
      final precios = {for (final it in f.items) it.producto.codigo: it.preciosPorColumna['Precio']};
      expect(precios, {'A': 11, 'B': 25, 'C': 30});
    });

    test('un producto quitado acá se va; uno quitado allá sin editar acá, también', () {
      final base = InstantaneaLista.de(conItems({'A': 10, 'B': 20}));
      final local = InstantaneaLista.de(conItems({'B': 20}));
      final remota = InstantaneaLista.de(conItems({'A': 10}));
      final f = InstantaneaLista.fusionar(local: local, base: base, remota: remota).aLista();
      expect(f.items, isEmpty);
    });

    test('la cabecera se fusiona campo a campo (tasa fija)', () {
      final base = InstantaneaLista.de(conItems({}, tasa: 200));
      final local = InstantaneaLista.de(conItems({}, tasa: 155, fija: true));
      final remota = InstantaneaLista.de(conItems({}, tasa: 210));
      final f = InstantaneaLista.fusionar(local: local, base: base, remota: remota).aLista();
      expect(f.tasaFija, isTrue);
      expect(f.tasaDelDia, 155);
      final f2 = InstantaneaLista.fusionar(
              local: base, base: base, remota: remota)
          .aLista();
      expect(f2.tasaDelDia, 210);
    });

    test('la marca de manual viaja en la fusión', () {
      final b = conItems({'A': 10});
      final base = InstantaneaLista.de(b);
      b.items.single.marcarManual('Precio');
      final f = InstantaneaLista.fusionar(
              local: InstantaneaLista.de(b), base: base, remota: base)
          .aLista();
      expect(f.items.single.esManual('Precio'), isTrue);
    });

    test('adoptar conserva los objetos de ítem (los diálogos abiertos los usan)', () {
      final l = conItems({'A': 10});
      final it = l.items.single;
      l.adoptar(conItems({'A': 99, 'B': 1}));
      expect(identical(l.items.first, it), isTrue);
      expect(it.preciosPorColumna['Precio'], 99);
      expect(l.items.length, 2);
    });
  });

  group('repoblado único (poblarListaDesdeCatalogo)', () {
    test('conserva precios, agrega con stock, no toma variantes ni agotados', () {
      catalogoGlobal = [
        _p('A', stock: 1),
        _p('B', stock: 2, venta: 50),
        _p('B-1', stock: 3, padre: 'B'),
        _p('C', stock: 0),
        _p('TV', stock: 1, categoria: 'Televisor'),
      ];
      invalidarStockListas();
      final l = _lista(pct: 10);
      l.items.addAll([
        ItemListaPrecio(producto: catalogoGlobal[0], preciosPorColumna: {'Precio': 77}),
        // Agregado a mano, de otra categoría: se queda.
        ItemListaPrecio(producto: catalogoGlobal[4], preciosPorColumna: {'Precio': 300}),
        // Ya no está en el catálogo: sale.
        ItemListaPrecio(producto: _p('VIEJO'), preciosPorColumna: {'Precio': 1}),
      ]);
      final r = poblarListaDesdeCatalogo(l);
      final precios = {for (final it in l.items) it.producto.codigo: it.preciosPorColumna['Precio']};
      expect(precios, {'A': 77, 'B': 55, 'TV': 300});
      expect(r.agregados, 1);
      expect(r.eliminados, 1);
      expect(l.items.firstWhere((i) => i.producto.codigo == 'B').stockDisponible, 5);
    });

    test('con el catálogo vacío no toca nada', () {
      final l = _lista();
      l.items.add(ItemListaPrecio(producto: _p('A'), preciosPorColumna: {'Precio': 1}));
      expect(poblarListaDesdeCatalogo(l).sinCatalogo, isTrue);
      expect(l.items.length, 1);
    });
  });

  test('borrar una columna deja la lista coherente', () {
    final l = _lista();
    l.columnas.addAll([
      ColumnaPrecio(nombre: 'Base2'),
      ColumnaPrecio(
          nombre: 'Mayor',
          formula: FormulaColumna(
              modo: FormulaColumna.modoPorcentaje, origen: 'columna',
              columnaOrigen: 'Base2', valor: 5)),
    ]);
    l.items.add(ItemListaPrecio(
        producto: _p('A'),
        preciosPorColumna: {'Precio': 1, 'Base2': 2, 'Mayor': 3},
        columnasManuales: {'Base2'}));
    expect(eliminarColumnaDeLista(l, 'Base2'), ['Mayor']);
    expect(l.columnas.map((c) => c.nombre), ['Precio', 'Mayor']);
    expect(l.columnas.last.formula.esManual, isTrue);
    expect(l.items.single.preciosPorColumna, {'Precio': 1, 'Mayor': 3});
    expect(l.items.single.esManual('Base2'), isFalse);
  });

  group('desde el costo (vista previa; el que vale lo calcula el servidor)', () {
    test('% sobre costo, % especial por tipo y redondeo hacia arriba', () {
      final l = _lista(pct: 99)
        ..modoPrecios = 'costo'
        ..pctSobreCosto = 70
        ..reglasPct = [ReglaPorcentaje(nombre: 'Cornetas', palabras: ['corneta'], pct: 100)];
      expect(l.precioPorDefecto(_p('F', costo: 5)), 8.5);
      expect(l.precioPorDefecto(_p('C', costo: 13.15, nombre: 'Corneta JBL')), 26.3);
      l.redondearArriba = true;
      expect(l.precioPorDefecto(_p('C', costo: 13.15, nombre: 'Corneta JBL')), 27);
    });

    test('en modo manual las reglas no cuentan', () {
      final l = _lista(pct: 10)
        ..reglasPct = [ReglaPorcentaje(nombre: 'X', palabras: ['prod'], pct: 100)];
      expect(l.porcentajePara(_p('A')), 10);
    });

    test('los campos nuevos van y vuelven', () {
      final l = _lista()
        ..montoAdicionalDolares = 5
        ..pctSobreCosto = 25
        ..tasaBs = 950
        ..redondearArriba = true
        ..reglasPct = [ReglaPorcentaje(nombre: 'iPhone', marca: 'Apple', pct: 12)];
      final v = ListaPrecio.fromMap(jsonDecode(jsonEncode(l.toMap())));
      expect(v.montoAdicionalDolares, 5);
      expect(v.pctSobreCosto, 25);
      expect(v.tasaBs, 950);
      expect(v.redondearArriba, isTrue);
      expect(v.reglasPct.single.nombre, 'iPhone');
      expect(v.modoPrecios, 'manual');
    });
  });

  group('permisos', () {
    test('gestionan y ven los %: Dueño, Administrador, Gerente y Maestro', () {
      for (final rol in ['Dueño', 'Administrador', 'Gerente', 'Maestro']) {
        usuarioSesion = _u(rol);
        expect(puedeGestionarListasPrecios(), isTrue, reason: rol);
        expect(puedeVerPorcentajesDeListas(), isTrue, reason: rol);
      }
      for (final rol in ['Vendedor', 'Cajero', 'Técnico']) {
        usuarioSesion = _u(rol);
        expect(puedeGestionarListasPrecios(), isFalse, reason: rol);
        expect(puedeVerPorcentajesDeListas(), isFalse, reason: rol);
      }
      usuarioSesion = null;
      expect(puedeGestionarListasPrecios(), isFalse);
    });
  });
}
