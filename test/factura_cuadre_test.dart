// Pruebas de la facturación oct-2026 (lib/factura_cuadre.dart y lo que
// usa la factura): cuadre mixto de TecnoLíder (contado por producto +
// inicial de las líneas financiadas), moneda y tasa BCV por pago,
// vuelto, FPB con deuda propuesta, factura impresa con solo lo pagado y
// la factura de una cuenta por cobrar. El servidor repite el cuadre:
// backend/tests/factura_cuadre_test.php tiene los mismos casos.

import 'package:flutter_test/flutter_test.dart';

import 'package:tecno_lider/factura_cuadre.dart';
import 'package:tecno_lider/main.dart';

LineaCuadre contado(double div, {double? bcv, String ref = 'FORRO'}) =>
    LineaCuadre(ref: ref, nombre: ref, precioDivisa: div, precioBcv: bcv);

LineaCuadre financiada(double div, double? inicial,
        {double precioFin = 0, String ref = '351111'}) =>
    LineaCuadre(ref: ref, nombre: 'Redmi 13', esEquipo: true,
        financiada: true, precioDivisa: div,
        precioFinanciadora: precioFin, inicial: inicial);

PagoCuadre pago(String metodo, double monto, {bool vuelto = false}) =>
    PagoCuadre(monto: monto, moneda: monedaDeMetodo(metodo),
        esVuelto: vuelto, metodo: metodo);

CuadreFactura cuadre(List<LineaCuadre> l, List<PagoCuadre> p,
        {double tasa = 100, bool fpb = false}) =>
    CuadreFactura.calcular(lineas: l, pagos: p, tasa: tasa, fpb: fpb);

