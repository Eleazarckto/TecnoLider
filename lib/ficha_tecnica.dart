// ============================================================================
//  ficha_tecnica.dart — Ficha técnica de cada producto
//  (traída de Brizuela, 14/10/2026, SIN la IA)
//
//  Se abre desde el inventario. Muestra los datos agrupados (Pantalla,
//  Cámaras, Batería…) según lo que es el producto; qué datos lleva cada tipo
//  lo decide el servidor (backend/endpoints/ficha_tecnica.php).
//
//  · «Editar» deja llenar o corregir cualquier dato y agregar otros. Al
//    guardar queda «revisada» (origen «manual»).
//  · Las fichas cargadas con los scripts de backend/herramientas_fichas/
//    quedan «auto»: se ven en naranja hasta que alguien las revise.
//  · «Copiar» la deja en el portapapeles, para mandarla por WhatsApp.
//
//  No habla con el servidor por su cuenta: recibe las funciones de
//  `main.dart`, que agregan el correo del usuario (el servidor comprueba
//  con él quién puede guardar).
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

typedef LeerFicha = Future<dynamic> Function(String recurso, [Map<String, String>? params]);
typedef EnviarFicha = Future<dynamic> Function(String recurso, Map<String, dynamic> cuerpo);

/// Quién corrige y llena fichas. Igual que FICHA_ROLES en el servidor, que
/// es el que corta de verdad.
const List<String> kRolesFicha = [
  'Dueño', 'Dueno', 'Administrador', 'Gerente', 'Encargado', 'Activador', 'Maestro',
];

class CampoFicha {
  final String grupo, campo;
  String valor;
  CampoFicha(this.grupo, this.campo, this.valor);

  factory CampoFicha.desdeJson(Map m) => CampoFicha(
      (m['grupo'] ?? '').toString(), (m['campo'] ?? '').toString(), (m['valor'] ?? '').toString());

  Map<String, dynamic> aJson() => {'grupo': grupo, 'campo': campo, 'valor': valor};
}

class FichaTecnica {
  final String codigo, nombre, titulo, origen, por;
  final String? actualizado;
  final List<CampoFicha> campos;

  FichaTecnica({
    required this.codigo, required this.nombre, required this.titulo,
    required this.origen, required this.por, required this.actualizado,
    required this.campos,
  });

  factory FichaTecnica.desdeJson(Map m) => FichaTecnica(
        codigo: (m['codigo'] ?? '').toString(),
        nombre: (m['nombre'] ?? '').toString(),
        titulo: (m['titulo'] ?? 'Producto').toString(),
        origen: (m['origen'] ?? '').toString(),
        por: (m['por'] ?? '').toString(),
        actualizado: m['actualizado']?.toString(),
        campos: (m['campos'] is List ? m['campos'] as List : const [])
            .whereType<Map>()
            .map(CampoFicha.desdeJson)
            .toList(),
      );

  int get llenos => campos.where((c) => c.valor.trim().isNotEmpty).length;

  /// Grupos en el orden en que vienen, con sus campos.
  Map<String, List<CampoFicha>> get porGrupo {
    final m = <String, List<CampoFicha>>{};
    for (final c in campos) {
      m.putIfAbsent(c.grupo, () => []).add(c);
    }
    return m;
  }

  /// Texto para copiar (WhatsApp): solo los datos llenos.
  String comoTexto() {
    final b = StringBuffer('*$nombre*\nFicha técnica\n');
    porGrupo.forEach((grupo, campos) {
      final llenos = campos.where((c) => c.valor.trim().isNotEmpty).toList();
      if (llenos.isEmpty) return;
      b.write('\n*$grupo*\n');
      for (final c in llenos) {
        b.write('• ${c.campo}: ${c.valor.trim()}\n');
      }
    });
    return b.toString().trim();
  }
}

