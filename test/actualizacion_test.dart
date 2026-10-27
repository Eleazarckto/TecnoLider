// ============================================================================
//  actualizacion_test.dart — Cuándo la actualización es obligatoria
//
//  Traído de Brizuela (lib/actualizador.dart). El servidor puede exigir
//  actualizar a quien quedó muy atrás (version_minima, max_versiones_atras
//  en version.json). Estas pruebas fijan esa regla: obliga a quien debe y a
//  nadie más.
// ============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:tecno_lider/main.dart';

InfoActualizacion _info({
  String version = '1.0.47',
  bool obligatoria = false,
  String minima = '',
  int maxAtras = 0,
}) =>
    InfoActualizacion(
        version: version,
        url: 'https://x/app.apk',
        obligatoria: obligatoria,
        versionMinima: minima,
        maxVersionesAtras: maxAtras);

void main() {
  group('Versiones atrás', () {
    test('cuenta parches con la misma mayor y menor', () {
      expect(ActualizadorApp.versionesAtras('1.0.47', '1.0.40'), 7);
      expect(ActualizadorApp.versionesAtras('1.0.47', '1.0.46'), 1);
    });
    test('al día o por delante: 0', () {
      expect(ActualizadorApp.versionesAtras('1.0.47', '1.0.47'), 0);
      expect(ActualizadorApp.versionesAtras('1.0.47', '1.0.50'), 0);
    });
    test('otra mayor o menor cuenta como muy atrás', () {
      expect(ActualizadorApp.versionesAtras('1.1.0', '1.0.47'), 1000);
      expect(ActualizadorApp.versionesAtras('2.0.0', '1.9.9'), 1000);
    });
  });

  group('¿Obligatoria?', () {
    test('sin reglas, nunca', () {
      expect(ActualizadorApp.debeSerObligatoria(_info(), '1.0.10'), isFalse);
    });
    test('marcada obligatoria en el servidor: siempre', () {
      expect(ActualizadorApp.debeSerObligatoria(_info(obligatoria: true), '1.0.46'), isTrue);
    });
    test('por debajo de la versión mínima: sí; en ella o por encima: no', () {
      final i = _info(minima: '1.0.45');
      expect(ActualizadorApp.debeSerObligatoria(i, '1.0.44'), isTrue);
      expect(ActualizadorApp.debeSerObligatoria(i, '1.0.45'), isFalse);
      expect(ActualizadorApp.debeSerObligatoria(i, '1.0.46'), isFalse);
    });
    test('más de N versiones atrás: sí; hasta N: no', () {
      final i = _info(maxAtras: 5);
      expect(ActualizadorApp.debeSerObligatoria(i, '1.0.42'), isFalse, reason: '5 atrás');
      expect(ActualizadorApp.debeSerObligatoria(i, '1.0.41'), isTrue, reason: '6 atrás');
    });
    test('el version.json se lee con las dos reglas', () {
      final i = InfoActualizacion.fromMap({
        'version': '1.0.47', 'url': 'u', 'obligatoria': false,
        'version_minima': ' 1.0.40 ', 'max_versiones_atras': '5',
      });
      expect(i.versionMinima, '1.0.40');
      expect(i.maxVersionesAtras, 5);
      expect(i.conObligatoria(true).versionMinima, '1.0.40');
    });
    test('un version.json viejo, sin los campos nuevos, no obliga a nadie', () {
      final i = InfoActualizacion.fromMap({'version': '1.0.47', 'url': 'u'});
      expect(ActualizadorApp.debeSerObligatoria(i, '1.0.1'), isFalse);
    });
  });

  test('el version.json del repositorio se lee en las dos plataformas y no obliga a quien está al día', () {
    final d = jsonDecode(File('backend/version.json').readAsStringSync()) as Map;
    for (final p in ['android', 'windows']) {
      final i = ActualizadorApp.leerVersionJson(jsonEncode(d), p)!;
      expect(i.version, kAppVersion, reason: p);
      expect(i.url, contains('tecnolider'), reason: p);
      // Publicar este archivo no puede dejar fuera a quien está al día.
      expect(ActualizadorApp.debeSerObligatoria(i, i.version), isFalse, reason: p);
    }
  });
}
