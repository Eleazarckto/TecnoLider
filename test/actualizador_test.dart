// ============================================================================
//  actualizador_test.dart — Actualización automática (lib/actualizador.dart)
//  Traídas de Brizuela; el .exe de Windows de Tecno Líder es tecno_lider.exe
//  (windows/CMakeLists.txt, BINARY_NAME).
//
//  Las piezas que fallaban en las tiendas, probadas de verdad: version.json
//  con BOM, descarga retomada, paquete cortado o con otra huella, y en
//  Windows el script de instalación corrido con una ruta con tilde y ñ y un
//  archivo bloqueado.
// ============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tecno_lider/actualizador.dart';

String _zip(Directory dir, String nombre, Map<String, String> archivos) {
  final a = Archive();
  archivos.forEach((ruta, contenido) {
    final bytes = utf8.encode(contenido);
    a.addFile(ArchiveFile(ruta, bytes.length, bytes));
  });
  final ruta = '${dir.path}${Platform.pathSeparator}$nombre';
  File(ruta).writeAsBytesSync(ZipEncoder().encode(a)!);
  return ruta;
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('actualizador_'));
  tearDown(() {
    try { tmp.deleteSync(recursive: true); } catch (_) {}
  });

  group('version.json', () {
    test('con BOM y espacios se lee igual', () {
      final i = ActualizadorApp.leerVersionJson(
          '\uFEFF  {"windows": {"version": "1.0.62", "url": "u", "sha256": "ABC", "tamano": "12"}}\n',
          'windows')!;
      expect(i.version, '1.0.62');
      expect(i.sha256, 'abc');
      expect(i.tamano, 12);
    });
    test('sin el bloque de la plataforma: null', () {
      expect(ActualizadorApp.leerVersionJson('{"android": {"version": "1", "url": "u"}}', 'windows'), isNull);
    });
    test('version.json viejo, sin huella: sigue sirviendo', () {
      final i = ActualizadorApp.leerVersionJson('{"android": {"version": "1.0.61", "url": "u"}}', 'android')!;
      expect(i.sha256, '');
      expect(i.tamano, 0);
    });
  });

  test('Content-Range para retomar la descarga', () {
    expect(ActualizadorApp.totalDeContentRange('bytes 100-199/53118852'), 53118852);
    expect(ActualizadorApp.totalDeContentRange('bytes */5000'), 5000);
    expect(ActualizadorApp.totalDeContentRange(null), isNull);
  });

  group('comprobación del paquete', () {
    test('entero, con su huella y su tamaño: bien', () {
      final ruta = _zip(tmp, 'a.zip', {'tecno_lider.exe': 'x', 'data/app.so': 'codigo'});
      final bytes = File(ruta).readAsBytesSync();
      expect(problemaDePaquete(ruta, '${sha256.convert(bytes)}', bytes.length, 'tecno_lider.exe'), isNull);
    });
    test('otra huella: se rechaza', () {
      final ruta = _zip(tmp, 'a.zip', {'tecno_lider.exe': 'x'});
      expect(problemaDePaquete(ruta, 'ab' * 32, 0, 'tecno_lider.exe'), contains('SHA-256'));
    });
    test('cortado a la mitad: se rechaza', () {
      final ruta = _zip(tmp, 'a.zip', {'tecno_lider.exe': 'x' * 5000, 'data/app.so': 'y' * 5000});
      final bytes = File(ruta).readAsBytesSync();
      File(ruta).writeAsBytesSync(bytes.sublist(0, bytes.length ~/ 2));
      expect(problemaDePaquete(ruta, '', 0, 'tecno_lider.exe'), isNotNull);
    });
    test('tamaño distinto al anunciado: se rechaza', () {
      final ruta = _zip(tmp, 'a.zip', {'tecno_lider.exe': 'x'});
      expect(problemaDePaquete(ruta, '', 999999, 'tecno_lider.exe'), contains('mide'));
    });
    test('un APK sin AndroidManifest.xml no es un APK', () {
      final ruta = _zip(tmp, 'a.apk', {'classes.dex': 'x'});
      expect(problemaDePaquete(ruta, '', 0, 'AndroidManifest.xml'), contains('no trae'));
    });
  });

  group('descomprimir la versión de Windows', () {
    // La primera prueba real dejó la carpeta vacía: la extracción no se
    // esperaba. Esto lo comprueba sobre disco.
    test('deja los archivos y devuelve la carpeta con el .exe', () {
      final zip = _zip(tmp, 'w.zip', {
        'tecno_lider.exe': 'exe', 'flutter_windows.dll': 'dll',
        'data/app.so': 'codigo nuevo', 'data/flutter_assets/a.txt': 'x'});
      final destino = '${tmp.path}${Platform.pathSeparator}nueva-1.0.62';
      final carpeta = descomprimirPaquete(zip, destino, 'tecno_lider.exe');
      expect(carpeta, destino);
      expect(File('$destino${Platform.pathSeparator}data${Platform.pathSeparator}app.so')
          .readAsStringSync(), 'codigo nuevo');
    });
    test('zip con todo dentro de una subcarpeta', () {
      final zip = _zip(tmp, 'w.zip', {'Release/tecno_lider.exe': 'exe', 'Release/data/app.so': 'c'});
      final destino = '${tmp.path}${Platform.pathSeparator}n';
      expect(descomprimirPaquete(zip, destino, 'tecno_lider.exe'),
          '$destino${Platform.pathSeparator}Release');
    });
    test('sin el .exe: null (se vuelve a bajar)', () {
      final zip = _zip(tmp, 'w.zip', {'data/app.so': 'c'});
      expect(descomprimirPaquete(zip, '${tmp.path}${Platform.pathSeparator}n', 'tecno_lider.exe'), isNull);
    });
  });

  group('restos del actualizador viejo (1.0.17)', () {
    test('se reconocen los archivos que dejaba en Documentos', () {
      for (final n in ['tecnolider-update-1.0.17.zip', 'tecnolider_update_1.0.17',
          'aplicar_update_tecnolider.bat']) {
        expect(esRestoDelActualizadorViejo(n, android: false), isTrue, reason: n);
      }
      expect(esRestoDelActualizadorViejo('tecnolider-1.0.17.apk', android: true), isTrue);
    });
    test('no toca nada más de Documentos', () {
      for (final n in ['tecnolider-1.0.17.apk', 'Reporte de Ventas.xlsx',
          'factura_66.pdf', 'tecnolider.db']) {
        expect(esRestoDelActualizadorViejo(n, android: false), isFalse, reason: n);
      }
    });
  });

  group('script de Windows', () {
    test('las rutas van entre comillas simples escapadas', () {
      final s = ActualizadorApp.scriptWindows(pid: 1, exe: r"C:\O'Brien\tecno_lider.exe",
          fuente: 'f', destino: 'd', resultado: 'r', log: 'l', reabrir: false);
      expect(s, contains(r"'C:\O''Brien\tecno_lider.exe'"));
      expect(s, contains('Wait-Process -Id 1 '));
      expect(s, isNot(contains('Start-Process -FilePath \$exe')));
    });

    test('reemplaza la instalación aunque la ruta tenga tilde y ñ y un archivo esté bloqueado',
        () async {
      final sep = Platform.pathSeparator;
      final destino = Directory('${tmp.path}${sep}Instalación José Muñoz')..createSync();
      final fuente = Directory('${tmp.path}${sep}nueva ñ')..createSync();
      for (final d in [destino, fuente]) {
        Directory('${d.path}${sep}data').createSync();
      }
      File('${destino.path}${sep}tecno_lider.exe').writeAsStringSync('viejo');
      File('${destino.path}${sep}data${sep}app.so').writeAsStringSync('código viejo');
      File('${fuente.path}${sep}tecno_lider.exe').writeAsStringSync('nuevo');
      File('${fuente.path}${sep}data${sep}app.so').writeAsStringSync('código nuevo 1.0.62');
      File('${fuente.path}${sep}nuevo_plugin.dll').writeAsStringSync('dll');

      // La "app" que tiene que cerrarse antes de copiar.
      final app = await Process.start('ping', ['-n', '3', '127.0.0.1']);
      // Un archivo de la instalación queda bloqueado 3 segundos (antivirus,
      // otra ventana): robocopy tiene que reintentar.
      final bloqueado = File('${destino.path}${sep}data${sep}app.so').openSync(mode: FileMode.append);
      bloqueado.lockSync(FileLock.exclusive);
      Future.delayed(const Duration(seconds: 5), () {
        bloqueado.unlockSync();
        bloqueado.closeSync();
      });

      final resultado = '${tmp.path}${sep}resultado.txt';
      final log = '${tmp.path}${sep}instalación.log';
      final script = ActualizadorApp.scriptWindows(
          pid: app.pid, exe: '${destino.path}${sep}tecno_lider.exe',
          fuente: fuente.path, destino: destino.path,
          resultado: resultado, log: log, reabrir: false);
      final ps1 = File('${tmp.path}${sep}instalar ñ.ps1')
        ..writeAsBytesSync([0xEF, 0xBB, 0xBF, ...utf8.encode(script)]);
      final r = await Process.run('powershell.exe',
          ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ps1.path]);
      final registro = File(log).existsSync() ? File(log).readAsStringSync() : '(sin log)';

      expect(File(resultado).readAsStringSync().trim(), 'ok',
          reason: 'stdout: ${r.stdout}\nstderr: ${r.stderr}\nlog: $registro');
      expect(File('${destino.path}${sep}data${sep}app.so').readAsStringSync(), 'código nuevo 1.0.62');
      expect(File('${destino.path}${sep}tecno_lider.exe').readAsStringSync(), 'nuevo');
      expect(File('${destino.path}${sep}nuevo_plugin.dll').existsSync(), isTrue);
    }, skip: !Platform.isWindows, timeout: const Timeout(Duration(minutes: 3)));
  });
}