/// Etiqueta y color del estado de la ficha.
(String, Color) estadoFicha(String origen, int llenos) => switch (origen) {
      'manual' => ('Revisada', Colors.green),
      // «auto»: cargada con los scripts de herramientas_fichas/. «ia» no se
      // usa en Tecno Líder; se trata igual por si llega una de Brizuela.
      'auto' || 'ia' => ('Cargada automáticamente · revisar', Colors.orange),
      _ => (llenos > 0 ? 'Con datos' : 'Sin ficha', Colors.grey),
    };

class VentanaFichaTecnica extends StatefulWidget {
  final String codigo, nombre;
  final LeerFicha leer;
  /// Para guardar: el POST normal.
  final EnviarFicha enviar;
  final bool puedeEditar;

  const VentanaFichaTecnica({
    super.key,
    required this.codigo,
    required this.nombre,
    required this.leer,
    required this.enviar,
    required this.puedeEditar,
  });

  @override
  State<VentanaFichaTecnica> createState() => _VentanaFichaTecnicaState();
}

class _VentanaFichaTecnicaState extends State<VentanaFichaTecnica> {
  FichaTecnica? _ficha;
  String? _error;
  bool _cargando = true;
  bool _editando = false;
  bool _ocupado = false;
  String _ocupadoTexto = '';
  final Map<CampoFicha, TextEditingController> _ctrls = {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final r = await widget.leer('ficha_tecnica', {'codigo': widget.codigo});
      if (r is! Map) throw Exception('Respuesta inesperada del servidor.');
      if (mounted) setState(() => _ficha = FichaTecnica.desdeJson(r));
    } catch (e) {
      if (mounted) setState(() => _error = _limpio(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  String _limpio(Object e) => e.toString().replaceFirst('Exception: ', '');

  void _aviso(String texto, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(texto),
      backgroundColor: error ? Colors.red : Colors.green,
      duration: Duration(seconds: error ? 6 : 3),
    ));
  }

  void _empezarEdicion() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    _ctrls.clear();
    for (final c in _ficha!.campos) {
      _ctrls[c] = TextEditingController(text: c.valor);
    }
    setState(() => _editando = true);
  }

  Future<void> _guardar() async {
    final f = _ficha!;
    for (final e in _ctrls.entries) {
      e.key.valor = e.value.text.trim();
    }
    setState(() {
      _ocupado = true;
      _ocupadoTexto = 'Guardando…';
    });
    try {
      final r = await widget.enviar('ficha_tecnica_guardar', {
        'codigo': f.codigo,
        'campos': f.campos.map((c) => c.aJson()).toList(),
      });
      if (r is Map && mounted) {
        setState(() {
          _ficha = FichaTecnica.desdeJson(r);
          _editando = false;
        });
      }
      _aviso('Ficha técnica guardada.');
    } catch (e) {
      _aviso('No se pudo guardar: ${_limpio(e)}', error: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _agregarDato() async {
    final grupo = TextEditingController(text: 'Otros');
    final campo = TextEditingController();
    final valor = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Agregar dato'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: grupo, decoration: const InputDecoration(labelText: 'Grupo')),
          TextField(controller: campo, autofocus: true,
              decoration: const InputDecoration(labelText: 'Dato (ej: Radio FM)')),
          TextField(controller: valor, decoration: const InputDecoration(labelText: 'Valor')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(c, true), child: const Text('AGREGAR')),
        ],
      ),
    );
    if (ok == true && campo.text.trim().isNotEmpty) {
      final nuevo = CampoFicha(
          grupo.text.trim().isEmpty ? 'Otros' : grupo.text.trim(), campo.text.trim(), valor.text.trim());
      setState(() {
        _ficha!.campos.add(nuevo);
        _ctrls[nuevo] = TextEditingController(text: nuevo.valor);
      });
    }
    grupo.dispose();
    campo.dispose();
    valor.dispose();
  }

  void _copiar() {
    final f = _ficha;
    if (f == null || f.llenos == 0) return;
    Clipboard.setData(ClipboardData(text: f.comoTexto()));
    _aviso('Ficha copiada. Puede pegarla en WhatsApp.');
  }

