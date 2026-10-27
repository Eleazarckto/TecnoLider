// ============================================================================
//  actualizador.dart — Actualización automática (Android y Windows)
//
//  Traído de Brizuela a Tecno Líder (incluye la 1.0.72 de Brizuela: tablets
//  Xiaomi con HyperOS, y la lectura de version.json como UTF-8).
//
//  Dueño, 10/10/2026: «el sistema OTA es para que el sistema descargue la
//  actualización sin necesidad de otras cosas». Lo que fallaba antes:
//
//   · Se buscaba UNA vez, al abrir, y solo en dos pantallas (panel y
//     ventas). Un equipo que pasa días abierto, o que entra por otra
//     pantalla, no se enteraba nunca.
//   · El aviso tenía «Más tarde» y la descarga (100 MB) solo avanzaba con
//     el aviso en pantalla; si se cortaba, empezaba de cero.
//   · Windows: un .bat con xcopy que no comprobaba nada. Rutas con tildes o
//     ñ, carpetas sin permiso o un archivo en uso dejaban la versión vieja
//     y volvía a abrirla sin decir nada. El zip llevaba además un zip viejo
//     adentro (el doble de descarga).
//   · Android: el instalador pedía «Instalar» en cada versión.
//   · Nadie sabía qué versión tenía cada equipo.
//
//  Ahora, desde que abre la app (cualquier pantalla, con o sin sesión):
//
//   1. Revisa version.json al abrir y cada 30 minutos (sin caché).
//   2. Descarga sola en segundo plano, retomando donde se cortó, y
//      comprueba el paquete (tamaño, SHA-256 y que el zip esté entero).
//   3. Instala sola:
//        Windows → al abrir la app, al cerrarla, o tras 10 minutos sin uso
//                  (se cierra y vuelve a abrir ya actualizada). Copia con
//                  robocopy y reintentos, comprueba que el código nuevo
//                  quedó, y si la carpeta pide permiso de administrador lo
//                  pide una vez.
//        Android → PackageInstaller (Actualizador.kt): en Android 12 o más
//                  nuevo, sin tocar nada; se instala al salir de la app o
//                  tras 10 minutos sin uso y avisa «toca para abrir».
//   4. Comprueba al volver a abrir que quedó la versión nueva; si no, lo
//      reintenta (3 veces por día) y lo muestra.
//   5. Puede reportar la versión y el estado de cada equipo (`reportar`).
//      En Tecno Líder todavía no hay app_equipos en el servidor: main.dart
//      pasa un reportar que no hace nada.
//
//  Compatibilidad: la 1.0.17 y anteriores (actualizador viejo) leen de
//  version.json solo version/url/obligatoria/notas; sha256 y tamano son
//  campos nuevos que esas versiones ignoran.
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:ui' show AppExitResponse;

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Lo que anuncia version.json para una plataforma.
class InfoActualizacion {
  final String version;
  final String url;
  final bool obligatoria;
  final String notas;

  /// Versión más vieja que se deja seguir usando. Vacía = sin mínimo.
  final String versionMinima;

  /// Cuántas versiones puede quedar atrás un equipo antes de que la
  /// actualización pase a ser obligatoria. 0 = regla apagada.
  final int maxVersionesAtras;

  /// SHA-256 (hex) y tamaño en bytes del paquete. Vacío / 0 en un
  /// version.json viejo: entonces se comprueba solo que el zip esté entero.
  final String sha256;
  final int tamano;

  InfoActualizacion({
    required this.version, required this.url,
    this.obligatoria = false, this.notas = '',
    this.versionMinima = '', this.maxVersionesAtras = 0,
    this.sha256 = '', this.tamano = 0});

  factory InfoActualizacion.fromMap(Map<String, dynamic> m) =>
      InfoActualizacion(
        version: (m['version'] ?? '').toString().trim(),
        url: (m['url'] ?? '').toString().trim(),
        obligatoria: m['obligatoria'] == true || m['obligatoria'] == 1,
        notas: (m['notas'] ?? '').toString(),
        versionMinima: (m['version_minima'] ?? '').toString().trim(),
        maxVersionesAtras:
            int.tryParse('${m['max_versiones_atras'] ?? 0}') ?? 0,
        sha256: (m['sha256'] ?? '').toString().trim().toLowerCase(),
        tamano: int.tryParse('${m['tamano'] ?? 0}') ?? 0);

  InfoActualizacion conObligatoria(bool valor) => InfoActualizacion(
      version: version, url: url, obligatoria: valor, notas: notas,
      versionMinima: versionMinima, maxVersionesAtras: maxVersionesAtras,
      sha256: sha256, tamano: tamano);
}

