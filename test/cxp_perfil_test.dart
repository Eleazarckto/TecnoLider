// Pruebas del perfil por acreedor de cuentas por pagar: agrupación por
// nombre, totales del resumen, facturas reconstruidas desde la
// bitácora, marcas de adjunto y reparto de un pago entre cuentas.
import 'package:flutter_test/flutter_test.dart';
import 'package:tecno_lider/cxp_perfil.dart';

class _C {
  final int id;
  final String nombre;
  final double resta;
  final double favor;
  _C(this.id, this.nombre, {this.resta = 0, this.favor = 0});
}

List<GrupoAcreedor<_C>> _agrupar(List<_C> l) => agruparPorAcreedor(
      l,
      nombre: (c) => c.nombre,
      id: (c) => c.id,
      saldoRestante: (c) => c.resta,
      saldoFavor: (c) => c.favor,
    );

void main() {
  group('Nombre normalizado', () {
    test('mayúsculas, acentos, signos y espacios no separan perfiles', () {
      expect(normalizarNombreAcreedor('  Maxí-2005 '), 'maxi 2005');
      expect(normalizarNombreAcreedor('MAXI   2005'), 'maxi 2005');
      expect(normalizarNombreAcreedor('Peña, C.A.'), 'pena c a');
    });
  });

  group('Agrupación por acreedor', () {
    test('dos cuentas de "Maxi 2005" quedan en un solo perfil', () {
      final g = _agrupar([
        _C(2, 'Maxi 2005', resta: 0),
        _C(6, 'MAXI 2005 ', resta: 500, favor: 0),
        _C(3, 'Tech Land', resta: 100),
      ]);
      expect(g.length, 2);
      final maxi = g.firstWhere((x) => x.clave == 'maxi 2005');
      expect(maxi.cuentas.map((c) => c.id), [2, 6]); // antigua → nueva
      expect(maxi.nombre, 'MAXI 2005'); // nombre de la más nueva
      expect(maxi.deuda, 500);
    });

    test('orden: con deuda (mayor primero), sólo a favor, saldados', () {
      final g = _agrupar([
        _C(1, 'Saldado'),
        _C(2, 'Favor chico', favor: 10),
        _C(3, 'Debe poco', resta: 50),
        _C(4, 'Favor grande', favor: 90),
        _C(5, 'Debe mucho', resta: 900),
      ]);
      expect(g.map((x) => x.nombre), [
        'Debe mucho', 'Debe poco', 'Favor grande', 'Favor chico', 'Saldado',
      ]);
    });

    test('resumen: deuda total, saldo a favor total y neto', () {
      final g = _agrupar([
        _C(1, 'A', resta: 300),
        _C(2, 'a', favor: 50), // mismo acreedor que el anterior
        _C(3, 'B', favor: 120),
        _C(4, 'C', resta: 80),
      ]);
      final r = resumirAcreedores(g);
      expect(r.acreedores, 3);
      expect(r.deudaTotal, 380);
      expect(r.favorTotal, 170);
      expect(r.conDeuda, 2);
      expect(r.conFavor, 2);
      expect(r.neto, 210);
    });
  });

  group('Facturas desde la bitácora', () {
    const notas = 'mercancía\n'
        '[03/09/2026] +\$3,450.00 (aplicado \$493.75 de saldo a favor)\n'
        '[05/09/2026] +\$3,000.00 — repuestos [[comp:17]]\n'
        '[[favor:12.50]]';

    test('original = total − aumentos, con el texto libre como concepto', () {
      final f = extraerFacturas(cuentaId: 6, montoTotal: 11956.25, notas: notas);
      expect(f.length, 3);
      expect(f[0].esOriginal, isTrue);
      expect(f[0].monto, closeTo(5506.25, 0.001));
      expect(f[0].concepto, 'mercancía');
      expect(f[1].fecha, '03/09/2026');
      expect(f[1].monto, 3450);
      expect(f[1].aplicadoDeFavor, 493.75);
      expect(f[1].concepto, '');
      expect(f[1].lineaNotas, 1);
      expect(f[2].concepto, 'repuestos');
      expect(f[2].comprobantes, [17]);
    });

    test('cuenta sin aumentos: una sola factura por el total', () {
      final f = extraerFacturas(cuentaId: 1, montoTotal: 1000, notas: '');
      expect(f.length, 1);
      expect(f.first.monto, 1000);
      expect(f.first.esOriginal, isTrue);
    });
  });

  group('Marcas de adjunto', () {
    test('agregar, leer y quitar', () {
      var t = agregarMarcaComprobante('[01/10/2026] +\$5.00', 3);
      t = agregarMarcaComprobante(t, 9);
      expect(leerMarcasComprobante(t), [3, 9]);
      expect(quitarMarcasComprobante(t), '[01/10/2026] +\$5.00');
      expect(agregarMarcaComprobante(null, 4), '[[comp:4]]');
    });

    test('los pagos toman el adjunto de sus notas', () {
      final p = extraerPagos(cuentaId: 1, pagos: [
        {'monto': '100', 'fecha': '01/10/2026', 'metodo': 'Zelle',
          'notas': '[[comp:21]]'},
        {'monto': 50, 'fecha': '02/10/2026', 'metodo': 'Efectivo \$',
          'notas': null},
      ], cuotasPagadas: [(1, 25.0, '03/10/2026')]);
      expect(p.length, 3);
      expect(p[0].comprobantes, [21]);
      expect(p[1].comprobantes, isEmpty);
      expect(p[2].esCuota, isTrue);
      final orden = ordenarPorFechaDesc(p, (x) => x.fecha);
      expect(orden.map((x) => x.monto), [25, 50, 100]);
    });
  });

  group('Reparto de un pago', () {
    test('cubre primero las cuentas más antiguas', () {
      final t = repartirPago([(1, 100), (2, 300)], 250, idExcedente: 2);
      expect(t.map((x) => (x.cuentaId, x.monto)), [(1, 100.0), (2, 150.0)]);
    });

    test('lo que sobra queda a favor en la cuenta más nueva', () {
      final t = repartirPago([(1, 100), (2, 0), (3, 50)], 400, idExcedente: 3);
      expect(t.map((x) => (x.cuentaId, x.monto)), [(1, 100.0), (3, 300.0)]);
      final total = t.fold(0.0, (s, x) => s + x.monto);
      expect(total, 400);
    });

    test('sin deuda pendiente todo va a la cuenta principal', () {
      final t = repartirPago([(1, 0)], 75, idExcedente: 1);
      expect(t.single.monto, 75);
    });
  });
}