  @override
  Widget build(BuildContext context) {
    final f = _ficha;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ficha técnica'),
        actions: [
          if (f != null && !_editando && f.llenos > 0)
            IconButton(tooltip: 'Copiar', icon: const Icon(Icons.copy_rounded), onPressed: _copiar),
          if (f != null && widget.puedeEditar && !_editando)
            IconButton(
                tooltip: 'Editar',
                icon: const Icon(Icons.edit_outlined),
                onPressed: _ocupado ? null : _empezarEdicion),
          if (_editando)
            IconButton(
                tooltip: 'Cancelar edición',
                icon: const Icon(Icons.close),
                onPressed: _ocupado ? null : () => setState(() => _editando = false)),
        ],
      ),
      body: _cuerpo(),
      floatingActionButton: f == null || !widget.puedeEditar || _ocupado
          ? null
          : _editando
              ? FloatingActionButton.extended(
                  onPressed: _guardar,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Guardar'))
              : FloatingActionButton.extended(
                  onPressed: _empezarEdicion,
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(f.llenos == 0 ? 'Llenar ficha' : 'Corregir ficha')),
    );
  }

  Widget _cuerpo() {
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
          child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('No se pudo cargar la ficha técnica:\n$_error', textAlign: TextAlign.center),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: _cargar, child: const Text('Reintentar')),
              ])));
    }
    final f = _ficha!;
    final (estado, color) = estadoFicha(f.origen, f.llenos);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      children: [
        Text(f.nombre, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('${f.codigo} · ${f.titulo}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
            child: Text(estado,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
          ),
        ]),
        if (f.origen == 'auto' || f.origen == 'ia')
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Se cargó automáticamente a partir del nombre del producto. Revise los '
              'datos y corrija lo que haga falta antes de dárselos a un cliente.',
              style: TextStyle(fontSize: 12, color: Colors.deepOrange)),
          ),
        if (_ocupado)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const LinearProgressIndicator(),
              const SizedBox(height: 4),
              Text(_ocupadoTexto, style: const TextStyle(fontSize: 12)),
            ]),
          ),
        const SizedBox(height: 8),
        for (final e in f.porGrupo.entries) _grupo(e.key, e.value),
        if (_editando)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton.icon(
                onPressed: _agregarDato,
                icon: const Icon(Icons.add),
                label: const Text('Agregar otro dato')),
          ),
        if (!_editando && f.llenos == 0 && !widget.puedeEditar)
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Text('Este producto todavía no tiene ficha técnica.',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
          ),
      ],
    );
  }

  Widget _grupo(String grupo, List<CampoFicha> campos) {
    final visibles = _editando ? campos : campos.where((c) => c.valor.trim().isNotEmpty).toList();
    if (visibles.isEmpty && !_editando) {
      // Sin datos en todo el grupo: se muestra el nombre del grupo con los
      // campos en gris, para que se vea qué falta.
      return _tarjeta(grupo, [
        for (final c in campos)
          _fila(c.campo, '—', gris: true),
      ]);
    }
    return _tarjeta(grupo, [
      for (final c in visibles)
        _editando
            ? Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  controller: _ctrls[c],
                  decoration: InputDecoration(labelText: c.campo, isDense: true),
                ),
              )
            : _fila(c.campo, c.valor),
      if (!_editando && visibles.length < campos.length)
        Text('${campos.length - visibles.length} dato(s) sin llenar',
            style: const TextStyle(fontSize: 11, color: Colors.grey)),
    ]);
  }

  Widget _tarjeta(String titulo, List<Widget> hijos) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            ...hijos,
          ]),
        ),
      );

  Widget _fila(String campo, String valor, {bool gris = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 150,
              child: Text(campo, style: const TextStyle(fontSize: 13, color: Colors.grey))),
          Expanded(
              child: Text(valor,
                  style: TextStyle(fontSize: 13, color: gris ? Colors.grey : null))),
        ]),
      );
}