/// Reglas de versiones (sin red ni archivos: se prueban solas).
class ActualizadorApp {
  static List<int> _partes(String v) {
    final p = v
        .split('.')
        .map((x) => int.tryParse(x.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();
    while (p.length < 3) {
      p.add(0);
    }
    return p;
  }

  /// true si `remota` es MÁS NUEVA que `local` ("MAYOR.MENOR.PARCHE").
  static bool esMasNueva(String remota, String local) {
    final r = _partes(remota), l = _partes(local);
    final n = max(r.length, l.length);
    for (int i = 0; i < n; i++) {
      final a = i < r.length ? r[i] : 0;
      final b = i < l.length ? l[i] : 0;
      if (a > b) return true;
      if (a < b) return false;
    }
    return false;
  }

  /// Cuántas versiones está `local` por detrás de `remota`. Con otra MAYOR
  /// o MENOR no se pueden contar parches: 1000 («muy atrás»).
  static int versionesAtras(String remota, String local) {
    if (!esMasNueva(remota, local)) return 0;
    final r = _partes(remota), l = _partes(local);
    if (r[0] != l[0] || r[1] != l[1]) return 1000;
    return r[2] - l[2];
  }

  /// ¿Obligatoria para ESTE equipo? Si el servidor la marca, si está por
  /// debajo de `version_minima` o si quedó más de `max_versiones_atras`.
  static bool debeSerObligatoria(InfoActualizacion info, String local) {
    if (info.obligatoria) return true;
    if (info.versionMinima.isNotEmpty &&
        esMasNueva(info.versionMinima, local)) {
      return true;
    }
    return info.maxVersionesAtras > 0 &&
        versionesAtras(info.version, local) > info.maxVersionesAtras;
  }

  /// Lee version.json (tolera BOM y espacios) y devuelve el bloque de la
  /// plataforma, o null si no lo trae completo.
  static InfoActualizacion? leerVersionJson(String cuerpo, String plataforma) {
    var texto = cuerpo.trim();
    if (texto.startsWith('\uFEFF')) texto = texto.substring(1);
    final data = jsonDecode(texto);
    if (data is! Map || data[plataforma] is! Map) return null;
    final info = InfoActualizacion.fromMap(
        Map<String, dynamic>.from(data[plataforma] as Map));
    if (info.version.isEmpty || info.url.isEmpty) return null;
    return info;
  }

  /// Tamaño total de un `Content-Range: bytes 100-199/5000` (o `*/5000`).
  static int? totalDeContentRange(String? cabecera) {
    if (cabecera == null) return null;
    final m = RegExp(r'/(\d+)\s*$').firstMatch(cabecera.trim());
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  /// Texto para PowerShell entre comillas simples.
  static String ps(String s) => "'${s.replaceAll("'", "''")}'";

  /// Script que reemplaza la instalación de Windows con la carpeta nueva.
  ///
  /// PowerShell y no .bat: un .bat se lee con la página de códigos de la
  /// consola y una ruta con tilde o ñ (C:\Users\José\…) se rompía. Espera a
  /// que la app cierre, copia con robocopy (reintenta si un archivo está en
  /// uso), comprueba que el código nuevo (data\app.so) quedó idéntico y, si
  /// la carpeta no deja escribir, pide permiso de administrador una vez.
  /// Deja «ok» o «error …» en `resultado` y lo que hizo en `log`.
  static String scriptWindows({
    required int pid,
    required String exe,
    required String fuente,
    required String destino,
    required String resultado,
    required String log,
    required bool reabrir,
  }) => '''
param([switch]\$Elevado)
\$ErrorActionPreference = 'Continue'
\$log = ${ps(log)}
\$exe = ${ps(exe)}
\$fuente = ${ps(fuente)}
\$destino = ${ps(destino)}
\$resultado = ${ps(resultado)}
function Anotar(\$m) { try { Add-Content -LiteralPath \$log -Value ((Get-Date).ToString('s') + ' ' + \$m) } catch {} }
function Huella(\$ruta) {
  try {
    \$f = [IO.File]::OpenRead(\$ruta)
    try { return [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash(\$f)) } finally { \$f.Close() }
  } catch { return '' }
}
function Copiar {
  \$rc = 99
  for (\$i = 1; \$i -le 5; \$i++) {
    & robocopy \$fuente \$destino /E /IS /IT /R:3 /W:2 /NP /NJH /NJS /NFL /NDL | Out-Null
    \$rc = \$LASTEXITCODE
    Anotar ('robocopy intento ' + \$i + ' -> ' + \$rc)
    if (\$rc -lt 8) { break }
    Start-Sleep -Seconds 3
  }
  return \$rc
}
function Quedo {
  \$a = Huella (Join-Path \$fuente 'data\\app.so')
  \$b = Huella (Join-Path \$destino 'data\\app.so')
  return (\$a -ne '' -and \$a -eq \$b)
}
Anotar ('inicio elevado=' + [bool]\$Elevado)
if (\$Elevado) {
  \$rc = Copiar
  Anotar ('como administrador -> ' + \$rc)
  exit
}
try { Wait-Process -Id $pid -Timeout 60 -ErrorAction SilentlyContinue } catch {}
\$nombre = [IO.Path]::GetFileNameWithoutExtension(\$exe)
Get-Process -Name \$nombre -ErrorAction SilentlyContinue | Where-Object { \$_.Path -eq \$exe } | ForEach-Object {
  Anotar ('cerrando proceso ' + \$_.Id)
  Stop-Process -Id \$_.Id -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 2
\$rc = Copiar
\$ok = Quedo
if (-not \$ok) {
  Anotar 'no quedo: se pide permiso de administrador'
  try {
    \$yo = \$MyInvocation.MyCommand.Path
    \$p = Start-Process -FilePath 'powershell.exe' -Verb RunAs -PassThru -Wait -WindowStyle Hidden -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + \$yo + '"'), '-Elevado')
    \$ok = Quedo
  } catch { Anotar ('sin permiso de administrador: ' + \$_) }
}
if (\$ok) { Set-Content -LiteralPath \$resultado -Value 'ok' } else { Set-Content -LiteralPath \$resultado -Value ('error robocopy ' + \$rc) }
Anotar ('resultado ok=' + \$ok)
${reabrir ? r"Start-Process -FilePath $exe -WorkingDirectory $destino" : "# la app se cerró a propósito: no se vuelve a abrir"}
''';
}

/// En qué anda el actualizador.
enum FaseActualizacion { alDia, descargando, lista, instalando, error, sinPermiso }

class EstadoActualizacion {
  final FaseActualizacion fase;
  final String version;
  final double progreso;
  final String detalle;
  const EstadoActualizacion(this.fase,
      {this.version = '', this.progreso = 0, this.detalle = ''});
}

/// Datos del equipo y de la sesión para el reporte.
typedef DatosReporte = Map<String, dynamic> Function();

class MotorActualizacion {
  MotorActualizacion._();
  static final MotorActualizacion instancia = MotorActualizacion._();

  static const _canal = MethodChannel('tl/instalador');
  static const _cadaCuanto = Duration(minutes: 30);
  static const _sinUso = Duration(minutes: 10);
  static const _maxIntentosPorDia = 3;

  final estado = ValueNotifier<EstadoActualizacion>(
      const EstadoActualizacion(FaseActualizacion.alDia));

  String _versionLocal = '';
  String _urlJson = '';
  Future<void> Function(Map<String, dynamic>)? _reportar;
  DatosReporte? _datos;
  bool _iniciado = false;
  bool _revisando = false;
  bool _instalando = false;
  bool _enPantalla = true;
  DateTime _ultimaRevision = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _ultimoUso = DateTime.now();
  InfoActualizacion? _info;
  File? _paquete;           // APK o zip verificado
  String? _carpetaNueva;    // Windows: zip ya descomprimido
  String _equipoId = '';
  Map<String, dynamic> _equipo = {};
  // ignore: unused_field
  AppLifecycleListener? _ciclo;

  static bool get soportado => Platform.isAndroid || Platform.isWindows;
  static String get _plataforma => Platform.isAndroid ? 'android' : 'windows';

  // ── Carpeta y estado guardado ─────────────────────────────────────

  static Future<Directory> _carpeta() async {
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}${Platform.pathSeparator}actualizaciones');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static String _en(Directory d, String nombre) =>
      '${d.path}${Platform.pathSeparator}$nombre';

  static Future<Map<String, dynamic>> _leerEstado(Directory d) async {
    try {
      final f = File(_en(d, 'estado.json'));
      if (await f.exists()) {
        return Map<String, dynamic>.from(jsonDecode(await f.readAsString()) as Map);
      }
    } catch (_) {}
    return {};
  }

  static Future<void> _guardarEstado(Directory d, Map<String, dynamic> e) async {
    try {
      await File(_en(d, 'estado.json')).writeAsString(jsonEncode(e), flush: true);
    } catch (_) {}
  }

  /// Intentos de instalar en las últimas 24 horas (se reinicia solo).
  static int _intentosHoy(Map<String, dynamic> e) {
    final cuando = DateTime.tryParse('${e['ultimo_intento'] ?? ''}');
    if (cuando == null || DateTime.now().difference(cuando) > const Duration(hours: 24)) {
      return 0;
    }
    return (e['intentos'] as num?)?.toInt() ?? 0;
  }

  // ── Windows: instalar al arrancar ─────────────────────────────────

  /// Se llama ANTES de dibujar la app. Si hay una versión nueva ya
  /// descargada y descomprimida, la instala ya (no hay nada abierto que
  /// perder) y devuelve true: quien llama cierra la app.
  /// ¿Se lanzó un instalador hace menos de 2 minutos? Mientras copia no se
  /// lanza otro (dos a la vez se pisaban: el segundo no encontraba la
  /// carpeta nueva porque la app ya actualizada la había borrado).
  static bool _instaladorTrabajando(Map<String, dynamic> e) {
    final cuando = DateTime.tryParse('${e['ultimo_intento'] ?? ''}');
    return cuando != null && DateTime.now().difference(cuando) < const Duration(minutes: 2);
  }

  static Future<bool> instalarPendienteAlArrancar(String versionLocal) async {
    if (!Platform.isWindows) return false;
    try {
      final d = await _carpeta();
      final e = await _leerEstado(d);
      final objetivo = '${e['lista'] ?? ''}';
      final carpeta = '${e['carpeta'] ?? ''}';
      if (objetivo.isEmpty || !ActualizadorApp.esMasNueva(objetivo, versionLocal)) return false;
      if (carpeta.isEmpty || !await Directory(carpeta).exists()) return false;
      if (_intentosHoy(e) >= _maxIntentosPorDia) return false;
      if (_instaladorTrabajando(e)) {
        await anotar('arranque $versionLocal: ya hay un instalador trabajando, no se lanza otro');
        return false;
      }
      await anotar('arranque $versionLocal: hay ${e['lista']} lista, se instala ya');
      return await _lanzarWindows(d, e, objetivo, carpeta, versionLocal, reabrir: true);
    } catch (e) {
      debugPrint('[Actualizador] al arrancar: $e');
      return false;
    }
  }

  static Future<bool> _lanzarWindows(Directory d, Map<String, dynamic> e,
      String objetivo, String carpeta, String versionLocal,
      {required bool reabrir}) async {
    final exe = Platform.resolvedExecutable;
    final destino = File(exe).parent.path;
    final resultado = _en(d, 'resultado.txt');
    final log = _en(d, 'instalacion.log');
    try { await File(resultado).delete(); } catch (_) {}
    final script = ActualizadorApp.scriptWindows(
        pid: pid, exe: exe, fuente: carpeta, destino: destino,
        resultado: resultado, log: log, reabrir: reabrir);
    final ruta = _en(d, 'instalar.ps1');
    // Con BOM: PowerShell 5 lee así las tildes y la ñ de las rutas.
    await File(ruta).writeAsBytes([0xEF, 0xBB, 0xBF, ...utf8.encode(script)], flush: true);
    e['intentos'] = _intentosHoy(e) + 1;
    e['ultimo_intento'] = DateTime.now().toIso8601String();
    e['objetivo'] = objetivo;
    e['desde'] = versionLocal;
    await _guardarEstado(d, e);
    final raiz = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    var powershell = '$raiz\\System32\\WindowsPowerShell\\v1.0\\powershell.exe';
    if (!await File(powershell).exists()) powershell = 'powershell.exe';
    var cmd = '$raiz\\System32\\cmd.exe';
    if (!await File(cmd).exists()) cmd = 'cmd.exe';
    // Por `cmd /c start` y no directo: PowerShell lanzado desprendido de una
    // app sin consola no llega a correr (probado el 10/10/2026: el script
    // quedaba escrito y la versión vieja seguía). `start` le da su consola,
    // que -WindowStyle Hidden esconde enseguida.
    await Process.start(cmd,
        ['/c', 'start', '""', '/min', powershell,
         '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', ruta],
        mode: ProcessStartMode.detached);
    await anotar('instalador lanzado hacia $objetivo (reabrir: $reabrir)');
    return true;
  }

  // ── Arranque del motor ────────────────────────────────────────────

  /// Arranca el actualizador para toda la vida de la app. Se llama una vez,
  /// después de `runApp`.
  Future<void> iniciar({
    required String versionLocal,
    required String urlVersionJson,
    required Future<void> Function(Map<String, dynamic>) reportar,
    required DatosReporte datos,
  }) async {
    if (!soportado || _iniciado) return;
    _iniciado = true;
    _versionLocal = versionLocal;
    _urlJson = urlVersionJson;
    _reportar = reportar;
    _datos = datos;
    try {
      final d = await _carpeta();
      _equipoId = await _idEquipo(d);
      _equipo = await _datosEquipo();
      await _limpiarVersionVieja();
      await _comprobarInstalacionAnterior(d);
    } catch (e) {
      debugPrint('[Actualizador] inicio: $e');
    }
    _escucharUso();
    _ciclo = AppLifecycleListener(
      onStateChange: _cambioDeEstado,
      onExitRequested: _alCerrar,
    );
    Timer.periodic(const Duration(minutes: 1), (_) => _tic());
    unawaited(revisar());
  }

  static Future<String> _idEquipo(Directory d) async {
    final f = File(_en(d, 'equipo_id'));
    try {
      if (await f.exists()) {
        final id = (await f.readAsString()).trim();
        if (id.length >= 16) return id;
      }
    } catch (_) {}
    final r = Random.secure();
    final id = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    try { await f.writeAsString(id, flush: true); } catch (_) {}
    return id;
  }

  static Future<Map<String, dynamic>> _datosEquipo() async {
    if (Platform.isAndroid) {
      try {
        final m = await _canal.invokeMapMethod<String, dynamic>('equipo');
        return {'equipo': m?['modelo'] ?? 'Android', 'sistema': 'Android API ${m?['android'] ?? '?'}'};
      } catch (_) {
        return {'equipo': 'Android', 'sistema': Platform.operatingSystemVersion};
      }
    }
    return {'equipo': Platform.localHostname, 'sistema': Platform.operatingSystemVersion};
  }

  /// Borra lo que dejaba el actualizador anterior de Tecno Líder (1.0.17 y
  /// anteriores) en Documentos: tecnolider-<versión>.apk en Android;
  /// tecnolider-update-<versión>.zip, la carpeta tecnolider_update_<versión>
  /// y aplicar_update_tecnolider.bat en Windows (cada versión dejaba ahí el
  /// paquete entero).
  static Future<void> _limpiarVersionVieja() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      await for (final ent in docs.list()) {
        final nombre = ent.path.split(RegExp(r'[\\/]')).last;
        final viejo = esRestoDelActualizadorViejo(nombre, android: Platform.isAndroid);
        if (viejo) {
          try { await ent.delete(recursive: true); } catch (_) {}
        }
      }
    } catch (_) {}
  }

  /// ¿Se instaló lo que se intentó la vez anterior? Se reporta en los dos
  /// casos; si falló, queda para reintentar.
  Future<void> _comprobarInstalacionAnterior(Directory d) async {
    final e = await _leerEstado(d);
    final objetivo = '${e['objetivo'] ?? ''}';
    var nativo = <String, dynamic>{};
    if (Platform.isAndroid) {
      try {
        nativo = await _canal.invokeMapMethod<String, dynamic>('resultado') ?? {};
      } catch (_) {}
    }
    if (objetivo.isEmpty) return;
    if (!ActualizadorApp.esMasNueva(objetivo, _versionLocal)) {
      // Quedó: se avisa y se borra lo descargado.
      _enviar('instalada', detalle: 'Desde ${e['desde'] ?? '?'}');
      await _borrarDescargas(d);
      if (Platform.isAndroid) {
        try { await _canal.invokeMethod('limpiarResultado'); } catch (_) {}
      }
      return;
    }
    // Sigue la versión vieja: no se instaló.
    String detalle;
    if (Platform.isWindows) {
      final res = await _leerTexto(_en(d, 'resultado.txt'));
      final log = await _leerTexto(_en(d, 'instalacion.log'));
      final cola = log.split('\n').where((l) => l.trim().isNotEmpty).toList();
      detalle = '${res.isEmpty ? 'sin resultado (el instalador no corrió)' : res}'
          '${cola.isEmpty ? '' : ' · ${cola.skip(max(0, cola.length - 4)).join(' | ')}'}';
    } else {
      final est = '${nativo['estado'] ?? ''}';
      detalle = est == 'error'
          ? '${nativo['detalle']}'
          : est == 'confirmar'
              ? 'Android espera que se confirme la instalación'
              : 'La instalación no terminó ($est)';
    }
    _fijar(FaseActualizacion.error, version: objetivo, detalle: detalle);
    _enviar('error', detalle: 'No se instaló $objetivo: $detalle');
  }

  static Future<String> _leerTexto(String ruta) async {
    try {
      final f = File(ruta);
      return await f.exists() ? (await f.readAsString()).trim() : '';
    } catch (_) {
      return '';
    }
  }

  static Future<void> _borrarDescargas(Directory d) async {
    try {
      await for (final ent in d.list()) {
        final nombre = ent.path.split(RegExp(r'[\\/]')).last;
        if (nombre == 'equipo_id' || nombre == 'motor.log' || nombre == 'instalacion.log') continue;
        try { await ent.delete(recursive: true); } catch (_) {}
      }
    } catch (_) {}
  }

  // ── Uso y ciclo de vida ───────────────────────────────────────────

  void _escucharUso() {
    void tocar() => _ultimoUso = DateTime.now();
    GestureBinding.instance.pointerRouter.addGlobalRoute((_) => tocar());
    HardwareKeyboard.instance.addHandler((_) {
      tocar();
      return false;
    });
  }

  void _cambioDeEstado(AppLifecycleState s) {
    _enPantalla = s == AppLifecycleState.resumed;
    if (s == AppLifecycleState.resumed) {
      _ultimoUso = DateTime.now();
      if (Platform.isAndroid) unawaited(_revisarPermisoAndroid());
      if (DateTime.now().difference(_ultimaRevision) >= _cadaCuanto) unawaited(revisar());
    }
    // Android: al salir de la app se instala sin interrumpir a nadie.
    if (Platform.isAndroid &&
        (s == AppLifecycleState.paused || s == AppLifecycleState.hidden) &&
        estado.value.fase == FaseActualizacion.lista) {
      unawaited(instalarAhora());
    }
  }

  /// Windows: el usuario cierra la app y hay una versión lista → se instala
  /// sin volver a abrirla.
  Future<AppExitResponse> _alCerrar() async {
    if (Platform.isWindows && estado.value.fase == FaseActualizacion.lista &&
        _carpetaNueva != null && _info != null) {
      try {
        final d = await _carpeta();
        final e = await _leerEstado(d);
        if (!_instaladorTrabajando(e)) {
          await _lanzarWindows(d, e, _info!.version, _carpetaNueva!, _versionLocal, reabrir: false);
        }
      } catch (e) {
        debugPrint('[Actualizador] al cerrar: $e');
      }
    }
    return AppExitResponse.exit;
  }

  void _tic() {
    final ahora = DateTime.now();
    final f = estado.value.fase;
    final espera = f == FaseActualizacion.error ? const Duration(minutes: 10) : _cadaCuanto;
    if (!_revisando && ahora.difference(_ultimaRevision) >= espera) {
      unawaited(revisar());
    }
    if (f == FaseActualizacion.lista &&
        (ahora.difference(_ultimoUso) >= _sinUso || (_info?.obligatoria ?? false))) {
      // Android solo si está en pantalla: en segundo plano ya se instaló.
      if (Platform.isWindows || _enPantalla) unawaited(instalarAhora());
    }
  }

  // ── Revisar y descargar ───────────────────────────────────────────

  /// Revisa version.json y, si hay versión nueva, la descarga y la deja
  /// lista. `manual`: el usuario tocó «Buscar actualización».
  Future<void> revisar({bool manual = false}) async {
    if (!soportado || !_iniciado || _revisando) return;
    _revisando = true;
    unawaited(anotar('revisar${manual ? ' (manual)' : ''} desde $_versionLocal'));
    _ultimaRevision = DateTime.now();
    try {
      final info = await _consultar();
      if (info == null) {
        if (manual) _fijar(estado.value.fase, detalle: 'Sin conexión con el servidor');
        return;
      }
      if (!ActualizadorApp.esMasNueva(info.version, _versionLocal)) {
        _info = null;
        _fijar(FaseActualizacion.alDia);
        _enviar('al_dia');
        return;
      }
      _info = info.conObligatoria(ActualizadorApp.debeSerObligatoria(info, _versionLocal));
      final d = await _carpeta();
      final e = await _leerEstado(d);
      final yaLista = e['lista'] == info.version && _paquete != null && await _paquete!.exists();
      if (yaLista) {
        if (estado.value.fase != FaseActualizacion.error || manual) {
          _fijar(FaseActualizacion.lista, version: info.version);
        }
        _enviar(estado.value.fase == FaseActualizacion.error ? 'error' : 'descargada',
            detalle: estado.value.detalle);
        if (manual && estado.value.fase == FaseActualizacion.error) {
          e['intentos'] = 0;
          await _guardarEstado(d, e);
        }
        return;
      }
      if (Platform.isAndroid) await _revisarPermisoAndroid();
      await _bajar(d, info);
      if (_info!.obligatoria && (Platform.isWindows || _enPantalla)) {
        unawaited(instalarAhora());
      }
    } catch (e) {
      final detalle = '$e'.replaceFirst('Exception: ', '');
      _fijar(FaseActualizacion.error, version: _info?.version ?? '', detalle: detalle);
      _enviar('error', detalle: detalle);
    } finally {
      _revisando = false;
    }
  }

  Future<InfoActualizacion?> _consultar() async {
    for (int intento = 1; intento <= 3; intento++) {
      try {
        // ?t= y no-cache: un proxy o la caché del sistema no puede
        // devolver el version.json de ayer.
        final sep = _urlJson.contains('?') ? '&' : '?';
        final resp = await http.get(
            Uri.parse('$_urlJson${sep}t=${DateTime.now().millisecondsSinceEpoch}'),
            headers: {'Cache-Control': 'no-cache', 'Pragma': 'no-cache'},
        ).timeout(const Duration(seconds: 20));
        if (resp.statusCode == 200) {
          return ActualizadorApp.leerVersionJson(utf8.decode(resp.bodyBytes), _plataforma);
        }
      } catch (e) {
        debugPrint('[Actualizador] version.json intento $intento: $e');
      }
      await Future.delayed(Duration(seconds: 3 * intento));
    }
    return null;
  }

  Future<void> _bajar(Directory d, InfoActualizacion info) async {
    // Dos ventanas de la app en la misma PC: baja una sola.
    final candado = await File(_en(d, 'descarga.lock')).open(mode: FileMode.append);
    try {
      try {
        await candado.lock(FileLock.exclusive);
      } catch (_) {
        throw Exception('Otra ventana de la app ya está descargando');
      }
      final ext = Platform.isAndroid ? 'apk' : 'zip';
      final fin = File(_en(d, 'tecnolider-${info.version}.$ext'));
      // Lo de otras versiones sobra.
      await for (final ent in d.list()) {
        final n = ent.path.split(RegExp(r'[\\/]')).last;
        final esPaquete = n.startsWith('tecnolider-') || n.startsWith('nueva-');
        if (esPaquete && !n.contains(info.version)) {
          try { await ent.delete(recursive: true); } catch (_) {}
        }
      }
      if (!(await fin.exists() && await _problema(fin.path, info) == null)) {
        _fijar(FaseActualizacion.descargando, version: info.version);
        _enviar('descargando');
        await _descargar(info, fin);
      }
      String? carpeta;
      if (Platform.isWindows) {
        final destino = _en(d, 'nueva-${info.version}');
        carpeta = await _descomprimirAparte(fin.path, destino);
        if (carpeta == null) {
          try { await fin.delete(); } catch (_) {}
          throw Exception('El paquete descomprimido no trae la app: se vuelve a bajar');
        }
      }
      final e = await _leerEstado(d);
      if (e['lista'] != info.version) {
        e['intentos'] = 0;
      }
      e['lista'] = info.version;
      e['paquete'] = fin.path;
      if (carpeta != null) e['carpeta'] = carpeta;
      await _guardarEstado(d, e);
      _paquete = fin;
      _carpetaNueva = carpeta;
      _fijar(FaseActualizacion.lista, version: info.version);
      _enviar('descargada');
    } finally {
      try { await candado.unlock(); } catch (_) {}
      await candado.close();
    }
  }

  /// Baja `info.url` a `fin`, retomando lo ya bajado (`.parte`). Una
  /// conexión que se queda quieta 90 s se corta y se retoma: antes una
  /// descarga colgada podía esperar 12 horas.
  Future<void> _descargar(InfoActualizacion info, File fin) async {
    final parte = File('${fin.path}.parte');
    Object? ultimo;
    for (int intento = 1; intento <= 8; intento++) {
      final cliente = http.Client();
      IOSink? salida;
      try {
        var desde = await parte.exists() ? await parte.length() : 0;
        if (info.tamano > 0 && desde > info.tamano) {
          await parte.delete();
          desde = 0;
        }
        final req = http.Request('GET', Uri.parse(info.url));
        req.headers['Accept-Encoding'] = 'identity';
        req.headers['Cache-Control'] = 'no-cache';
        if (desde > 0) req.headers['Range'] = 'bytes=$desde-';
        final resp = await cliente.send(req).timeout(const Duration(minutes: 2));
        int total;
        if (resp.statusCode == 416) {
          // Ya estaba todo bajado.
          await resp.stream.drain<void>();
          total = ActualizadorApp.totalDeContentRange(resp.headers['content-range']) ?? desde;
          if (desde != total) {
            await parte.delete();
            throw Exception('La descarga parcial no coincide: se empieza de nuevo');
          }
        } else if (resp.statusCode == 206 || resp.statusCode == 200) {
          if (resp.statusCode == 200) desde = 0;   // el servidor no retoma
          total = resp.statusCode == 206
              ? (ActualizadorApp.totalDeContentRange(resp.headers['content-range']) ?? info.tamano)
              : (resp.contentLength ?? info.tamano);
          salida = parte.openWrite(mode: desde > 0 ? FileMode.append : FileMode.write);
          var recibido = desde;
          await for (final trozo in resp.stream.timeout(const Duration(seconds: 90))) {
            salida.add(trozo);
            recibido += trozo.length;
            if (total > 0) {
              _fijar(FaseActualizacion.descargando,
                  version: info.version, progreso: recibido / total);
            }
          }
          await salida.flush();
          await salida.close();
          salida = null;
        } else {
          await resp.stream.drain<void>();
          throw Exception('El servidor respondió ${resp.statusCode} al bajar ${info.version}');
        }
        final tam = await parte.length();
        if (total > 0 && tam < total) {
          throw Exception('Descarga incompleta ($tam de $total bytes)');
        }
        if (await fin.exists()) await fin.delete();
        await parte.rename(fin.path);
        final problema = await _problema(fin.path, info);
        if (problema != null) {
          await fin.delete();
          throw Exception('Paquete dañado: $problema');
        }
        return;
      } catch (e) {
        ultimo = e;
        debugPrint('[Actualizador] descarga intento $intento: $e');
        try { await salida?.close(); } catch (_) {}
        await Future.delayed(Duration(seconds: min(60, 5 * intento)));
      } finally {
        cliente.close();
      }
    }
    throw Exception('No se pudo bajar la versión ${info.version}: '
        '${'$ultimo'.replaceFirst('Exception: ', '')}');
  }

  // Solo valores simples al otro isolate (un cierre de un método de
  // instancia arrastraría objetos que no se pueden mandar).
  static Future<String?> _descomprimirAparte(String zip, String destino) =>
      Isolate.run(() => _descomprimir(zip, destino));

  static Future<String?> _problema(String ruta, InfoActualizacion info) {
    final sha = info.sha256, tam = info.tamano;
    final adentro = Platform.isAndroid
        ? 'AndroidManifest.xml'
        : Platform.resolvedExecutable.split(RegExp(r'[\\/]')).last;
    return Isolate.run(() => problemaDePaquete(ruta, sha, tam, adentro));
  }

  // ── Instalar ──────────────────────────────────────────────────────

  /// Instala la versión descargada ya. Windows: la app se cierra y vuelve
  /// a abrir. Android: se reemplaza (Android 12+ sin preguntar).
  Future<void> instalarAhora() async {
    if (_instalando || _info == null) return;
    final d = await _carpeta();
    final e = await _leerEstado(d);
    if (_intentosHoy(e) >= _maxIntentosPorDia && estado.value.fase == FaseActualizacion.error) {
      return;   // se espera a «Reintentar» o al día siguiente
    }
    _instalando = true;
    try {
      if (Platform.isWindows) {
        if (_instaladorTrabajando(e)) return;
        final carpeta = _carpetaNueva ?? '${e['carpeta'] ?? ''}';
        if (carpeta.isEmpty || !await Directory(carpeta).exists()) {
          throw Exception('Falta la versión descomprimida');
        }
        _fijar(FaseActualizacion.instalando, version: _info!.version);
        _enviar('instalando');
        await _lanzarWindows(d, e, _info!.version, carpeta, _versionLocal, reabrir: true);
        await Future.delayed(const Duration(milliseconds: 600));
        exit(0);
      }
      final apk = _paquete ?? File('${e['paquete'] ?? ''}');
      if (!await apk.exists()) throw Exception('Falta el APK descargado');
      if (!await _revisarPermisoAndroid()) return;
      e['intentos'] = _intentosHoy(e) + 1;
      e['ultimo_intento'] = DateTime.now().toIso8601String();
      e['objetivo'] = _info!.version;
      e['desde'] = _versionLocal;
      await _guardarEstado(d, e);
      _fijar(FaseActualizacion.instalando, version: _info!.version);
      _enviar('instalando');
      await _canal.invokeMethod('instalar', {'ruta': apk.path});
      // Si Android pide confirmar, la pantalla sale sola (Actualizador.kt).
      // Si termina, Android cierra la app: el resultado se lee al reabrir.
      unawaited(Future.delayed(const Duration(minutes: 2), _leerResultadoAndroid));
    } catch (err) {
      final detalle = '$err'.replaceFirst('Exception: ', '');
      _fijar(FaseActualizacion.error, version: _info?.version ?? '', detalle: detalle);
      _enviar('error', detalle: detalle);
    } finally {
      _instalando = false;
    }
  }

  Future<void> _leerResultadoAndroid() async {
    try {
      final r = await _canal.invokeMapMethod<String, dynamic>('resultado') ?? {};
      if (r['estado'] == 'error') {
        _fijar(FaseActualizacion.error, version: _info?.version ?? '', detalle: '${r['detalle']}');
        _enviar('error', detalle: '${r['detalle']}');
        await _canal.invokeMethod('limpiarResultado');
      } else if (r['estado'] == 'confirmar') {
        _enviar('confirmar', detalle: 'Android espera que se toque «Instalar»');
      } else if (r['estado'] == 'clasico') {
        // Android canceló la sesión (código 3, tablets Xiaomi con HyperOS) y
        // se abrió el instalador clásico con el mismo APK (Actualizador.kt).
        _enviar('confirmar',
            detalle: 'Sesión cancelada por Android: se abrió el instalador clásico, '
                'espera que se toque «Instalar»');
      }
    } catch (_) {}
  }

  /// Android 8+: Tecno Líder necesita «Permitir desde esta fuente» una vez.
  Future<bool> _revisarPermisoAndroid() async {
    if (!Platform.isAndroid) return true;
    bool puede = true;
    try {
      puede = await _canal.invokeMethod<bool>('puedeInstalar') ?? true;
    } catch (_) {}
    if (!puede && estado.value.fase != FaseActualizacion.sinPermiso) {
      _fijar(FaseActualizacion.sinPermiso, version: _info?.version ?? '');
      _enviar('sin_permiso', detalle: 'Falta «Permitir desde esta fuente» para Tecno Líder');
    } else if (puede && estado.value.fase == FaseActualizacion.sinPermiso) {
      _fijar(_paquete != null ? FaseActualizacion.lista : FaseActualizacion.alDia,
          version: _info?.version ?? '');
    }
    return puede;
  }

  /// Abre el ajuste de Android para permitir instalar (botón del aviso).
  Future<void> pedirPermisoAndroid() async {
    try { await _canal.invokeMethod('abrirPermiso'); } catch (_) {}
  }

  /// «Reintentar» del aviso de error.
  Future<void> reintentar() async {
    unawaited(anotar('reintentar (botón)'));
    final d = await _carpeta();
    final e = await _leerEstado(d);
    e['intentos'] = 0;
    await _guardarEstado(d, e);
    _fijar(FaseActualizacion.alDia);
    await revisar(manual: true);
    if (estado.value.fase == FaseActualizacion.lista) await instalarAhora();
  }

  // ── Estado y reporte ──────────────────────────────────────────────

  /// Registro en disco de cada paso (actualizaciones/motor.log, se recorta
  /// solo). En producción debugPrint está apagado: sin esto, un equipo que
  /// no se actualiza no deja rastro.
  static Future<void> anotar(String mensaje) async {
    try {
      final d = await _carpeta();
      final f = File(_en(d, 'motor.log'));
      if (await f.exists() && await f.length() > 200000) {
        final lineas = await f.readAsLines();
        await f.writeAsString('${lineas.skip(lineas.length ~/ 2).join('\n')}\n');
      }
      await f.writeAsString('${DateTime.now().toIso8601String()} [pid $pid] $mensaje\n',
          mode: FileMode.append, flush: true);
    } catch (_) {}
  }

  void _fijar(FaseActualizacion fase, {String? version, double progreso = 0, String detalle = ''}) {
    if (fase != estado.value.fase || detalle != estado.value.detalle) {
      unawaited(anotar('fase ${fase.name} ${version ?? estado.value.version} $detalle'.trim()));
    }
    estado.value = EstadoActualizacion(fase,
        version: version ?? estado.value.version, progreso: progreso, detalle: detalle);
  }

  DateTime _ultimoEnvio = DateTime.fromMillisecondsSinceEpoch(0);
  String _ultimoEnviado = '';

  void _enviar(String estadoTexto, {String detalle = ''}) {
    final reportar = _reportar;
    if (reportar == null) return;
    // El mismo estado no se repite más de una vez cada 25 minutos.
    final clave = '$estadoTexto|$detalle|${_info?.version}';
    final ahora = DateTime.now();
    if (clave == _ultimoEnviado && ahora.difference(_ultimoEnvio) < const Duration(minutes: 25)) {
      return;
    }
    _ultimoEnviado = clave;
    _ultimoEnvio = ahora;
    final datos = <String, dynamic>{
      'dispositivo_id': _equipoId,
      'plataforma': _plataforma,
      'version': _versionLocal,
      'version_disponible': _info?.version ?? '',
      'estado': estadoTexto,
      'detalle': detalle.length > 900 ? detalle.substring(0, 900) : detalle,
      ..._equipo,
      ...(_datos?.call() ?? const {}),
    };
    unawaited(reportar(datos).catchError((Object e) {
      debugPrint('[Actualizador] reporte: $e');
      _ultimoEnviado = '';   // se reintenta en la próxima vuelta
    }));
  }
}

/// ¿Este archivo de Documentos lo dejó el actualizador viejo de Tecno Líder
/// (1.0.17 y anteriores)? Ver main.dart de la 1.0.17: `tecnolider-<v>.apk`,
/// `tecnolider-update-<v>.zip`, `tecnolider_update_<v>` y
/// `aplicar_update_tecnolider.bat`. El .apk solo se borra en Android.
bool esRestoDelActualizadorViejo(String nombre, {required bool android}) =>
    nombre.startsWith('tecnolider-update-') ||
    nombre.startsWith('tecnolider_update_') ||
    nombre == 'aplicar_update_tecnolider.bat' ||
    (android && nombre.startsWith('tecnolider-') && nombre.endsWith('.apk'));

/// Comprueba un paquete descargado: tamaño, SHA-256 y que el zip esté
/// entero y traiga `adentro`. Devuelve el problema o null si está bien.
/// Corre en otro isolate (lee ~100 MB).
String? problemaDePaquete(String ruta, String sha, int tamano, String adentro) {
  final f = File(ruta);
  if (!f.existsSync()) return 'no existe';
  final largo = f.lengthSync();
  if (largo == 0) return 'vacío';
  if (tamano > 0 && largo != tamano) return 'mide $largo bytes y debía medir $tamano';
  if (sha.isNotEmpty) {
    final salida = _Captura();
    final conv = sha256.startChunkedConversion(salida);
    final raf = f.openSync();
    try {
      while (true) {
        final trozo = raf.readSync(1 << 20);
        if (trozo.isEmpty) break;
        conv.add(trozo);
      }
    } finally {
      raf.closeSync();
    }
    conv.close();
    if ('${salida.valor}' != sha) return 'la huella SHA-256 no coincide';
  }
  InputFileStream? entrada;
  try {
    entrada = InputFileStream(ruta);
    final zip = ZipDecoder().decodeBuffer(entrada);
    final nombre = adentro.toLowerCase();
    final ok = zip.files.any((a) {
      final n = a.name.replaceAll('\\', '/').toLowerCase();
      return n == nombre || n.endsWith('/$nombre');
    });
    if (!ok) return 'no trae $adentro';
  } catch (e) {
    return 'el archivo está cortado o dañado ($e)';
  } finally {
    entrada?.closeSync();
  }
  return null;
}

class _Captura implements Sink<Digest> {
  Digest? valor;
  @override
  void add(Digest data) => valor = data;
  @override
  void close() {}
}

/// Descomprime el zip de Windows en `destino` y devuelve la carpeta que
/// tiene el .exe (la raíz o una subcarpeta), o null si no lo trae.
String? _descomprimir(String zip, String destino) => descomprimirPaquete(
    zip, destino, Platform.resolvedExecutable.split(RegExp(r'[\\/]')).last);

/// [_descomprimir] con el nombre del .exe a buscar (para las pruebas).
String? descomprimirPaquete(String zip, String destino, String exe) {
  final dir = Directory(destino);
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  dir.createSync(recursive: true);
  final entrada = InputFileStream(zip);
  try {
    final archivo = ZipDecoder().decodeBuffer(entrada);
    // La versión síncrona: `extractArchiveToDisk` devuelve un Future y, sin
    // esperarlo, el isolate terminaba antes de escribir nada (carpeta vacía).
    extractArchiveToDiskSync(archivo, destino);
  } finally {
    entrada.closeSync();
  }
  bool tiene(Directory d) =>
      File('${d.path}${Platform.pathSeparator}$exe').existsSync() &&
      File('${d.path}${Platform.pathSeparator}data${Platform.pathSeparator}app.so').existsSync();
  if (tiene(dir)) return dir.path;
  for (final ent in dir.listSync()) {
    if (ent is Directory && tiene(ent)) return ent.path;
  }
  return null;
}
