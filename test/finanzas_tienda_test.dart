// Pruebas de la lógica de Costos y Finanzas: ganancia real vs
// diferencial cambiario, balance neto, equilibrio diario y flujo de caja.
import 'package:flutter_test/flutter_test.dart';
import 'package:tecno_lider/finanzas_tienda.dart';

FacturaCF _fac(String tienda, DateTime fecha, List<EquipoVendidoCF> eq,
        List<PagoClienteCF> pagos, {String nro = 'F1'}) =>
    FacturaCF(nroFactura: nro, tienda: tienda, fecha: fecha,
        equipos: eq, pagos: pagos);

void main() {
  const tasasIguales = TasasCF(tasaBcv: 100, tasaDivisa: 100);

  group('Ganancia real vs diferencial cambiario', () {
    test('Ejemplo del dueño: costo 100, contado 120, financiado 140', () {
      // Krece (sin comisión): base 140, el cliente pone $40 de inicial,
      // Krece debe $100. Con tasas iguales entra 140 en total.
      final f = _fac('T1', DateTime(2026, 10, 1), [
        const EquipoVendidoCF(costo: 100, precioContado: 120,
            precioFinanciadora: 140),
      ], [
        const PagoClienteCF(monto: 40, enBolivares: false,
            esInicial: true, financiadora: 'Krece'),
      ]);
      final v = analizarFactura(f, tasasIguales);
      expect(v.financiadoBcv, 100);
      expect(v.ingresoEnDivisa, 140);
      expect(v.gananciaReal, 20);           // no 40
      expect(v.diferencialCambiario, 20);
      expect(v.gananciaTotal, 40);
    });

    test('Krece paga en Bs a BCV: \$1000 convertidos son 850', () {
      const t = TasasCF(tasaBcv: 85, tasaDivisa: 100);
      expect(t.factorBcvADivisa, closeTo(0.85, 1e-9));
      // Base 1100, inicial $100 en divisas → Krece debe 1000 BCV = 850.
      final f = _fac('T1', DateTime(2026, 10, 1), [
        const EquipoVendidoCF(costo: 700, precioContado: 850,
            precioFinanciadora: 1100),
      ], [
        const PagoClienteCF(monto: 100, enBolivares: false,
            financiadora: 'Krece'),
      ]);
      final v = analizarFactura(f, t);
      expect(v.financiadoBcv, 1000);
      expect(v.financiadoEnDivisa, closeTo(850, 1e-9));
      // 100 inicial + 850 − 850 contado = 100 de diferencial.
      expect(v.diferencialCambiario, closeTo(100, 1e-9));
      expect(v.gananciaReal, 150);
    });

    test('Inicial en Bs: se usa la tasa histórica para la deuda y la '
        'tasa divisa para lo cobrado', () {
      const t = TasasCF(tasaBcv: 100, tasaDivisa: 125);
      final f = _fac('T1', DateTime(2026, 10, 1), [
        const EquipoVendidoCF(costo: 100, precioContado: 120,
            precioFinanciadora: 150),
      ], [
        // 5000 Bs a tasa 100 = $50 BCV de inicial.
        const PagoClienteCF(monto: 5000, enBolivares: true, tasa: 100,
            esInicial: true, financiadora: 'Krece'),
      ]);
      final v = analizarFactura(f, t);
      expect(v.cobradoBs, 5000);
      expect(v.cobradoEnDivisa, 40);        // 5000 / 125
      expect(v.financiadoBcv, 100);         // 150 − 50
      expect(v.financiadoEnDivisa, 80);     // 100 × 100/125
      expect(v.diferencialCambiario, 0);    // 40 + 80 − 120
    });

    test('Contado en divisas: sin diferencial', () {
      final f = _fac('T1', DateTime(2026, 10, 1), [
        const EquipoVendidoCF(costo: 100, precioContado: 120),
      ], [const PagoClienteCF(monto: 120, enBolivares: false)]);
      final v = analizarFactura(f, tasasIguales);
      expect(v.esFinanciada, isFalse);
      expect(v.financiadoBcv, 0);
      expect(v.gananciaReal, 20);
      expect(v.diferencialCambiario, 0);
    });

    test('Cashea descuenta su comisión de lo que paga', () {
      final f = _fac('T1', DateTime(2026, 10, 1), [
        const EquipoVendidoCF(costo: 500, precioContado: 600,
            precioFinanciadora: 800),
      ], [
        const PagoClienteCF(monto: 200, enBolivares: false,
            financiadora: 'Cashea'),
      ]);
      final v = analizarFactura(f, tasasIguales);
      expect(v.financiadoBcv, 538.88); // mismo número que el reporte
    });

    test('Agrupar por tienda y balance neto', () {
      final ventas = [
        analizarFactura(_fac('A', DateTime(2026, 10, 1), [
          const EquipoVendidoCF(costo: 100, precioContado: 120),
        ], [const PagoClienteCF(monto: 120, enBolivares: false)]),
            tasasIguales),
        analizarFactura(_fac('B', DateTime(2026, 10, 1), [
          const EquipoVendidoCF(costo: 100, precioContado: 120,
              precioFinanciadora: 140),
        ], [
          const PagoClienteCF(monto: 40, enBolivares: false,
              financiadora: 'Krece'),
        ]), tasasIguales),
      ];
      final g = agruparGanancias(ventas, (v) => v.tienda);
      expect(g['A']!.gananciaReal, 20);
      expect(g['B']!.diferencialCambiario, 20);
      // Balance B: 40 cobrado + 100 financiado − 100 costo − 30 gastos.
      expect(g['B']!.balanceNeto(30), 10);
      expect(totalGanancias(ventas).gananciaTotal, 60);
    });
  });

  group('Precio en lista de la financiadora', () {
    final listas = [
      (nombre: 'LISTA INTERNA', financiadora: 'KRECE.',
          precios: {'A002': 151.0}),
      (nombre: 'KRECE', financiadora: '', precios: {'A002': 149.86}),
      (nombre: 'CASHEA TELEFONOS', financiadora: '',
          precios: {'A002': 212.4}),
    ];
    test('Prefiere la lista con el nombre de la financiadora', () {
      expect(precioEnListaFinanciadora(listas, 'Krece', 'A002'), 149.86);
    });
    test('La lista usada al facturar manda', () {
      expect(precioEnListaFinanciadora(listas, 'Krece', 'A002',
          nombreLista: 'LISTA INTERNA'), 151.0);
    });
    test('Nombre que contiene la financiadora', () {
      expect(precioEnListaFinanciadora(listas, 'Cashea', 'A002'), 212.4);
      expect(precioEnListaFinanciadora(listas, 'Weppa', 'A002'), isNull);
    });
  });

  group('Equilibrio diario', () {
    test('"Hoy generamos 200, gastamos 50, quedamos en 150"', () {
      final v = analizarFactura(_fac('A', DateTime(2026, 10, 2), [
        const EquipoVendidoCF(costo: 300, precioContado: 500),
      ], [const PagoClienteCF(monto: 500, enBolivares: false)]),
          tasasIguales);
      final gastos = [
        GastoCF(id: '1', fecha: DateTime(2026, 10, 2), tienda: 'A',
            monto: 50),
        // 10.000 Bs a tasa 100 = $100 de alquiler el día 5.
        GastoCF(id: '2', fecha: DateTime(2026, 10, 5), tienda: 'A',
            monto: 10000, moneda: monedaBs, tasa: 100,
            categoria: 'Gastos fijos'),
      ];
      final e = calcularEquilibrio(tienda: 'A', ventas: [v], gastos: gastos);
      expect(e.dias.length, 2);
      expect(e.dias.first.resultado, 150);
      expect(e.dias.last.acumulado, 50);
      expect(e.totalGastos, 150);
      expect(e.enPositivo, isTrue);
      expect(e.diaCubreGastos, DateTime(2026, 10, 2));
      expect(gastosPorCategoria(gastos)['Gastos fijos'], 100);
    });

    test('Tienda que todavía no cubre sus gastos', () {
      final e = calcularEquilibrio(tienda: 'B', ventas: const [], gastos: [
        GastoCF(id: '1', fecha: DateTime(2026, 10, 1), monto: 80),
      ]);
      expect(e.enPositivo, isFalse);
      expect(e.faltante, 80);
      expect(e.diaCubreGastos, isNull);
    });
  });

  group('Flujo de caja', () {
    test('Separa \$ y Bs por tienda y consolida', () {
      final d = DateTime(2026, 10, 1);
      final f = calcularFlujoCaja([
        MovimientoCaja(fecha: d, tienda: 'A', concepto: 'Ventas',
            entrada: true, moneda: monedaUsd, monto: 100),
        MovimientoCaja(fecha: d, tienda: 'A', concepto: 'Ventas',
            entrada: true, moneda: monedaBs, monto: 5000),
        MovimientoCaja(fecha: d, tienda: 'A', concepto: 'Gastos',
            entrada: false, moneda: monedaBs, monto: 1000),
        MovimientoCaja(fecha: d, tienda: 'B', concepto: 'Nómina',
            entrada: false, moneda: monedaUsd, monto: 30),
      ]);
      expect(f.porTienda['A']!.netoUsd, 100);
      expect(f.porTienda['A']!.netoBs, 4000);
      expect(f.porTienda['A']!.porConcepto['Ventas']!.entradasBs, 5000);
      expect(f.consolidado.netoUsd, 70);
      expect(f.consolidado.netoBs, 4000);
      expect(f.consolidado.netoEquivUsd(100), 110);
    });
  });

  group('Nómina y persistencia JSON', () {
    test('Agregar usuarios sin duplicar', () {
      final emp = [EmpleadoNomina(usuarioId: 1, nombre: 'Ana', sueldo: 50)];
      final n = agregarUsuariosANomina(emp, [
        (id: 1, nombre: 'Ana', rol: 'Vendedor', tienda: 'A', sueldo: 40.0),
        (id: 2, nombre: 'Luis', rol: 'Cajero', tienda: 'B', sueldo: 30.0),
      ]);
      expect(n, 1);
      expect(emp.length, 2);
      expect(emp.first.sueldo, 50); // no se pisa lo ya configurado
      expect(emp.last.tienda, 'B');
    });

    test('Pago de nómina guarda a quién y quién registró', () {
      final p = PagoNomina(id: 'x', empleado: 'Luis', usuarioId: 2,
          monto: 3000, moneda: monedaBs, tasa: 100,
          fechaPago: DateTime(2026, 10, 15), registradoPor: 'Dueño',
          registradoEn: DateTime(2026, 10, 15, 9, 30));
      final q = PagoNomina.fromJson(p.toJson());
      expect(q.empleado, 'Luis');
      expect(q.registradoPor, 'Dueño');
      expect(q.registradoEn, DateTime(2026, 10, 15, 9, 30));
      expect(q.montoUsd, 30);
      expect(totalPagadoPorEmpleado([p, q])['Luis'], 60);
    });

    test('Gasto ida y vuelta', () {
      final g = GastoCF(id: 'g', fecha: DateTime(2026, 10, 3), tienda: 'A',
          categoria: 'Administrativo', concepto: 'Papelería', monto: 12.5);
      final h = GastoCF.fromJson(g.toJson());
      expect(h.fecha, DateTime(2026, 10, 3));
      expect(h.categoria, 'Administrativo');
      expect(h.montoUsd, 12.5);
      expect(claveGastosMes(2026, 3), 'cf_gastos_2026_03');
    });
  });
}
