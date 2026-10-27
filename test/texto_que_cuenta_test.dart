// ============================================================================
//  texto_que_cuenta_test.dart — Las cifras que cuentan respetan el formato
//
//  TextoQueCuenta anima el número de un texto ya formateado. Al terminar
//  muestra el texto original; mientras cuenta, cada paso tiene que salir con
//  el mismo formato (separadores, decimales, prefijo y sufijo), o la cifra
//  «baila» de ancho y de estilo.
// ============================================================================

import 'package:flutter_test/flutter_test.dart';

import 'package:tecno_lider/theme/movimiento.dart';

void main() {
  void ida(String texto, double valor) {
    final c = CifraEnTexto.leer(texto)!;
    expect(c.valor, valor, reason: texto);
    expect(c.escribir(valor), texto, reason: 'vuelve a escribirse igual');
  }

  test('dólares con miles y centavos', () => ida('\$1,234.56', 1234.56));
  test('bolívares a la venezolana', () => ida('Bs 1.234.567,89', 1234567.89));
  test('entero con sufijo', () => ida('45 equipos', 45));
  test('porcentaje', () => ida('12.5%', 12.5));
  test('miles sin decimales', () => ida('Bs 12.500', 12500));
  test('signo antes del símbolo: queda en el prefijo', () => ida('-\$ 30.00', 30));
  test('negativo pegado al número', () => ida('-30.00 \$', -30));
  test('una coma al final no es parte del número', () {
    final c = CifraEnTexto.leer('45, hoy')!;
    expect(c.valor, 45);
    expect(c.escribir(45), '45, hoy');
  });
  test('cuenta con el mismo formato', () {
    final c = CifraEnTexto.leer('Bs 1.234,56')!;
    expect(c.escribir(500.5), 'Bs 500,50');
    expect(c.escribir(0), 'Bs 0,00');
  });
  test('sin número: no se anima', () => expect(CifraEnTexto.leer('Sin datos'), isNull));
}
