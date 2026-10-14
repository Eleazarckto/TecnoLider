// Pruebas de la lógica pura agregada para: billetera semanal de
// comisiones, calculadora rápida, pago por lote de la financiadora y
// cobros de servicio técnico.
import 'package:flutter_test/flutter_test.dart';
import 'package:tecno_lider/main.dart';
import 'package:tecno_lider/cuenta_financiadora.dart';

void main() {
  group('Semana de comisiones (lunes a domingo)', () {
    test('inicio y fin de semana', () {
      // 14/10/2026 es miércoles.
      final d = DateTime(2026, 10, 14, 15, 30);
      expect(inicioSemanaComisiones(d), DateTime(2026, 10, 12));
      expect(finSemanaComisiones(d), DateTime(2026, 10, 18));
      // El lunes es su propio inicio y el domingo cierra la semana.
      expect(inicioSemanaComisiones(DateTime(2026, 10, 12)), DateTime(2026, 10, 12));
      expect(inicioSemanaComisiones(DateTime(2026, 10, 18, 23, 59)),
          DateTime(2026, 10, 12));
    });

    test('semana que cruza de mes y de año', () {
      expect(inicioSemanaComisiones(DateTime(2026, 11, 1)), DateTime(2026, 10, 26));
      expect(inicioSemanaComisiones(DateTime(2027, 1, 2)), DateTime(2026, 12, 28));
    });

    test('agrupar por semana ordena de la más reciente a la más vieja', () {
      final fechas = [
        DateTime(2026, 10, 5, 10),  // semana del 05/10
        DateTime(2026, 10, 13, 9),  // semana del 12/10
        DateTime(2026, 10, 11, 18), // domingo → semana del 05/10
        DateTime(2026, 10, 18, 20), // domingo → semana del 12/10
      ];
      final g = agruparPorSemana<DateTime>(fechas, (d) => d);
      expect(g.keys.toList(), [DateTime(2026, 10, 12), DateTime(2026, 10, 5)]);
      expect(g[DateTime(2026, 10, 12)], [DateTime(2026, 10, 18, 20), DateTime(2026, 10, 13, 9)]);
      expect(g[DateTime(2026, 10, 5)]!.length, 2);
    });

    test('etiqueta legible', () {
      expect(etiquetaSemanaComisiones(DateTime(2026, 10, 12)),
          'Lun 12/10 – Dom 18/10/2026');
    });
  });

  group('Calculadora', () {
    double? ev(String s) => evaluarExpresionCalculadora(s);
    test('operaciones básicas y precedencia', () {
      expect(ev('2+3×4'), 14);
      expect(ev('(2+3)×4'), 20);
      expect(ev('10÷4'), 2.5);
      expect(ev('7−10'), -3);
      expect(ev('-5+2'), -3);
      expect(ev('1,5+1.5'), 3);
    });
    test('porcentaje como calculadora de mano', () {
      expect(ev('200+10%'), closeTo(220, 1e-9));
      expect(ev('200-10%'), closeTo(180, 1e-9));
      expect(ev('200×10%'), closeTo(20, 1e-9));
      expect(ev('50%'), closeTo(0.5, 1e-9));
      expect(ev('100+(50+50)%'), closeTo(200, 1e-9));
    });
    test('expresiones inválidas o incompletas devuelven null', () {
      expect(ev(''), isNull);
      expect(ev('2+'), isNull);
      expect(ev('(2+3'), isNull);
      expect(ev('5÷0'), isNull);
      expect(ev('abc'), isNull);
    });
    test('formato del resultado', () {
      expect(formatoResultadoCalculadora(12), '12');
      expect(formatoResultadoCalculadora(12.5), '12.5');
      expect(formatoResultadoCalculadora(1 / 3), '0.333333');
    });
  });

  group('Pago por lote de la financiadora', () {
    EquipoFinanciado eq(String imei, double deuda, {double abonado = 0}) =>
        EquipoFinanciado(financiadora: 'Krece', nroFactura: 'F1', base: deuda,
            imei: imei)
          ..deuda = deuda
          ..abonado = abonado;

    test('pago exacto cubre cada saldo', () {
      final e = [eq('1', 100), eq('2', 50, abonado: 20), eq('3', 80)];
      expect(repartirPagoEntreEquipos(e, 210), [100, 30, 80]);
    });
    test('pago menor deja a los últimos parciales', () {
      final e = [eq('1', 100), eq('2', 50), eq('3', 80)];
      expect(repartirPagoEntreEquipos(e, 120), [100, 20, 0]);
    });
    test('excedente va al último (sobrepago visible)', () {
      final e = [eq('1', 100), eq('2', 50)];
      final r = repartirPagoEntreEquipos(e, 160);
      expect(r, [100, 60]);
      expect(r.fold<double>(0, (t, x) => t + x), 160);
    });
    test('lista vacía', () {
      expect(repartirPagoEntreEquipos([], 50), isEmpty);
    });
  });

  group('Cobros de servicio técnico', () {
    test('estado del pago', () {
      expect(estadoPagoServicio(40, 0), 'Pendiente');
      expect(estadoPagoServicio(40, 15), 'Abonado');
      expect(estadoPagoServicio(40, 40), 'Pagado');
      expect(estadoPagoServicio(40, 39.999), 'Pagado');
    });

    test('los cobros y la tienda sobreviven el viaje por __META__', () {
      final s = ServicioTecnico(
        id: 7, monto: 40, abono: 30, fecha: DateTime(2026, 10, 10, 9),
        nombreCliente: 'Cliente', marca: 'Tecno', modelo: 'Spark',
        descripcion: 'Cambio de pantalla', tienda: 'Tecno Líder Principal',
        pagos: [
          PagoServicioTecnico(fecha: DateTime(2026, 10, 10, 9, 5),
              metodo: 'Pago Móvil', moneda: 'Bs', monto: 3650, tasa: 365,
              montoUsd: 10, referencia: '123456', cedulaPagador: 'V12345678',
              telefonoPagador: '04141234567'),
          PagoServicioTecnico(fecha: DateTime(2026, 10, 12, 16),
              metodo: 'Efectivo \$', moneda: 'USD', monto: 20, tasa: 365,
              montoUsd: 20),
        ],
      );
      final leido = ServicioTecnico.fromMap({...s.toMap(), 'id': 7});
      expect(leido.tienda, 'Tecno Líder Principal');
      expect(leido.descripcion, 'Cambio de pantalla');
      expect(leido.pagos.length, 2);
      expect(leido.pagos.first.esBs, isTrue);
      expect(leido.pagos.first.referencia, '123456');
      expect(leido.pagos.first.cedulaPagador, 'V12345678');
      expect(leido.cobradoUsd, 30);
      expect(leido.estadoPago, 'Abonado');
    });

    test('pagado se lee aunque el backend lo mande como string', () {
      final m = ServicioTecnico(monto: 10, abono: 10, pagado: true,
          fecha: DateTime(2026, 8, 31)).toMap();
      m['pagado'] = '1';
      expect(ServicioTecnico.fromMap(m).pagado, isTrue);
    });

    test('ingresos por rango y tienda (incluye abonos viejos sin detalle)', () {
      final nuevo = ServicioTecnico(monto: 40, fecha: DateTime(2026, 10, 1),
          tienda: 'A', pagos: [
            PagoServicioTecnico(fecha: DateTime(2026, 10, 2, 10), metodo: 'Zelle',
                moneda: 'USD', monto: 15, tasa: 0, montoUsd: 15),
            PagoServicioTecnico(fecha: DateTime(2026, 10, 20, 10), metodo: 'Zelle',
                moneda: 'USD', monto: 25, tasa: 0, montoUsd: 25, tienda: 'B'),
          ]);
      final viejo = ServicioTecnico(monto: 35, abono: 35, pagado: true,
          fecha: DateTime(2026, 10, 5));
      final todos = cobrosServicioEnRango([nuevo, viejo],
          DateTime(2026, 10, 1), DateTime(2026, 10, 31));
      expect(todos.length, 3);
      expect(todos.fold<double>(0, (t, f) => t + f.pago.montoUsd), 75);
      expect(todos.where((f) => f.pago.metodo == 'Sin detalle').length, 1);

      final soloA = cobrosServicioEnRango([nuevo, viejo],
          DateTime(2026, 10, 1), DateTime(2026, 10, 31), tienda: 'A');
      expect(soloA.length, 1);
      expect(soloA.first.pago.montoUsd, 15);

      final primeraQuincena = cobrosServicioEnRango([nuevo, viejo],
          DateTime(2026, 10, 1), DateTime(2026, 10, 15));
      expect(primeraQuincena.length, 2);
    });
  });
}
