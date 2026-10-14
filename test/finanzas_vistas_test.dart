// Los apartados nuevos de Costos y Finanzas se dibujan sin desbordes en
// teléfono y en tablet.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tecno_lider/finanzas_tienda.dart';
import 'package:tecno_lider/main.dart';

void main() {
  final desde = DateTime(2026, 10, 1);
  final hasta = DateTime(2026, 10, 31);
  final facturas = [
    FacturaCF(
      nroFactura: 'F1',
      tienda: 'Tecno Líder Principal',
      fecha: DateTime(2026, 10, 2),
      equipos: const [
        EquipoVendidoCF(costo: 100, precioContado: 120, precioFinanciadora: 140),
      ],
      pagos: const [
        PagoClienteCF(monto: 3500, enBolivares: true, tasa: 87.5,
            esInicial: true, financiadora: 'Krece'),
      ],
    ),
    FacturaCF(
      nroFactura: 'F2',
      tienda: 'Geo Cell',
      fecha: DateTime(2026, 10, 3),
      equipos: const [EquipoVendidoCF(costo: 80, precioContado: 100)],
      pagos: const [PagoClienteCF(monto: 100, enBolivares: false)],
    ),
  ];
  final gasto = GastoCF(id: 'g1', fecha: DateTime(2026, 10, 2),
      tienda: 'Geo Cell', categoria: 'Gastos fijos',
      concepto: 'Alquiler del local con nombre bastante largo', monto: 50,
      registradoPor: 'Dueño');
  final pago = PagoNomina(id: 'p1', empleado: 'Ana', monto: 40,
      fechaPago: DateTime(2026, 10, 15), registradoPor: 'Dueño',
      registradoEn: DateTime(2026, 10, 15, 10));
  final config = <String, dynamic>{
    claveGastosMes(2026, 10): [gasto.toJson()],
    claveNominaPagosMes(2026, 10): [pago.toJson()],
    claveNominaEmpleados: [EmpleadoNomina(nombre: 'Ana', sueldo: 40).toJson()],
  };

  for (final tam in const [Size(360, 740), Size(1024, 1366)]) {
    for (final cual in ['equilibrio', 'ganancia', 'flujo', 'gastos', 'nomina']) {
      testWidgets('$cual se dibuja en ${tam.width.toInt()}px', (t) async {
        t.view.physicalSize = tam;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await t.pumpWidget(MaterialApp(
          home: Scaffold(
            body: panelFinanzasDePrueba(cual,
                facturas: facturas, config: config,
                desde: desde, hasta: hasta),
          ),
        ));
        await t.pump();
        expect(t.takeException(), isNull);
      });
    }
  }
}
