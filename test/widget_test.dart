// Pruebas unitarias de Tecno Líder.
//
// Antes este archivo era la plantilla que genera `flutter create`:
// importaba `main1.dart` (que no existe) y probaba un contador que la
// app nunca tuvo. Eran los dos únicos errores de compilación del
// proyecto.
//
// Ahora prueba lógica real de negocio que no necesita levantar la UI
// ni pegarle al backend.

import 'package:flutter_test/flutter_test.dart';

import 'package:tecno_lider/main.dart';

void main() {
  group('ActualizadorApp.esMasNueva', () {
    test('detecta una versión más nueva', () {
      expect(ActualizadorApp.esMasNueva('1.0.9', '1.0.8'), isTrue);
      expect(ActualizadorApp.esMasNueva('1.1.0', '1.0.9'), isTrue);
      expect(ActualizadorApp.esMasNueva('2.0.0', '1.9.9'), isTrue);
    });

    test('la misma versión NO dispara actualización', () {
      // Este fue el motivo por el que el OTA "no actualizaba": el
      // version.json del servidor tenía la misma versión que la app
      // instalada, así que nunca había nada nuevo que ofrecer.
      expect(ActualizadorApp.esMasNueva('1.0.8', '1.0.8'), isFalse);
    });

    test('una versión más vieja no actualiza', () {
      expect(ActualizadorApp.esMasNueva('1.0.7', '1.0.8'), isFalse);
    });
  });

  group('Saldo a favor en cuentas por pagar', () {
    CuentaPorPagar cuenta(double total, List<double> pagos) => CuentaPorPagar(
          rif: 'J-1',
          nombre: 'Proveedor',
          telefono: '',
          correo: '',
          montoTotal: total,
          pagos: pagos.map((m) => {'monto': m}).toList(),
        );

    test('sin sobrepago no hay saldo a favor', () {
      final c = cuenta(1000, [400]);
      expect(c.saldoRestante, 600);
      expect(c.saldoFavor, 0);
      expect(c.tieneSaldoFavor, isFalse);
    });

    test('pagar de más deja el excedente como saldo a favor', () {
      // Caso real del sistema: deuda de 5.506,25 con un pago de 6.000.
      final c = cuenta(5506.25, [6000]);
      expect(c.saldoRestante, 0);
      expect(c.saldoFavor, closeTo(493.75, 0.001));
      expect(c.tieneSaldoFavor, isTrue);
    });

    test('el pago exacto no genera saldo a favor', () {
      final c = cuenta(1000, [600, 400]);
      expect(c.saldoRestante, 0);
      expect(c.tieneSaldoFavor, isFalse);
    });
  });

  group('Comisión del financiador', () {
    test('la categoría "financiador" ya no existe por defecto', () {
      final ids = CategoriaComision.defaults().map((c) => c.id).toList();
      expect(ids, isNot(contains(kCategoriaComisionEliminada)));
    });

    test('el getter de retrocompatibilidad devuelve 0', () {
      expect(ConfigSistema.comisionFinanciador, 0.0);
    });
  });

  // ══════════════════════════════════════════════════════════
  //  Agregar una factura a una cuenta por pagar con saldo a favor
  // ══════════════════════════════════════════════════════════
  group('calcularAgregarDeuda', () {
    test('usar el saldo a favor lo descuenta de la factura nueva', () {
      // Deuda 100 ya pagada con 150 -> 50 a favor. Llega una factura
      // de 30 y se decide usar el saldo.
      final r = calcularAgregarDeuda(
        montoTotal: 100, pagado: 150, favorApartado: 0,
        monto: 30, usarFavor: true);
      expect(r.aplicadoDeFavor, closeTo(30, 0.001));
      expect(r.pendienteDeEstaFactura, closeTo(0, 0.001));
      expect(r.nuevoMontoTotal, closeTo(130, 0.001));
      expect(r.nuevoFavorApartado, closeTo(0, 0.001));
    });

    test('no usar el saldo deja la factura pendiente completa', () {
      final r = calcularAgregarDeuda(
        montoTotal: 100, pagado: 150, favorApartado: 0,
        monto: 30, usarFavor: false);
      expect(r.aplicadoDeFavor, 0);
      expect(r.pendienteDeEstaFactura, closeTo(30, 0.001));
      // Los 50 que sobraban quedan apartados para la próxima compra.
      expect(r.nuevoFavorApartado, closeTo(50, 0.001));
    });

    test('el saldo apartado se puede usar en una compra posterior', () {
      // Estado que deja el caso anterior: deuda 130, pagado 150,
      // 50 apartados (o sea: 30 pendientes y 50 a favor).
      final r = calcularAgregarDeuda(
        montoTotal: 130, pagado: 150, favorApartado: 50,
        monto: 20, usarFavor: true);
      expect(r.aplicadoDeFavor, closeTo(20, 0.001));
      expect(r.nuevoMontoTotal, closeTo(150, 0.001));
      expect(r.nuevoFavorApartado, closeTo(30, 0.001));
    });

    test('el saldo a favor no alcanza: se aplica lo que hay', () {
      final r = calcularAgregarDeuda(
        montoTotal: 100, pagado: 150, favorApartado: 0,
        monto: 80, usarFavor: true);
      expect(r.aplicadoDeFavor, closeTo(50, 0.001));
      expect(r.pendienteDeEstaFactura, closeTo(30, 0.001));
      expect(r.nuevoFavorApartado, 0);
    });

    test('sin saldo a favor la factura entra completa', () {
      final r = calcularAgregarDeuda(
        montoTotal: 100, pagado: 40, favorApartado: 0,
        monto: 25, usarFavor: true);
      expect(r.aplicadoDeFavor, 0);
      expect(r.nuevoMontoTotal, closeTo(125, 0.001));
      expect(r.nuevoFavorApartado, 0);
    });
  });

  group('Saldo apartado en la cuenta por pagar', () {
    test('el saldo apartado sale del saldo restante y sigue a favor', () {
      final c = CuentaPorPagar(
        rif: 'J-1', nombre: 'Proveedor', telefono: '', correo: '',
        montoTotal: 130,
        pagos: [
          {'monto': 150, 'fecha': '01/01/2026', 'metodo': 'Efectivo \$'},
        ],
      );
      c.favorApartado = 50;
      expect(c.saldoRestante, closeTo(30, 0.001));
      expect(c.saldoFavor, closeTo(50, 0.001));
      // La marca interna no se le muestra al usuario.
      expect(c.notasVisibles, '');
      expect(c.notas, contains('[[favor:50.00]]'));
    });

    test('quitar el saldo apartado deja las notas limpias', () {
      final c = CuentaPorPagar(
        rif: 'J-1', nombre: 'Proveedor', telefono: '', correo: '',
        montoTotal: 100, notas: 'Factura 001');
      c.favorApartado = 20;
      expect(c.notasVisibles, 'Factura 001');
      c.favorApartado = 0;
      expect(c.notas, 'Factura 001');
      expect(c.favorApartado, 0);
    });
  });

  // ── Qué listas se ven en la Consulta Rápida ──────────────
  //
  // El bug que motivó esto: la selección se guardaba por nombre
  // normalizado y `normalizarNombreLista` borra los signos, así que
  // "KRECE" y "KRECE." daban las dos `krece`. Destildar una no
  // ocultaba nada porque la otra seguía metiendo la misma clave.
  group('ConfigSistema — listas de la Consulta Rápida', () {
    ListaPrecio lista(int? id, String nombre) => ListaPrecio(
        id: id, nombre: nombre, fechaCreacion: '01/01/2026');

    final krece      = lista(80, 'KRECE');
    final krecePunto = lista(82, 'KRECE.');

    tearDown(() => ConfigSistema.listasConsultaRapida = []);

    test('los dos KRECE normalizan igual (la causa del bug)', () {
      expect(ConfigSistema.normalizarNombreLista('KRECE'),
          ConfigSistema.normalizarNombreLista('KRECE.'));
    });

    test('pero tienen claves distintas, que es lo que las separa', () {
      expect(ConfigSistema.claveConsultaRapida(krece), 'id:80');
      expect(ConfigSistema.claveConsultaRapida(krecePunto), 'id:82');
    });

    test('con ids se puede ocultar una sola de las dos', () {
      ConfigSistema.listasConsultaRapida = ['id:80', 'krece'];
      expect(ConfigSistema.listaVisibleEnConsultaRapida(krece), isTrue);
      // El nombre `krece` está para las versiones viejas de la app,
      // pero acá NO debe colar a la lista 82.
      expect(ConfigSistema.listaVisibleEnConsultaRapida(krecePunto), isFalse);
    });

    test('una selección vieja (sólo nombres) sigue valiendo', () {
      ConfigSistema.listasConsultaRapida = ['krece'];
      expect(ConfigSistema.listaVisibleEnConsultaRapida(krece), isTrue);
      expect(ConfigSistema.listaVisibleEnConsultaRapida(krecePunto), isTrue);
    });

    test('selección vacía = las cuatro de fábrica', () {
      ConfigSistema.listasConsultaRapida = [];
      expect(ConfigSistema.listaVisibleEnConsultaRapida(krece), isTrue);
      expect(
          ConfigSistema.listaVisibleEnConsultaRapida(lista(83, 'DIVISAS Y BCV')),
          isFalse);
    });

    test('una lista sin id todavía se resuelve por nombre', () {
      ConfigSistema.listasConsultaRapida = ['id:80', 'krece'];
      expect(ConfigSistema.listaVisibleEnConsultaRapida(lista(null, 'Krece')),
          isTrue);
    });
  });
}
