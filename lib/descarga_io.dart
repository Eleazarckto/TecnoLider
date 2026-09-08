// descarga_io.dart — implementación para móvil y escritorio.
// Guarda los bytes en un archivo temporal y abre el sharesheet
// nativo para que el usuario decida qué hacer (guardar, enviar, etc.).
//
// Usa la API nueva de share_plus v12: SharePlus.instance.share(...)
// con ShareParams. La API vieja (Share.shareXFiles) quedó deprecada.
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Descarga / comparte un archivo de bytes.
/// [nombre] debe incluir la extensión (ej. "reporte.xlsx").
/// [mimeType] el tipo MIME del archivo.
Future<void> descargarArchivo(
    Uint8List bytes, String nombre, String mimeType) async {
  final dir = await getTemporaryDirectory();
  final path = '${dir.path}/$nombre';
  final file = File(path);
  await file.writeAsBytes(bytes, flush: true);
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(path, mimeType: mimeType, name: nombre)],
      subject: nombre,
    ),
  );
}