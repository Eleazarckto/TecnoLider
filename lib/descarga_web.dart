// descarga_web.dart — implementación para Flutter Web.
// Dispara una descarga real del navegador creando un blob y un
// enlace <a download> temporal. No usa el sistema de archivos
// (que no existe en web).
import 'dart:typed_data';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

/// Descarga un archivo de bytes en el navegador.
/// [nombre] debe incluir la extensión (ej. "reporte.xlsx").
/// [mimeType] el tipo MIME del archivo.
Future<void> descargarArchivo(
    Uint8List bytes, String nombre, String mimeType) async {
  // Crear un Blob con los bytes
  final jsBytes = bytes.toJS;
  final blob = web.Blob(
    [jsBytes].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  // Crear una URL temporal apuntando al blob
  final url = web.URL.createObjectURL(blob);
  // Crear un <a download> invisible y simular click
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = nombre
    ..style.display = 'none';
  web.document.body!.appendChild(anchor);
  anchor.click();
  anchor.remove();
  // Liberar la URL temporal
  web.URL.revokeObjectURL(url);
}
