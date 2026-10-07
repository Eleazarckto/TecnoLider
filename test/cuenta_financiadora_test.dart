// Pruebas de la aritmética de la cuenta con la financiadora
// (deuda por equipo, comisiones y aplicación de abonos).
import 'package:flutter_test/flutter_test.dart';
import 'package:tecno_lider/cuenta_financiadora.dart';

EquipoFinanciado _eq(String fin, String nro, double base, {String imei = ''}) =>
    EquipoFinanciado(financiadora: fin, nroFactura: nro, base: base,
        imei: imei, codigo: 'C-$imei', marca: 'Samsung', modelo: 'A15');

void main() {
  group('Deuda por equipo', () {
    test('Weppa: (Base − Inicial) − 3.5%', () {
      final e = _eq('Weppa', 'F1', 500);
      calcularDeudaFactura([e], 100);
      expect(e.inicial, 100);
      expect(e.comision, 14);
      expect(e.deuda, 386);
      expect(e.saldo, 386);
    });

    test('Cashea: ejemplo del dueño (Base 800, Inicial 200)', () {
      final e = _eq('Cashea', 'F1', 800);
      calcularDeudaFactura([e], 200);
      expect(e.comision, 61.12);
      expect(e.deuda, 538.88);
    });

    test('Krece no cobra comisión', () {
      final e = _eq('Krece', 'F1', 300);
      calcularDeudaFactura([e], 50);
      expect(e.comision, 0);
      expect(e.deuda, 250);
    });

    test('la inicial se reparte proporcional y la suma cuadra al centavo', () {
      final a = _eq('Krece', 'F1', 200, imei: '1');
      final b = _eq('Krece', 'F1', 100, imei: '2');
      calcularDeudaFactura([a, b], 100);
      expect(a.inicial, closeTo(66.67, 0.001));
      expect(b.inicial, closeTo(33.33, 0.001));
      expect(a.inicial + b.inicial, closeTo(100, 0.0001));
      expect(a.deuda + b.deuda, closeTo(200, 0.0001));
    });

    test('una inicial mayor a la base no resta deuda a otros equipos', () {
      final e = _eq('Krece', 'F1', 100);
      calcularDeudaFactura([e], 150);
      expect(e.deuda, 0);
    });
  });

  group('Aplicación de abonos', () {
    test('un abono con IMEI se resta SOLO de ese equipo', () {
      final a = _eq('Krece', 'F1', 200, imei: '111');
      final b = _eq('Krece', 'F1', 100, imei: '222');
      calcularDeudaFactura([a, b], 0);
      final sobran = aplicarPagosAEquipos([a, b], [
        const PagoFinanciadora(financiadora: 'Krece', monto: 50,
            nroFactura: 'F1', imei: '222'),
      ]);
      expect(sobran, isEmpty);
      expect(a.abonado, 0);
      expect(a.saldo, 200);
      expect(b.abonado, 50);
      expect(b.saldo, 50);
    });

    test('un abono solo con factura llena los equipos en orden', () {
      final a = _eq('Krece', 'F1', 200, imei: '111');
      final b = _eq('Krece', 'F1', 100, imei: '222');
      calcularDeudaFactura([a, b], 0);
      aplicarPagosAEquipos([a, b], [
        const PagoFinanciadora(financiadora: 'Krece', monto: 250,
            nroFactura: 'F1'),
      ]);
      expect(a.saldo, 0);
      expect(b.saldo, 50);
    });

    test('el sobrepago queda como saldo negativo (no se pierde)', () {
      final a = _eq('Krece', 'F1', 100, imei: '111');
      calcularDeudaFactura([a], 0);
      aplicarPagosAEquipos([a], [
        const PagoFinanciadora(financiadora: 'Krece', monto: 120,
            nroFactura: 'F1', imei: '111'),
      ]);
      expect(a.saldo, -20);
    });

    test('el abono se aplica aunque su fecha sea de otro mes', () {
      // Bug original: el pago de octubre de un equipo de septiembre
      // no se restaba en septiembre.
      final a = _eq('Cashea', 'F9', 800, imei: '999');
      calcularDeudaFactura([a], 200);
      aplicarPagosAEquipos([a], [
        PagoFinanciadora(financiadora: 'Cashea', monto: 538.88,
            nroFactura: 'F9', imei: '999', fecha: DateTime(2026, 10, 5)),
      ]);
      expect(a.saldo, 0);
    });

    test('pagos sin vínculo o de facturas ajenas se devuelven sin aplicar', () {
      final a = _eq('Krece', 'F1', 100, imei: '111');
      calcularDeudaFactura([a], 0);
      final sobran = aplicarPagosAEquipos([a], [
        const PagoFinanciadora(financiadora: 'Krece', monto: 10),
        const PagoFinanciadora(financiadora: 'Krece', monto: 20,
            nroFactura: 'OTRA'),
      ]);
      expect(sobran.length, 2);
      expect(a.abonado, 0);
    });

    test('redondeo: varios abonos de centavos no dejan residuos', () {
      final a = _eq('Krece', 'F1', 0.3, imei: '1');
      calcularDeudaFactura([a], 0);
      aplicarPagosAEquipos([a], [
        const PagoFinanciadora(financiadora: 'Krece', monto: 0.1,
            nroFactura: 'F1', imei: '1'),
        const PagoFinanciadora(financiadora: 'Krece', monto: 0.2,
            nroFactura: 'F1', imei: '1'),
      ]);
      expect(a.saldo, 0);
    });
  });

  group('Marca del equipo en las notas', () {
    test('se escribe, se lee y no se muestra', () {
      final notas = escribirMarcaEquipoPago('Transferencia BDV', 'F-10', '3569');
      final m = leerMarcaEquipoPago(notas);
      expect(m, isNotNull);
      expect(m!.nroFactura, 'F-10');
      expect(m.imei, '3569');
      expect(notasPagoVisibles(notas), 'Transferencia BDV');
    });

    test('notas sin marca devuelven null', () {
      expect(leerMarcaEquipoPago('pago normal'), isNull);
    });
  });
}
