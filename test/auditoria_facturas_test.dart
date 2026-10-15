// Pruebas de la auditoría automática de facturas (lib/auditoria_facturas.dart).
// Los casos salen de facturas reales del servidor (oct-2026).

import 'package:flutter_test/flutter_test.dart';

import 'package:tecno_lider/main.dart';

Producto _prod(String codigo, double venta) => Producto(
    codigo: codigo, nombre: codigo, categoria: 'Telefono', marca: '',
    modelo: '', precioCosto: 0, tipo: '', precioVenta: venta);

ListaPrecio _lista(String nombre, Map<String, double> precios,
    {String? financiadora, double pctInicial = 0, String codigo = 'H010'}) =>
    ListaPrecio(
      nombre: nombre,
      fechaCreacion: '',
      financiadora: financiadora,
      porcentajeInicial: pctInicial,
      columnas: precios.keys.map((c) => ColumnaPrecio(nombre: c)).toList(),
      items: [
        ItemListaPrecio(producto: _prod(codigo, 110), preciosPorColumna: precios),
      ],
    );

// Listas como están en producción para el HONOR Choice T10 (H010).
final _listas = [
  _lista('Cashea', {'Precio': 198}),
  _lista('LISTA INTERNA DE TODO LOS TELEFONOS Y PRECIOS',
      {'Precio': 141, 'CASHEA': 198, 'BCV': 132, 'DIVISAS': 110},
      financiadora: 'KRECE.', pctInicial: 30),
  _lista('KRECE', {'Precio': 139.7}),
  _lista('BCV', {'Precio': 132}),
];

