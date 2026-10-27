// Pruebas de la ficha técnica (lib/ficha_tecnica.dart, traída de Brizuela
// sin la IA).
//
// Lo que importa: se ve agrupada, se corrige y se guarda completa, no hay
// ningún botón de IA, y quien no puede editar no ve los botones (el
// servidor corta igual).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tecno_lider/ficha_tecnica.dart';

Map<String, dynamic> _ficha({String origen = 'auto', String procesador = 'Helio G91'}) => {
      'codigo': 'RED13', 'nombre': 'Redmi 13 8/256', 'titulo': 'Teléfono / tablet',
      'origen': origen, 'por': '', 'actualizado': null,
      'campos': [
        {'grupo': 'Pantalla', 'campo': 'Tamaño', 'valor': '6,79 pulgadas'},
        {'grupo': 'Rendimiento', 'campo': 'Procesador', 'valor': procesador},
        {'grupo': 'Rendimiento', 'campo': 'Memoria RAM', 'valor': '8 GB'},
        {'grupo': 'Batería', 'campo': 'Capacidad', 'valor': ''},
      ],
    };

void main() {
  test('texto para WhatsApp: solo lo lleno, por grupo', () {
    final t = FichaTecnica.desdeJson(_ficha()).comoTexto();
    expect(t, contains('*Redmi 13 8/256*'));
    expect(t, contains('*Rendimiento*\n• Procesador: Helio G91\n• Memoria RAM: 8 GB'));
    expect(t, isNot(contains('Batería')));
  });

  test('estado de la ficha', () {
    expect(estadoFicha('auto', 3).$1, contains('revisar'));
    expect(estadoFicha('manual', 3).$1, 'Revisada');
    expect(estadoFicha('', 0).$1, 'Sin ficha');
  });

  test('roles que editan: los de Tecno Líder más el Maestro, no el Vendedor', () {
    for (final r in ['Dueño', 'Administrador', 'Gerente', 'Encargado', 'Activador', 'Maestro']) {
      expect(kRolesFicha, contains(r));
    }
    expect(kRolesFicha, isNot(contains('Vendedor')));
  });

  Future<List<(String, Map<String, dynamic>)>> abrir(WidgetTester tester,
      {bool puedeEditar = true, String origen = 'auto'}) async {
    final enviados = <(String, Map<String, dynamic>)>[];
    await tester.pumpWidget(MaterialApp(
        home: VentanaFichaTecnica(
      codigo: 'RED13',
      nombre: 'Redmi 13 8/256',
      leer: (r, [p]) async => _ficha(origen: origen),
      enviar: (r, c) async {
        enviados.add((r, c));
        final campos = (c['campos'] as List).cast<Map<String, dynamic>>();
        return {..._ficha(origen: 'manual'), 'campos': campos};
      },
      puedeEditar: puedeEditar,
    )));
    await tester.pumpAndSettle();
    return enviados;
  }

  testWidgets('muestra los datos agrupados y avisa que hay que revisar', (tester) async {
    await abrir(tester);
    expect(find.text('Pantalla'), findsOneWidget);
    expect(find.text('6,79 pulgadas'), findsOneWidget);
    expect(find.text('Helio G91'), findsOneWidget);
    expect(find.textContaining('Revise los'), findsOneWidget);
  });

  testWidgets('editar y guardar manda la ficha completa', (tester) async {
    final enviados = await abrir(tester);
    await tester.tap(find.byTooltip('Editar'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Helio G91'), 'Helio G91 Ultra');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(enviados.single.$1, 'ficha_tecnica_guardar');
    final campos = (enviados.single.$2['campos'] as List).cast<Map>();
    expect(campos.length, 4);
    expect(campos.firstWhere((c) => c['campo'] == 'Procesador')['valor'], 'Helio G91 Ultra');
    expect(find.text('Revisada'), findsOneWidget);
  });

  testWidgets('el botón grande abre la edición; no hay nada de IA', (tester) async {
    await abrir(tester, origen: 'manual');
    expect(find.textContaining('IA'), findsNothing);
    await tester.tap(find.text('Corregir ficha'));
    await tester.pumpAndSettle();
    expect(find.text('Guardar'), findsOneWidget);
    expect(find.text('Agregar otro dato'), findsOneWidget);
  });

  testWidgets('quien no puede editar solo mira', (tester) async {
    await abrir(tester, puedeEditar: false);
    expect(find.byTooltip('Editar'), findsNothing);
    expect(find.text('Corregir ficha'), findsNothing);
    expect(find.byTooltip('Copiar'), findsOneWidget);
  });
}