void main() {
  group('Moneda de cada método', () {
    test('es la misma regla que esMetodoEnBolivares', () {
      for (final m in [
        'Pago Móvil', 'Pago Movil', 'Efectivo Bs', 'Transferencia',
        'Punto de venta', 'Punto de Venta BDV', 'Transferencia Bs',
        'Efectivo Bs.', 'Biopago Bs', 'Zelle', 'Divisas', 'Efectivo \$',
        'Binance', 'Cashea', 'Transferencia USD', 'Efectivo divisas',
        kTextoSinInicial,
      ]) {
        expect(monedaDeMetodo(m) == kMonedaBs, esMetodoEnBolivares(m), reason: m);
      }
    });
    test('el vuelto solo en efectivo o divisas', () {
      expect(metodoPermiteVuelto('Efectivo \$'), isTrue);
      expect(metodoPermiteVuelto('Efectivo Bs'), isTrue);
      expect(metodoPermiteVuelto('Divisas'), isTrue);
      expect(metodoPermiteVuelto('Pago Móvil'), isFalse);
      expect(metodoPermiteVuelto('Punto de venta'), isFalse);
      expect(metodoPermiteVuelto('Zelle'), isFalse);
    });
  });

  group('Contado: precio en divisas o precio BCV × tasa', () {
    test('en \$ al precio de divisas', () {
      expect(cuadre([contado(100)], [pago('Divisas', 100)]).cuadra, isTrue);
    });
    test('en Bs al precio BCV × tasa BCV (como hoy en TecnoLíder)', () {
      expect(cuadre([contado(100, bcv: 110)], [pago('Pago Móvil', 11000)]).cuadra, isTrue);
    });
    test('en Bs al precio de divisas NO alcanza', () {
      final c = cuadre([contado(100, bcv: 110)], [pago('Pago Móvil', 10000)]);
      expect(c.problema, 'Falta cobrar \$9.09 o Bs 1000.00.');
      expect(c.faltaBs, 1000);
    });
    test('mezclado: \$50 + Bs a precio BCV de la otra mitad', () {
      expect(cuadre([contado(100, bcv: 110)],
          [pago('Divisas', 50), pago('Pago Móvil', 5500)]).cuadra, isTrue);
    });
    test('no se suman \$ y Bs crudos', () {
      final c = cuadre([contado(100)], [pago('Divisas', 60), pago('Pago Móvil', 5000)]);
      expect(c.cuadra, isFalse);
      expect(c.sobraUsd, 10);
      expect(c.sobraBs, 1000);
      // Antes: 60 + 5000 = 5060 «pagado» contra 100.
    });
    test('tolerancia: 1 Bs o \$0,01', () {
      expect(cuadre([contado(100)], [pago('Pago Móvil', 9999.5)]).cuadra, isTrue);
      expect(cuadre([contado(100)], [pago('Pago Móvil', 9998)]).cuadra, isFalse);
      expect(cuadre([contado(100)], [pago('Divisas', 99.99)]).cuadra, isTrue);
      expect(cuadre([contado(100)], [pago('Divisas', 99.97)]).cuadra, isFalse);
    });
    test('sin tasa no se convierten los Bs', () {
      expect(cuadre([contado(100)], [pago('Pago Móvil', 10000)], tasa: 0).problema,
          'No hay tasa BCV: no se pueden convertir los pagos en Bs.');
    });
  });

  group('Vuelto', () {
    test('en efectivo \$: cuadra', () {
      final c = cuadre([contado(95)],
          [pago('Divisas', 100), pago('Efectivo \$', 5, vuelto: true)]);
      expect(c.cuadra, isTrue);
      expect(c.vueltoUsd, 5);
    });
    test('guardado en negativo (como lo devuelve el servidor)', () {
      expect(cuadre([contado(95)], [pago('Divisas', 100), pago('Efectivo \$', -5)]).cuadra,
          isTrue);
    });
    test('en efectivo Bs', () {
      expect(cuadre([contado(95)],
          [pago('Divisas', 100), pago('Efectivo Bs', 500, vuelto: true)]).cuadra, isTrue);
    });
    test('NO por Pago Móvil', () {
      expect(cuadre([contado(95)],
              [pago('Divisas', 100), pago('Pago Móvil', 500, vuelto: true)]).problema,
          'El vuelto solo se da en efectivo o divisas (no por Pago Móvil).');
    });
    test('el sugerido, en la moneda del método', () {
      final c = cuadre([contado(95)], [pago('Divisas', 100)]);
      expect(c.vueltoSugerido(kMonedaUsd), 5);
      expect(c.vueltoSugerido(kMonedaBs), 500);
      expect(c.problema, contains('registre el vuelto'));
    });
  });

  group('Mixto: teléfono por Krece + forro de contado', () {
    final lin = [financiada(200, 50, precioFin: 260), contado(5, bcv: 6)];
    test('inicial + forro en \$', () {
      final c = cuadre(lin, [pago('Divisas', 55)]);
      expect(c.cuadra, isTrue);
      expect(c.inicialTotal, 50);
      expect(c.montoFinanciado, 210);
      expect(c.objetivoUsd, 55);
    });
    test('todo en Bs: (inicial + forro a BCV) × tasa', () {
      expect(cuadre(lin, [pago('Pago Móvil', 5600)]).cuadra, isTrue);
    });
    test('inicial en \$ y el forro en Bs a precio BCV', () {
      expect(cuadre(lin, [pago('Divisas', 50), pago('Pago Móvil', 600)]).cuadra, isTrue);
    });
    test('inicial en Bs y el forro en \$', () {
      expect(cuadre(lin, [pago('Pago Móvil', 5000), pago('Divisas', 5)]).cuadra, isTrue);
    });
    test('falta el forro: lo dice en \$ y en Bs (a BCV)', () {
      final c = cuadre(lin, [pago('Divisas', 50)]);
      expect(c.problema, 'Falta cobrar \$5.00 o Bs 600.00 (contado + inicial).');
    });
    test('sin inicial escrita no se emite', () {
      expect(cuadre([financiada(200, null), contado(5)], [pago('Divisas', 55)]).problema,
          'Escriba la inicial aprobada por la financiadora de: Redmi 13.');
    });
    test('venta financiada sin inicial con pago \$0', () {
      final c = cuadre([financiada(200, 0, precioFin: 260)],
          [pago(kTextoSinInicial, 0)]);
      expect(c.cuadra, isTrue);
      expect(c.montoFinanciado, 260);
    });
    test('el financiado no es un pago: no se suma a lo pagado', () {
      final c = cuadre(lin, [pago('Divisas', 55)]);
      expect(c.pagadoUsd, 55);
      expect(c.pagadoBs, 0);
    });
  });

  group('FPB: sale con lo que pague el cliente', () {
    test('pago parcial: deuda propuesta = total − pagado', () {
      final c = cuadre([contado(300)], [pago('Divisas', 100)], fpb: true);
      expect(c.cuadra, isTrue);
      expect(c.deudaFpbPropuesta, 200);
    });
    test('sin pago: todo es deuda', () {
      expect(cuadre([contado(300)], [], fpb: true).deudaFpbPropuesta, 300);
    });
    test('pagando la mitad en Bs (a BCV)', () {
      expect(cuadre([contado(300, bcv: 330)], [pago('Pago Móvil', 16500)], fpb: true)
          .deudaFpbPropuesta, 150);
    });
    test('pagado todo: sin deuda', () {
      expect(cuadre([contado(300)], [pago('Divisas', 300)], fpb: true).deudaFpbPropuesta, 0);
    });
    test('pagó de más: vuelto', () {
      final c = cuadre([contado(300)], [pago('Divisas', 320)], fpb: true);
      expect(c.cuadra, isFalse);
      expect(c.problema, contains('de más'));
    });
    test('sin FPB no hay deuda propuesta', () {
      expect(cuadre([contado(300)], [pago('Divisas', 100)]).deudaFpbPropuesta, 0);
    });
  });

  group('Lo que viaja al servidor', () {
    test('líneas y resumen', () {
      final c = cuadre([financiada(200, 50, precioFin: 260), contado(5, bcv: 6)],
          [pago('Divisas', 55)]);
      final r = c.resumen();
      expect(r['inicial'], 50);
      expect(r['monto_financiado'], 210);
      expect(r['tasa_bcv'], 100);
      expect(financiada(200, 50).toMap(),
          {'ref': '351111', 'tipo': 'equipo', 'financiada': true,
           'precio_divisa': 200.0, 'precio_financiadora': 0.0, 'inicial': 50.0});
    });
    test('el cuerpo de la factura lleva precio por línea y el cuadre', () {
      final tel = Producto(codigo: 'R13', nombre: 'Redmi 13', categoria: 'Telefono',
          marca: '', modelo: '', precioCosto: 0, tipo: '', precioVenta: 200);
      final forro = Producto(codigo: 'FORRO', nombre: 'Forro', categoria: 'Accesorio',
          marca: '', modelo: '', precioCosto: 0, tipo: '', precioVenta: 5);
      final f = FacturaModel(
          cliente: 'Ana', cedula: '1', tienda: 'Principal', telefono: '', nroFactura: 'F-1',
          equipos: [ImeiRegistro(imei: '351111', producto: tel, fechaIngreso: '',
              proveedor: '', color: '', ubicacion: 'Principal')],
          itemsSinImei: [forro],
          pagos: [PagoFactura(metodo: 'Divisas', monto: 55, tipo: 'Contado')],
          vendedor: 'Luis', fecha: '16/10/2026',
          vendedorPorImei: {'351111': 'Pedro'});
      final lineas = [financiada(200, 50, precioFin: 260), contado(5, bcv: 6)];
      final c = cuadre(lineas, [pago('Divisas', 55)]);
      // toApiMap arma listas de Map<String, String>: no admiten un número.
      final m = agregarCuadreAlCuerpo(f.toApiMap(), lineas, c);
      expect(m['equipos'], [
        {'imei': '351111', 'vendedor': 'Pedro', 'precio_unitario': 260.0}
      ]);
      expect(m['items'], [
        {'codigo': 'FORRO', 'vendedor': '', 'precio_unitario': 5.0}
      ]);
      expect([m['tasa_bcv'], m['inicial'], m['monto_financiado']], [100.0, 50.0, 210.0]);
      expect((m['cuadre'] as Map)['lineas'], hasLength(2));
      expect(m['nro_factura'], 'F-1', reason: 'lo de siempre sigue igual');
    });
    test('monto en \$ de cada pago: Bs a tasa BCV, con signo', () {
      expect(montoUsdDePago(5600, kMonedaBs, 100), 56);
      expect(montoUsdDePago(-500, kMonedaBs, 100), -5);
      expect(montoUsdDePago(20, kMonedaUsd, 100), 20);
    });
    test('clave de idempotencia: 32 hex', () {
      var i = 0;
      final k = nuevaClaveIdempotencia((m) => (i++) % m);
      expect(k, matches(RegExp(r'^[0-9a-f]{32}$')));
    });
  });

  group('Pago guardado (moneda y vuelto)', () {
    test('vuelve del servidor en negativo y sigue siendo vuelto', () {
      final p = PagoFactura.fromMap({'metodo': 'Efectivo \$', 'monto': '-5.00',
          'tipo': 'Contado', 'moneda': 'USD', 'es_vuelto': '1', 'monto_usd': '-5.00'});
      expect(p.esVuelto, isTrue);
      expect(p.monedaEfectiva, kMonedaUsd);
      expect(p.montoUsd, -5);
      expect(p.toMap()['es_vuelto'], isTrue);
    });
    test('un pago viejo (sin moneda) toma la del método', () {
      final p = PagoFactura.fromMap({'metodo': 'Pago Móvil', 'monto': 1000, 'tipo': 'Contado'});
      expect(p.esVuelto, isFalse);
      expect(p.monedaEfectiva, kMonedaBs);
      expect(p.toMap().containsKey('es_vuelto'), isFalse,
          reason: 'la 1.0.17 no manda claves nuevas y la nueva tampoco si no hacen falta');
    });
  });

  group('Factura impresa: solo lo pagado', () {
    Producto prod() => Producto(codigo: 'R13', nombre: 'Redmi 13', categoria: 'Telefono',
        marca: '', modelo: '', precioCosto: 0, tipo: '', precioVenta: 200);
    FacturaModel factura(List<PagoFactura> pagos, {double? tasa}) => FacturaModel(
        cliente: 'Ana', cedula: '1', tienda: 'Principal', telefono: '', nroFactura: 'F-1',
        equipos: [ImeiRegistro(imei: '351111', producto: prod(), fechaIngreso: '',
            proveedor: '', color: '', ubicacion: 'Principal')],
        itemsSinImei: const [], pagos: pagos, vendedor: 'Luis', fecha: '16/10/2026',
        tasaBcv: tasa);

    test('sin el pago de \$0 de la venta sin inicial', () {
      final f = factura([
        PagoFactura(metodo: kTextoSinInicial, monto: 0, tipo: 'Financiado', esInicial: true),
      ]);
      expect(pagosEnFacturaImpresa(f), isEmpty);
    });
    test('el vuelto sale rotulado y en negativo', () {
      final v = PagoFactura(metodo: 'Efectivo \$', monto: -5, tipo: 'Contado', esVuelto: true);
      final f = factura([PagoFactura(metodo: 'Divisas', monto: 100, tipo: 'Contado'), v]);
      expect(pagosEnFacturaImpresa(f).length, 2);
      expect(rotuloPagoFactura(v), 'Vuelto · Efectivo \$');
      expect(montoPagoFacturaTexto(v), '-\$5.00');
      expect(montoPagoFacturaTexto(PagoFactura(metodo: 'Efectivo Bs', monto: -400,
          tipo: 'Contado', esVuelto: true)), '-400,00 Bs.');
      // Lo que suma la factura descuenta el vuelto.
      expect(f.total, 95);
    });
    test('la tasa impresa es la del cobro, no la del día', () {
      ConfigSistema.tasaCambio = 999;
      expect(tasaDeFactura(factura(const [], tasa: 120.5)), 120.5);
      expect(tasaDeFactura(factura([PagoFactura(metodo: 'Pago Móvil', monto: 1000,
          tipo: 'Contado', tasaCambio: 110)])), 110);
      expect(tasaDeFactura(factura(const [])), 999);
    });
  });

  group('¿De qué factura es esta deuda?', () {
    test('la que guarda el servidor', () {
      final c = CuentaPorCobrar.fromMap({
        'id': 745, 'cedula': '30128398', 'nombre': 'Eduardo', 'telefono': '',
        'correo': '', 'monto_total': '300.00', 'factura_id': 7830,
        'nro_factura': '1791390473465-0428', 'tienda': 'Principal',
        'cuotas': [], 'pagos': [],
      });
      expect(c.facturaId, 7830);
      expect(c.tienda, 'Principal');
      expect(nroFacturaDeCuenta(c), '1791390473465-0428');
      expect(c.toMap().containsKey('factura_id'), isFalse,
          reason: 'el PUT de la cuenta no toca el enlace');
    });
    test('en las cuentas viejas, la de la nota', () {
      final c = CuentaPorCobrar(cedula: '1', nombre: 'A', telefono: '', correo: '',
          montoTotal: 10, notas: 'Generado automáticamente desde factura 1791-0428');
      expect(c.facturaId, isNull);
      expect(nroFacturaDeCuenta(c), '1791-0428');
    });
    test('una cuenta cargada a mano no tiene factura', () {
      expect(nroFacturaDeCuenta(CuentaPorCobrar(cedula: '1', nombre: 'A', telefono: '',
          correo: '', montoTotal: 10, notas: 'Préstamo')), '');
    });
  });
}