void main() {
  group('preciosReferenciaDe', () {
    test('Krece: toma la lista marcada con la financiadora y su % de inicial', () {
      final p = preciosReferenciaDe(codigo: 'H010', precioVenta: 110,
          listas: _listas, financiadora: 'Krece');
      expect(p.divisa, 110);
      expect(p.bcv, 132);
      expect(p.financiadora, 141);
      expect(p.pctInicial, 30);
    });

    test('Cashea: lista con el nombre de la financiadora', () {
      final p = preciosReferenciaDe(codigo: 'H010', precioVenta: 110,
          listas: _listas, financiadora: 'Cashea');
      expect(p.financiadora, 198);
    });

    test('la lista elegida al facturar manda y usa la columna de la financiadora', () {
      final p = preciosReferenciaDe(codigo: 'H010', precioVenta: 110,
          listas: _listas, financiadora: 'Cashea',
          nombreLista: 'LISTA INTERNA DE TODO LOS TELEFONOS Y PRECIOS');
      expect(p.financiadora, 198);
    });

    test('producto que no está en ninguna lista', () {
      final p = preciosReferenciaDe(codigo: 'X1', precioVenta: 50,
          listas: _listas, financiadora: 'Krece');
      expect(p.divisa, 50);
      expect(p.bcv, isNull);
      expect(p.financiadora, isNull);
    });
  });

  group('auditarFacturaAuto', () {
    final krece = preciosReferenciaDe(codigo: 'H010', precioVenta: 110,
        listas: _listas, financiadora: 'Krece');
    final cashea = preciosReferenciaDe(codigo: 'H010', precioVenta: 110,
        listas: _listas, financiadora: 'Cashea');
    final contado = preciosReferenciaDe(codigo: 'H010', precioVenta: 110,
        listas: _listas);

    test('contado en divisas al precio de divisa concuerda', () {
      final r = auditarFacturaAuto(
          renglones: [RenglonAuditoria(financiado: false, precios: contado)],
          pagadoUsd: 110, pagadoBsEnUsd: 0);
      expect(r.estado, EstadoAuditoriaAuto.concuerda);
    });

    test('contado en bolívares se compara con el precio BCV', () {
      final r = auditarFacturaAuto(
          renglones: [RenglonAuditoria(financiado: false, precios: contado)],
          pagadoUsd: 0, pagadoBsEnUsd: 132.31);
      expect(r.estado, EstadoAuditoriaAuto.concuerda);
    });

    test('contado cobrado de menos marca la diferencia', () {
      final r = auditarFacturaAuto(
          renglones: [RenglonAuditoria(financiado: false, precios: contado)],
          pagadoUsd: 100, pagadoBsEnUsd: 0);
      expect(r.estado, EstadoAuditoriaAuto.diferencia);
      expect(r.diferencia, -10);
      expect(r.titulo, 'Diferencia de -\$10.00');
    });

    test('Krece: inicial = 30% del precio Krece concuerda (factura 318)', () {
      final r = auditarFacturaAuto(
          renglones: [RenglonAuditoria(financiado: true, precios: krece)],
          pagadoUsd: 0, pagadoBsEnUsd: 42.10,
          numeroCuotas: 6, montoCuota: 42, financiadora: 'Krece');
      expect(r.estado, EstadoAuditoriaAuto.concuerda);
    });

    test('Krece: inicial distinta a la esperada (factura 304)', () {
      final r = auditarFacturaAuto(
          renglones: [RenglonAuditoria(financiado: true, precios: krece)],
          pagadoUsd: 0, pagadoBsEnUsd: 55.13,
          numeroCuotas: 6, montoCuota: 14, financiadora: 'Krece');
      expect(r.estado, EstadoAuditoriaAuto.diferencia);
      expect(r.diferencia, closeTo(12.83, 0.001)); // 55.13 − 42.30
    });

    test('Cashea: inicial + cuotas = precio Cashea concuerda (factura 237)', () {
      final r = auditarFacturaAuto(
          renglones: [RenglonAuditoria(financiado: true, precios: cashea)],
          pagadoUsd: 0, pagadoBsEnUsd: 19.80,
          numeroCuotas: 6, montoCuota: 29.70, financiadora: 'Cashea');
      expect(r.estado, EstadoAuditoriaAuto.concuerda);
    });

    test('financiado + accesorio de contado: el accesorio no cuenta como inicial', () {
      final vidrio = PreciosReferencia(divisa: 4);
      final r = auditarFacturaAuto(
          renglones: [
            RenglonAuditoria(financiado: true, precios: krece),
            RenglonAuditoria(financiado: false, precios: vidrio),
          ],
          pagadoUsd: 46.30, pagadoBsEnUsd: 0, financiadora: 'Krece');
      expect(r.estado, EstadoAuditoriaAuto.concuerda);
    });

    test('sin precio de la financiadora no inventa un resultado', () {
      final r = auditarFacturaAuto(
          renglones: [RenglonAuditoria(financiado: true,
              precios: const PreciosReferencia(divisa: 155))],
          pagadoUsd: 49, pagadoBsEnUsd: 0, financiadora: 'Krece');
      expect(r.estado, EstadoAuditoriaAuto.sinDatos);
    });

    test('resultado se guarda y se recupera del reporte', () {
      final r = ResultadoAuditoriaAuto(EstadoAuditoriaAuto.diferencia,
          diferencia: 2.5, detalle: 'x');
      final r2 = ResultadoAuditoriaAuto.fromMap(r.toMap());
      expect(r2.estado, r.estado);
      expect(r2.diferencia, 2.5);
    });
  });

  group('MarcaAuditoria', () {
    test('ida y vuelta por JSON y estado pendiente', () {
      final m = MarcaAuditoria(pagoRecibido: true, pagoPor: 'Josmar',
          pagoEn: '14/10/2026 10:00');
      expect(m.pendiente, isTrue);
      m.auditoriaOk = true;
      expect(m.pendiente, isFalse);
      final m2 = MarcaAuditoria.fromJson(m.toJson());
      expect(m2.pagoRecibido, isTrue);
      expect(m2.auditoriaOk, isTrue);
      expect(m2.pagoPor, 'Josmar');
      expect(MarcaAuditoria(auditoriaOk: false).conProblema, isTrue);
    });

    test('lee solo las claves aud_fac_ de configuracion', () {
      final marcas = marcasDesdeConfiguracion({
        'cfg_moneda': '\$',
        claveAuditoriaFactura('123-45'): '{"p":1,"pu":"Ana"}',
        'aud_fac_roto': 'no-json',
      });
      expect(marcas.length, 1);
      expect(marcas['aud_fac_123-45']!.pagoRecibido, isTrue);
    });
  });

  test('contarUnidadesVentas separa contado y financiados por financiadora', () {
    final c = contarUnidadesVentas([
      {
        'pagos': [{'financiadora': 'Krece', 'metodo': 'Punto de venta'}],
        'productos': [{'financiado': true}, {'financiado': false}],
      },
      {
        'pagos': [{'financiadora': '', 'metodo': 'Cashea'}],
        'productos': [{'financiado': true}],
      },
      {
        'pagos': [{'financiadora': '', 'metodo': 'Efectivo \$'}],
        'productos': [{'financiado': false}],
      },
    ]);
    expect(c.contado, 2);
    expect(c.financiado, 2);
    expect(c.porFinanciadora, {'Krece': 1, 'Cashea': 1});
  });

  test('lineasPrecioReferencia: sin porcentaje, con precio base y de la financiadora', () {
    const p = PreciosReferencia(divisa: 110, financiadora: 141, pctInicial: 30);
    expect(lineasPrecioReferencia(p, financiado: false),
        ['Precio ref. divisa: \$110.00']);
    final fin = lineasPrecioReferencia(p, financiado: true, financiadora: 'Krece');
    expect(fin, ['Precio base: \$110.00', 'Precio Krece: \$141.00']);
    expect(fin.any((l) => l.contains('%')), isFalse);
  });

  group('venta financiada sin inicial (promoción)', () {
    final cashea = preciosReferenciaDe(codigo: 'H010', precioVenta: 110,
        listas: _listas, financiadora: 'Cashea');
    final krece = preciosReferenciaDe(codigo: 'H010', precioVenta: 110,
        listas: _listas, financiadora: 'Krece');

    test('inicial 0 y cuotas = precio de la lista concuerda', () {
      final r = auditarFacturaAuto(
          renglones: [RenglonAuditoria(financiado: true, precios: cashea)],
          pagadoUsd: 0, pagadoBsEnUsd: 0,
          numeroCuotas: 6, montoCuota: 33, financiadora: 'Cashea');
      expect(r.estado, EstadoAuditoriaAuto.concuerda);
      expect(r.detalle, contains('Sin inicial (promoción)'));
    });

    test('inicial 0 con lista de 30% y cuotas que no suman el precio: diferencia', () {
      final r = auditarFacturaAuto(
          renglones: [RenglonAuditoria(financiado: true, precios: krece)],
          pagadoUsd: 0, pagadoBsEnUsd: 0,
          numeroCuotas: 6, montoCuota: 14, financiadora: 'Krece');
      expect(r.estado, EstadoAuditoriaAuto.diferencia);
      expect(r.detalle, startsWith('Sin inicial (promoción)'));
    });

    test('% de inicial: 0 y vacío valen, negativo no', () {
      expect(errorPctInicial('0'), isNull);
      expect(errorPctInicial(''), isNull);
      expect(errorPctInicial('36,5'), isNull);
      expect(errorPctInicial('-5'), isNotNull);
      expect(errorPctInicial('abc'), isNotNull);
      expect(esInicialCero(0), isTrue);
      expect(esInicialCero(0.001), isTrue);
      expect(esInicialCero(0.01), isFalse);
    });

    test('lista con 0% de inicial: la inicial es 0 y la cuota cubre el precio', () {
      final l = _lista('Promo Cashea', {'Precio': 198}, financiadora: 'Cashea');
      l.numeroCuotas = 6;
      final it = l.items.first;
      expect(l.inicialDe(it, 198), 0);
    });
  });
}
