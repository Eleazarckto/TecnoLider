// descarga.dart — punto de entrada único para descargar archivos.
// Usa compilación condicional: en web carga descarga_web.dart,
// en móvil/escritorio carga descarga_io.dart. El resto del código
// solo importa este archivo y llama a `descargarArchivo(...)`.
export 'descarga_io.dart'
    if (dart.library.js_interop) 'descarga_web.dart';
