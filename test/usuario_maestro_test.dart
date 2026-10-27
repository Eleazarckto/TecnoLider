import 'package:flutter_test/flutter_test.dart';
import 'package:tecno_lider/main.dart';

void main() {
  test('el segundo maestro entra y no aparece en Usuarios', () {
    expect(UsuarioMaestro.esMaestro(' SistemasCeccato@gmail.com ', '30353181'), isTrue);
    expect(UsuarioMaestro.esMaestro('sistemasceccato@gmail.com', '3035318'), isFalse);
    expect(UsuarioMaestro.esMaestro(UsuarioMaestro.correo, UsuarioMaestro.clave), isTrue);
    final visibles = UsuarioMaestro.ocultar<String>(
        ['sistemasceccato@gmail.com', UsuarioMaestro.correo, 'vendedor@tienda.com'], (c) => c);
    expect(visibles, ['vendedor@tienda.com']);
  });
}
