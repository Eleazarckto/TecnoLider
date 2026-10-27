// ============================================================================
//  dialogo_pago_movil_test.dart — Cerrar «Registrar Pago» con Pago Móvil
//
//  El diálogo liberaba (dispose) los controladores de referencia, cédula y
//  teléfono del pagador apenas se cerraba, pero el diálogo sigue dibujado
//  durante su animación de salida: sus TextField usaban controladores ya
//  liberados («A TextEditingController was used after being disposed»).
//  Se veía al Confirmar (la factura se redibuja con el pago nuevo mientras
//  el diálogo se va); Cancelar queda como guarda. Venía de la base 1.0.17.
// ============================================================================

import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tecno_lider/main.dart';

http.Client _servidor() =>
    MockClient((_) async => http.Response('[]', 200,
        headers: {'content-type': 'application/json; charset=utf-8'}));

Future<void> _abrirPagoMovil(WidgetTester t) async {
  // Alto suficiente para que el formulario y el diálogo entren sin scroll.
  t.view.physicalSize = const Size(900, 1600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: FormularioFactura(tienda: 'Principal')));
  await t.pumpAndSettle();
  // «Agregar» de la sección Pagos (el segundo).
  final agregar = find.widgetWithText(TextButton, 'Agregar').last;
  await t.ensureVisible(agregar);
  await t.tap(agregar);
  await t.pumpAndSettle();
  await t.tap(find.ancestor(
      of: find.text('Método de pago'),
      matching: find.byWidgetPredicate((w) => w is DropdownButtonFormField)));
  await t.pumpAndSettle();
  await t.tap(find.text('Pago Móvil').last);
  await t.pumpAndSettle();
  expect(find.text('Referencia *'), findsOneWidget);
}

/// Corre [cuerpo] con el servidor simulado. El interruptor «Marcar como
/// inicial» del diálogo es un SwitchListTile dentro de una caja con color y
/// Flutter avisa (solo en depuración) que su efecto al tocar no se ve: es
/// otro asunto y se deja pasar, para que la prueba mire solo los
/// controladores. Cualquier otro error sigue haciendo fallar la prueba.
Future<void> _correr(Future<void> Function() cuerpo) async {
  final original = FlutterError.onError;
  FlutterError.onError = (d) {
    if (d.exceptionAsString().contains('ListTile background color')) return;
    original?.call(d);
  };
  try {
    await http.runWithClient(cuerpo, _servidor);
  } finally {
    FlutterError.onError = original;
  }
}

Future<void> _escribir(WidgetTester t, String rotulo, String texto) async {
  final f = find.ancestor(of: find.text(rotulo), matching: find.byType(TextField));
  await t.ensureVisible(f);
  await t.enterText(f, texto);
  await t.pump();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    usuarioSesion = Usuario(
        nombre: 'Prueba', cedula: 'V-1', correo: 'prueba@ejemplo.com',
        clave: '', rol: 'Administrador', tienda: 'Principal');
    ConfigSistema.tasaCambio = 200;
  });

  testWidgets('Cancelar el diálogo con Pago Móvil no usa controladores liberados',
      (t) async {
    await _correr(() async {
      await _abrirPagoMovil(t);
      await t.tap(find.text('Cancelar'));
      await t.pumpAndSettle();
      expect(find.text('Registrar Pago'), findsNothing);
      expect(t.takeException(), isNull);
    });
  });

  testWidgets('Confirmar un Pago Móvil lo registra y cierra limpio', (t) async {
    await _correr(() async {
      await _abrirPagoMovil(t);
      await _escribir(t, 'Monto (Bs)', '2000');
      await _escribir(t, 'Referencia *', '004187');
      await _escribir(t, 'Cédula del pagador *', '18456321');
      await _escribir(t, 'Teléfono afiliado del pagador *', '04145551234');
      await t.tap(find.widgetWithText(ElevatedButton, 'Confirmar'));
      await t.pumpAndSettle();
      expect(find.text('Registrar Pago'), findsNothing);
      expect(t.takeException(), isNull);
      // El pago quedó en la factura.
      expect(find.text('Pago Móvil'), findsOneWidget);
    });
  });
}
