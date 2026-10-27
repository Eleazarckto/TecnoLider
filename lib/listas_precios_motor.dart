part of 'main.dart';

// ============================================================================
//  LISTAS DE PRECIOS — motor traído de Brizuela (hasta su 1.0.72)
//
//  16/10/2026. Lo que vive acá, fuera de main.dart para que los cambios
//  de las otras ramas no choquen:
//
//    · Permisos centralizados (quién gestiona listas y quién ve los %).
//    · Guardado sin pisar a los demás: InstantaneaLista + fusión a tres
//      bandas (leerListaDelServidor, modificarListaEnServidor,
//      guardarListaFusionando). Antes cada guardado mandaba la lista
//      ENTERA tal como la tenía ese equipo y gana el último que guarda.
//    · Sondeo barato (`solo_marcas`).
//    · Un solo repoblado: poblarListaDesdeCatalogo, con las reglas de
//      Tecno Líder (sin subproductos, nuevos solo con stock, stock de todas
//      las tiendas) y SIN el items.clear() que borraba lo agregado a mano.
//    · Marcas de celda manual (`es_manual`) y su migración.
//    · «Precios desde el costo»: diálogo de configuración, ensayo y
//      activación contra el servidor (backend/lib/precios_listas.php).
//      APAGADO: cada lista sigue a mano hasta que la administración la
//      pase a «desde el costo», y antes de activar se ve cuántos precios
//      cambiarían.
// ============================================================================

// ── Permisos ────────────────────────────────────────────────────────────────

/// ¿Puede crear, editar y borrar listas, columnas y precios?
/// Dueño, Administrador, Gerente y Maestro (el resto solo consulta).
bool puedeGestionarListasPrecios() =>
    puedeVerPorcentajesListas(usuarioSesion?.rol);

/// ¿Puede ver el % que una lista le suma al costo o a la venta, y los
/// botones de configuración? Los mismos roles: a un vendedor no se le
/// muestra cuánto se le suma al costo.
bool puedeVerPorcentajesDeListas() =>
    puedeVerPorcentajesListas(usuarioSesion?.rol);

// ── Estado del guardado (indicador de la barra) ─────────────────────────────

enum EstadoGuardado {
  /// No hay nada pendiente ni recién guardado.
  limpio,

  /// Hay cambios en memoria esperando a que venza el debounce.
  pendiente,

  /// Hay una escritura en vuelo.
  guardando,

  /// La última escritura terminó bien.
  guardado,

  /// La última escritura falló. Los cambios siguen en el equipo.
  error,
}

// ── Guardado sin pisar a los demás ──────────────────────────────────────────
//
//  El servidor guarda la lista ENTERA que le llega. Si cada equipo manda
//  su copia, gana el último con TODO su contenido aunque solo haya tocado
//  una cosa. El arreglo (Brizuela 1c84509): se recuerda la versión del
//  servidor sobre la que se trabajó (la «base»); al guardar se lee la
//  actual, se le aplica SOLO lo que este equipo cambió respecto de la base
//  y se escribe el resultado.

int? _aEntero(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('$v');
}

bool _igualJsonLista(Object? a, Object? b) {
  if (a is num && b is num) return a == b;
  return jsonEncode(a) == jsonEncode(b);
}

/// Foto comparable de una lista: cabecera, columnas y, por producto, sus
/// campos y sus celdas.
class InstantaneaLista {
  final int? id;
  final Map<String, dynamic> cabecera;
  final List<Map<String, dynamic>> columnas;

  /// código → ítem. Se conserva el orden.
  final Map<String, ItemInstantanea> items;

  InstantaneaLista._(this.id, this.cabecera, this.columnas, this.items);

  factory InstantaneaLista.de(ListaPrecio l) {
    final nombresCol = l.columnas.map((c) => c.nombre).toSet();
    return InstantaneaLista._(
      l.id,
      l.cabeceraMap(),
      [
        for (final c in l.columnas)
          {'nombre': c.nombre, 'formula': jsonEncode(c.formula.toJson())}
      ],
      {
        for (final it in l.items)
          it.producto.codigo: ItemInstantanea(
            producto: it.producto,
            fueraDeCatalogo: it.fueraDeCatalogo,
            campos: {
              'stock_disponible': it.stockDisponible,
              'inicial_manual': it.inicialManual,
              'cuota_manual': it.cuotaManual,
              'pct_inicial_override': it.pctInicialOverride,
              'cuotas_override': it.cuotasOverride,
            },
            celdas: {
              for (final e in it.preciosPorColumna.entries)
                // Una clave de una columna que ya no existe no es un
                // precio: `toMap` tampoco la manda.
                if (nombresCol.contains(e.key))
                  e.key: CeldaInstantanea(e.value, it.esManual(e.key)),
            },
          ),
      },
    );
  }

  /// Vuelve a armar una `ListaPrecio` con esta foto.
  ListaPrecio aLista() {
    final l = ListaPrecio.fromMap({
      'id': id,
      ...cabecera,
      'columnas': columnas,
      'items': const [],
    });
    for (final e in items.entries) {
      final it = e.value;
      l.items.add(ItemListaPrecio(
        producto: it.producto,
        preciosPorColumna: {
          for (final c in it.celdas.entries) c.key: c.value.precio,
        },
        stockDisponible: _aEntero(it.campos['stock_disponible']) ?? 0,
        inicialManual: (it.campos['inicial_manual'] as num?)?.toDouble(),
        cuotaManual: (it.campos['cuota_manual'] as num?)?.toDouble(),
        pctInicialOverride:
            (it.campos['pct_inicial_override'] as num?)?.toDouble(),
        cuotasOverride: _aEntero(it.campos['cuotas_override']),
        columnasManuales: {
          for (final c in it.celdas.entries)
            if (c.value.manual) c.key,
        },
        fueraDeCatalogo: it.fueraDeCatalogo,
      ));
    }
    return l;
  }

  /// ¿Esta foto y `otra` tienen exactamente el mismo contenido?
  bool mismoContenido(InstantaneaLista otra) =>
      _igualJsonLista(cabecera, otra.cabecera) &&
      _igualJsonLista(columnas, otra.columnas) &&
      items.length == otra.items.length &&
      items.entries.every((e) {
        final o = otra.items[e.key];
        return o != null && e.value.igualA(o);
      });

  /// Fusión a tres bandas: `remota` + lo que `local` cambió respecto de
  /// `base`. Lo que este equipo no tocó se toma del servidor; si los dos
  /// tocaron lo mismo, gana este equipo (es la edición más reciente).
  static InstantaneaLista fusionar({
    required InstantaneaLista local,
    required InstantaneaLista base,
    required InstantaneaLista remota,
  }) {
    // ── Cabecera, campo a campo ──
    final cabecera = Map<String, dynamic>.from(remota.cabecera);
    for (final k in local.cabecera.keys) {
      if (!_igualJsonLista(local.cabecera[k], base.cabecera[k])) {
        cabecera[k] = local.cabecera[k];
      }
    }

    // ── Columnas: si este equipo las cambió manda su estructura ──
    final cambioColumnas = !_igualJsonLista(local.columnas, base.columnas);
    final columnas = [
      for (final c in (cambioColumnas ? local.columnas : remota.columnas))
        Map<String, dynamic>.from(c),
    ];
    // Columnas renombradas acá: los precios del servidor bajo el nombre
    // viejo pasan al nuevo (solo si el nombre cambió en la misma
    // posición; un cambio de orden no renombra nada).
    final renombres = <String, String>{};
    if (cambioColumnas && local.columnas.length == base.columnas.length) {
      final nombresBase = base.columnas.map((c) => c['nombre']).toSet();
      final nombresLocal = local.columnas.map((c) => c['nombre']).toSet();
      for (int i = 0; i < base.columnas.length; i++) {
        final viejo = '${base.columnas[i]['nombre']}';
        final nuevo = '${local.columnas[i]['nombre']}';
        if (viejo != nuevo &&
            !nombresLocal.contains(viejo) &&
            !nombresBase.contains(nuevo)) {
          renombres[viejo] = nuevo;
        }
      }
    }
    ItemInstantanea renombrar(ItemInstantanea it) => renombres.isEmpty
        ? it
        : ItemInstantanea(
            producto: it.producto,
            fueraDeCatalogo: it.fueraDeCatalogo,
            campos: it.campos,
            celdas: {
              for (final c in it.celdas.entries)
                (renombres[c.key] ?? c.key): c.value,
            });

    // ── Ítems ──
    final items = <String, ItemInstantanea>{};
    for (final e in remota.items.entries) {
      final codigo = e.key;
      final r = renombrar(e.value);
      final l = local.items[codigo];
      final bOrig = base.items[codigo];
      final b = bOrig == null ? null : renombrar(bOrig);
      if (l == null) {
        if (b != null) continue; // estaba y acá se quitó: se quita
        items[codigo] = r; // lo agregó otro equipo: se queda
        continue;
      }
      items[codigo] = ItemInstantanea.fusionar(l: l, b: b, r: r);
    }
    for (final e in local.items.entries) {
      if (items.containsKey(e.key)) continue;
      final b = base.items[e.key];
      if (b == null) {
        items[e.key] = e.value; // agregado en este equipo
      } else if (!e.value.igualA(renombrar(b))) {
        // Otro equipo lo quitó pero acá se editó después: se conserva.
        items[e.key] = e.value;
      }
    }
    return InstantaneaLista._(local.id ?? remota.id, cabecera, columnas, items);
  }
}

class CeldaInstantanea {
  final double precio;
  final bool manual;
  const CeldaInstantanea(this.precio, this.manual);
  bool igualA(CeldaInstantanea? o) =>
      o != null && o.precio == precio && o.manual == manual;
}

class ItemInstantanea {
  final Producto producto;
  final bool fueraDeCatalogo;
  final Map<String, dynamic> campos;
  final Map<String, CeldaInstantanea> celdas;
  ItemInstantanea({
    required this.producto,
    required this.campos,
    required this.celdas,
    this.fueraDeCatalogo = false,
  });

  bool igualA(ItemInstantanea o) =>
      _igualJsonLista(campos, o.campos) &&
      celdas.length == o.celdas.length &&
      celdas.entries.every((e) => e.value.igualA(o.celdas[e.key]));

  /// Cada campo y cada celda sale de este equipo si lo cambió, y del
  /// servidor si no. Sin base (los dos lo agregaron a la vez) manda este.
  static ItemInstantanea fusionar({
    required ItemInstantanea l,
    required ItemInstantanea? b,
    required ItemInstantanea r,
  }) {
    final campos = Map<String, dynamic>.from(r.campos);
    for (final k in l.campos.keys) {
      if (b == null || !_igualJsonLista(l.campos[k], b.campos[k])) {
        campos[k] = l.campos[k];
      }
    }
    final celdas = Map<String, CeldaInstantanea>.from(r.celdas);
    for (final e in l.celdas.entries) {
      if (b == null || !e.value.igualA(b.celdas[e.key])) {
        celdas[e.key] = e.value;
      }
    }
    // El producto real gana sobre el mínimo (fuera de catálogo).
    final usarRemoto = l.fueraDeCatalogo && !r.fueraDeCatalogo;
    return ItemInstantanea(
        producto: usarRemoto ? r.producto : l.producto,
        fueraDeCatalogo: usarRemoto ? false : l.fueraDeCatalogo,
        campos: campos,
        celdas: celdas);
  }
}

/// Lee del servidor la versión actual de una lista. Lanza si no llega una
/// lista usable, o si llega VACÍA cuando la conocida tenía productos (una
/// respuesta incompleta: escribir encima borraría todo del servidor).
Future<ListaPrecio> leerListaDelServidor(int id,
    {bool conocidaTeniaProductos = false}) async {
  final raw = await _Api.get('listas_precios', {'id': id.toString()});
  Map<String, dynamic>? data;
  if (raw is Map) {
    data = Map<String, dynamic>.from(raw);
  } else if (raw is List && raw.isNotEmpty && raw.first is Map) {
    data = Map<String, dynamic>.from(raw.first as Map);
  }
  if (data == null || data['id'] == null) {
    throw Exception('El servidor no devolvió la lista $id');
  }
  final lista = ListaPrecio.fromMap(data);
  if (lista.items.isEmpty && conocidaTeniaProductos) {
    throw Exception('El servidor devolvió la lista sin productos. '
        'No se guardó nada para no borrar los que tiene.');
  }
  return lista;
}

/// Aplica `cambio` sobre la versión RECIÉN LEÍDA del servidor y la guarda.
/// Devuelve la lista tal como quedó guardada.
Future<ListaPrecio> modificarListaEnServidor(
    ListaPrecio conocida, void Function(ListaPrecio fresca) cambio) async {
  final id = conocida.id;
  if (id == null) {
    throw Exception(
        'La lista "${conocida.nombre}" todavía no está en el servidor');
  }
  final fresca = await leerListaDelServidor(id,
      conocidaTeniaProductos: conocida.items.isNotEmpty);
  cambio(fresca);
  await _Api.put('listas_precios', id.toString(), fresca.toMap());
  return fresca;
}

/// Guarda lo que `local` cambió respecto de `base` sin pisar lo que otros
/// equipos guardaron mientras tanto. Devuelve la foto de lo que quedó en
/// el servidor, que pasa a ser la nueva base.
Future<InstantaneaLista> guardarListaFusionando({
  required int id,
  required InstantaneaLista local,
  required InstantaneaLista base,
}) async {
  final remota = InstantaneaLista.de(await leerListaDelServidor(id,
      conocidaTeniaProductos: base.items.isNotEmpty));
  final fusion =
      InstantaneaLista.fusionar(local: local, base: base, remota: remota);
  await _Api.put('listas_precios', id.toString(), fusion.aLista().toMap());
  return fusion;
}

/// Guarda los cambios hechos a `lista` desde `base` (la foto tomada antes
/// de tocarla). Si la lista todavía no existe en el servidor, la crea. Al
/// terminar `lista` queda con lo guardado (incluye lo de otros equipos).
Future<void> guardarCambiosDeLista(
    ListaPrecio lista, InstantaneaLista base) async {
  if (lista.id == null) {
    final resp = await _Api.post('listas_precios', lista.toMap());
    if (resp is Map && resp['id'] != null) lista.id = _aEntero(resp['id']);
    return;
  }
  final r = await guardarListaFusionando(
      id: lista.id!, local: InstantaneaLista.de(lista), base: base);
  lista.adoptar(r.aLista());
}

/// Sondeo barato: id → `actualizado_en` de las listas (o de una). Una marca
/// vacía significa que el servidor todavía no tiene la columna.
Future<Map<int, String>> leerMarcasListas({int? id}) async {
  final raw = await _Api.get('listas_precios',
      {'solo_marcas': '1', if (id != null) 'id': id.toString()});
  final out = <int, String>{};
  if (raw is List) {
    for (final m in raw) {
      if (m is! Map) continue;
      final i = _aEntero(m['id']);
      if (i != null) out[i] = '${m['actualizado_en'] ?? ''}';
    }
  }
  return out;
}

// ── Repoblado desde el catálogo ─────────────────────────────────────────────

class ResultadoPoblado {
  final int preservados, agregados, eliminados, recalculados, sinStock;

  /// El catálogo estaba vacío y no se tocó nada.
  final bool sinCatalogo;

  const ResultadoPoblado(this.preservados, this.agregados, this.eliminados,
      this.recalculados,
      {this.sinStock = 0, this.sinCatalogo = false});

  @override
  String toString() => '$preservados preservados, $agregados nuevos, '
      '$eliminados eliminados, $recalculados recalculados, '
      '$sinStock sin stock omitidos'
      '${sinCatalogo ? ' (SIN CATÁLOGO: no se tocó nada)' : ''}';
}

/// ¿El producto entra en el filtro de la lista? (categoría y marca).
/// La categoría admite varias separadas por coma; «Todos» = todas.
bool listaLeCorrespondeA(ListaPrecio lista, String categoria, String marca) {
  final cats = lista.categoria
      .split(',')
      .map((c) => c.trim())
      .where((c) => c.isNotEmpty)
      .toList();
  final okCategoria = lista.categoria == 'Todos' ||
      lista.categoria == categoria ||
      cats.isEmpty ||
      cats.contains('Todos') ||
      cats.contains(categoria);
  final okMarca = lista.marcaFiltro == 'Todas' ||
      marca.toLowerCase() == lista.marcaFiltro.toLowerCase();
  return okCategoria && okMarca;
}

/// Repuebla los ítems de una lista desde `catalogoGlobal`. Es la ÚNICA
/// implementación (antes eran tres: `_poblarLista`, `_autoPoblar` y el
/// cálculo suelto de `precioPorDefectoEnLista`).
///
/// Reglas (las de Tecno Líder):
///   1. Filtra por categoría y marca; nunca toma subproductos (variantes).
///   2. Ordena por marca y nombre; el código entra una sola vez aunque el
///      catálogo tenga una fila por tienda.
///   3. Producto que YA estaba → conserva precios, marcas de celda manual
///      y condiciones; solo se le actualiza el stock (todas las tiendas +
///      variantes) y se le rellenan las columnas nuevas.
///   4. Producto nuevo → entra con el precio por defecto SOLO si tiene
///      stock (las listas solo ofrecen lo que hay).
///   5. Producto agregado a mano fuera del filtro → se conserva mientras
///      siga en el catálogo. Ya NO se vacía la lista: el `items.clear()`
///      del viejo `_autoPoblar` borraba lo agregado a mano y los precios.
///   6. Producto que ya no está en el catálogo → sale.
///   7. Recalcula las columnas con fórmula automática (sin tocar celdas
///      fijadas a mano).
ResultadoPoblado poblarListaDesdeCatalogo(ListaPrecio lista) {
  if (catalogoGlobal.isEmpty) {
    debugPrint('[poblarListaDesdeCatalogo] catálogo vacío: no se toca '
        '"${lista.nombre}"');
    return ResultadoPoblado(lista.items.length, 0, 0, 0, sinCatalogo: true);
  }
  final filtrados = catalogoGlobal
      .where((p) =>
          !p.esSubproducto &&
          listaLeCorrespondeA(lista, p.categoria, p.marca))
      .toList()
    ..sort((a, b) {
      final m = a.marca.toLowerCase().compareTo(b.marca.toLowerCase());
      return m != 0
          ? m
          : a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
    });

  if (lista.columnas.isEmpty) {
    lista.columnas.add(ColumnaPrecio(
        nombre: lista.esEnBolivares ? "Precio (Bs)" : "Precio (\$)"));
  }

  final existentes = <String, ItemListaPrecio>{
    for (final it in lista.items) it.producto.codigo: it,
  };
  final nuevos = <ItemListaPrecio>[];
  final vistos = <String>{};
  var preservados = 0, agregados = 0, sinStock = 0;

  for (final p in filtrados) {
    if (!vistos.add(p.codigo)) continue;
    final stock = stockGlobalDeProducto(p);
    final previo = existentes[p.codigo];
    if (previo == null && stock <= 0) {
      sinStock++;
      continue;
    }
    final porDefecto = lista.precioPorDefecto(p);
    if (previo != null) {
      previo.stockDisponible = stock;
      for (final col in lista.columnas) {
        previo.preciosPorColumna.putIfAbsent(col.nombre, () => porDefecto);
      }
      nuevos.add(previo);
      preservados++;
    } else {
      nuevos.add(ItemListaPrecio(
        producto: p,
        stockDisponible: stock,
        preciosPorColumna: {for (final c in lista.columnas) c.nombre: porDefecto},
      ));
      agregados++;
    }
  }

  // Agregados a mano fuera del filtro: se quedan mientras sigan en el
  // catálogo (regla 5).
  final enCatalogo = {for (final p in catalogoGlobal) p.codigo};
  for (final it in lista.items) {
    final c = it.producto.codigo;
    if (vistos.contains(c) || !enCatalogo.contains(c)) continue;
    vistos.add(c);
    it.stockDisponible = stockGlobalDeProducto(it.producto);
    nuevos.add(it);
    preservados++;
  }

  final eliminados = lista.items.length - preservados;
  lista.items
    ..clear()
    ..addAll(nuevos);
  final recalculados = lista.aplicarFormulas();
  final r = ResultadoPoblado(preservados, agregados, eliminados, recalculados,
      sinStock: sinStock);
  debugPrint('[poblarListaDesdeCatalogo] ${lista.nombre}: $r');
  return r;
}

/// Las listas guardadas antes de `es_manual` llegan sin marcas. La primera
/// vez que se abren, las celdas de columnas SIN fórmula cuyo precio no es
/// el por defecto (con la tasa guardada de la lista y la misma tolerancia
/// de siempre: 1 Bs o $0,01) se marcan como manuales. Solo pone marcas:
/// NO cambia ningún precio. Si la lista ya tiene alguna marca, o está en
/// modo costo, no hace nada. Devuelve cuántas celdas marcó.
///
/// Una lista en Bs con lista base tampoco: su precio por defecto ya no es
/// el de la venta y marcaría como manual lo que sigue a la base.
int migrarMarcasManuales(ListaPrecio lista) {
  if (lista.esModoCosto || lista.listaBaseId != null) return 0;
  if (lista.items.any((it) => it.columnasManuales.isNotEmpty)) return 0;
  final tasa = lista.esEnBolivares && lista.tasaDelDia > 0
      ? lista.tasaDelDia
      : null;
  final tolerancia = lista.esEnBolivares ? 1.0 : 0.01;
  var n = 0;
  for (final it in lista.items) {
    if (it.fueraDeCatalogo) continue;
    final def =
        precioPorDefectoEnLista(lista, it.producto.precioVenta, tasa: tasa);
    for (final col in lista.columnas) {
      if (!col.formula.esManual) continue;
      final v = it.preciosPorColumna[col.nombre];
      if (v == null) continue;
      if ((v - def).abs() > tolerancia) {
        it.marcarManual(col.nombre);
        n++;
      }
    }
  }
  return n;
}

/// Borra una columna dejando la lista coherente: sus precios, sus marcas
/// de manual, y las fórmulas de otras columnas que la usaban pasan a
/// manual (conservan sus precios; antes calculaban desde 0).
/// Devuelve los nombres de las columnas que perdieron su fórmula.
List<String> eliminarColumnaDeLista(ListaPrecio lista, String nombre) {
  final n = nombre.toLowerCase();
  final afectadas = <String>[];
  lista.columnas.removeWhere((c) => c.nombre == nombre);
  for (final c in lista.columnas) {
    final f = c.formula;
    final usa = (f.origen == 'columna' && f.columnaOrigen.toLowerCase() == n) ||
        f.expresion.toLowerCase().contains('[$n]');
    if (!f.esManual && usa) {
      c.formula = FormulaColumna();
      afectadas.add(c.nombre);
    }
  }
  for (final it in lista.items) {
    it.preciosPorColumna.remove(nombre);
    it.marcarManual(nombre, manual: false);
  }
  return afectadas;
}

// ── Precios desde el costo: ensayo y activación ─────────────────────────────

/// Lo que el servidor dice que cambiaría (o cambió) en una lista.
class InformePreciosLista {
  final int listaId;
  final String nombre;
  final int precios, items, agregados, montosFijos;
  final List<({String codigo, String nombre, double? antes, double? despues})>
      ejemplos;
  InformePreciosLista(this.listaId, this.nombre, this.precios, this.items,
      this.agregados, this.montosFijos, this.ejemplos);

  factory InformePreciosLista.fromMap(Map m) {
    double? d(dynamic v) => v == null ? null : double.tryParse('$v');
    return InformePreciosLista(
      _aEntero(m['lista_id']) ?? 0,
      '${m['nombre'] ?? ''}',
      _aEntero(m['precios']) ?? 0,
      _aEntero(m['items']) ?? 0,
      _aEntero(m['agregados']) ?? 0,
      _aEntero(m['montos_fijos']) ?? 0,
      [
        for (final e in (m['ejemplos'] as List? ?? const []))
          if (e is Map)
            (
              codigo: '${e['codigo'] ?? ''}',
              nombre: '${e['nombre'] ?? ''}',
              antes: d(e['antes']),
              despues: d(e['despues'])
            )
      ],
    );
  }
}

/// Configuración del cálculo desde el costo que se manda al servidor.
Map<String, dynamic> configPreciosCosto(ListaPrecio l) => {
      'pct_sobre_costo': l.pctSobreCosto,
      'monto_adicional_dolares': l.montoAdicionalDolares,
      'tasa_fija': l.tasaFija ? 1 : 0,
      if (l.tasaFija) 'tasa_del_dia': l.tasaDelDia,
      'tasa_bs': l.tasaBs,
      'redondear_arriba': l.redondearArriba ? 1 : 0,
      'reglas_pct': reglasAJson(l.reglasPct),
    };

/// `operacion`: 'ensayo' (no guarda nada), 'activar' o 'desactivar'.
/// El servidor exige que el correo sea de un Dueño, Administrador o
/// Gerente activo.
Future<List<InformePreciosLista>> operarPreciosCosto(
    int listaId, String operacion,
    {Map<String, dynamic>? config}) async {
  final resp = await _Api.post('listas_precios&accion=precios_costo', {
    'id': listaId,
    'operacion': operacion,
    'usuario_correo': usuarioSesion?.correo ?? '',
    if (config != null) 'config': config,
  });
  if (resp is Map && resp['ok'] == false) {
    throw Exception('${resp['error'] ?? 'No se pudo completar'}');
  }
  final listas = resp is Map ? resp['listas'] : null;
  return [
    for (final m in (listas is List ? listas : const []))
      if (m is Map) InformePreciosLista.fromMap(m)
  ];
}

/// Grupos que se suelen separar del % general, para crearlos con un toque.
const _kReglasSugeridas = <(String, List<String>, String)>[
  ('Forros', ['forro', 'funda'], ''),
  ('Cargadores', ['cargador', 'cable', 'adaptador'], ''),
  ('iPhone', ['iphone'], 'Apple'),
  ('Cornetas', ['corneta', 'parlante'], ''),
  ('Vidrios', ['vidrio', 'templado', 'mica'], ''),
];

/// Editor de los % especiales por tipo de producto (Brizuela 1.0.70).
/// Edita `reglas` en el sitio; el diálogo que lo contiene las guarda.
class _EditorReglasPct extends StatelessWidget {
  final List<ReglaPorcentaje> reglas;
  final double pctLista;
  final List<String> marcas;

  /// Productos de la lista, para decir cuántos caen en cada regla.
  final List<Producto> productos;
  final VoidCallback onCambio;

  /// En una lista de financiamiento el % va sobre el precio de venta.
  final bool sobreVenta;

  const _EditorReglasPct({
    required this.reglas,
    required this.pctLista,
    this.sobreVenta = false,
    required this.marcas,
    required this.productos,
    required this.onCambio,
  });

  String _n(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  List<Producto> _de(int i) => productos
      .where((p) => identical(reglaPara(reglas, p.nombre, p.marca), reglas[i]))
      .toList();

  Future<void> _editar(BuildContext context,
      {int? indice, ReglaPorcentaje? base}) async {
    final r = indice != null ? reglas[indice] : (base ?? ReglaPorcentaje());
    final nombreCtrl = TextEditingController(text: r.nombre);
    final palabrasCtrl = TextEditingController(text: r.palabras.join(', '));
    final pctCtrl = TextEditingController(
        text: indice != null || base != null ? _n(r.pct) : '');
    String marca = r.marca;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        final prueba = ReglaPorcentaje(
            palabras: palabrasCtrl.text.split(','), marca: marca);
        final calzan = productos
            .where((p) => prueba.esValida && prueba.calzaCon(p.nombre, p.marca))
            .toList();
        return AlertDialog(
          title: Text(indice == null ? 'Nuevo % especial' : 'Editar % especial'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: nombreCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Nombre del grupo',
                        hintText: 'Forros, Cargadores, iPhone…',
                        border: OutlineInputBorder(),
                        isDense: true)),
                const SizedBox(height: 10),
                TextField(
                    controller: palabrasCtrl,
                    onChanged: (_) => setD(() {}),
                    decoration: const InputDecoration(
                        labelText: 'Palabras del nombre (separadas por coma)',
                        hintText: 'forro, funda',
                        helperText: 'Si el nombre del producto tiene alguna, '
                            'se le aplica este %.',
                        border: OutlineInputBorder(),
                        isDense: true)),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                    initialValue: marca,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: 'O por marca (opcional)',
                        border: OutlineInputBorder(),
                        isDense: true),
                    items: [
                      const DropdownMenuItem(
                          value: '', child: Text('— cualquier marca —')),
                      for (final m in {...marcas, if (marca.isNotEmpty) marca})
                        DropdownMenuItem(value: m, child: Text(m)),
                    ],
                    onChanged: (v) => setD(() => marca = v ?? '')),
                const SizedBox(height: 10),
                TextField(
                    controller: pctCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                        labelText: sobreVenta
                            ? '% sobre el precio de venta'
                            : '% sobre el costo',
                        hintText: '100',
                        helperText: 'En lugar del ${_n(pctLista)} % de la lista.',
                        border: const OutlineInputBorder(),
                        isDense: true)),
                const SizedBox(height: 12),
                // Vista previa: qué productos de esta lista calzan.
                Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: AppColors.primaryBlue.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(10)),
                    child: Text(
                        !prueba.esValida
                            ? 'Escribe al menos una palabra o elige una marca.'
                            : calzan.isEmpty
                                ? 'Ningún producto de esta lista calza todavía.'
                                : '${calzan.length} productos calzan: '
                                    '${calzan.take(4).map((p) => p.nombre).join(' · ')}'
                                    '${calzan.length > 4 ? '…' : ''}',
                        style: const TextStyle(fontSize: 12))),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('CANCELAR')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('LISTO')),
          ],
        );
      }),
    );
    if (ok != true) return;
    final pct = double.tryParse(pctCtrl.text.trim().replaceAll(',', '.'));
    final nueva = ReglaPorcentaje(
      nombre: nombreCtrl.text.trim(),
      palabras: palabrasCtrl.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(),
      marca: marca,
      pct: pct ?? 0,
    );
    if (pct == null || !nueva.esValida) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Falta el % o las palabras / la marca: no se agregó.'),
            backgroundColor: AppColors.statusRed));
      }
      return;
    }
    if (nueva.nombre.isEmpty) {
      nueva.nombre = nueva.marca.isNotEmpty ? nueva.marca : nueva.palabras.first;
    }
    if (indice != null) {
      reglas[indice] = nueva;
    } else {
      reglas.add(nueva);
    }
    onCambio();
  }

  @override
  Widget build(BuildContext context) {
    final yaHay = {for (final r in reglas) r.nombre.toLowerCase()};
    final sugeridas = _kReglasSugeridas
        .where((s) => !yaHay.contains(s.$1.toLowerCase()))
        .toList();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: AppColors.surfaceGrey, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('% especial por tipo de producto',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(
            'Los que calcen con una regla llevan su % en lugar del '
            '${_n(pctLista)} % de la lista. Vale la primera que calce.',
            style: const TextStyle(fontSize: 11, color: Colors.black54)),
        const SizedBox(height: 8),
        for (int i = 0; i < reglas.length; i++)
          Builder(builder: (_) {
            final r = reglas[i];
            final n = _de(i).length;
            final criterio = [
              if (r.palabras.isNotEmpty) 'nombre con: ${r.palabras.join(', ')}',
              if (r.marca.isNotEmpty) 'marca ${r.marca}',
            ].join(' · o ');
            return Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                dense: true,
                title: Text('${r.nombre}  ·  ${_n(r.pct)} %',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('$criterio\n$n productos de esta lista',
                    style: const TextStyle(fontSize: 11)),
                isThreeLine: true,
                onTap: () => _editar(context, indice: i),
                trailing: IconButton(
                    icon: const Icon(Icons.delete_outline,
                        color: AppColors.statusRed),
                    tooltip: 'Quitar',
                    onPressed: () {
                      reglas.removeAt(i);
                      onCambio();
                    }),
              ),
            );
          }),
        Wrap(spacing: 6, runSpacing: 6, children: [
          ActionChip(
              avatar: const Icon(Icons.add, size: 16),
              label: const Text('Agregar'),
              onPressed: () => _editar(context)),
          for (final s in sugeridas)
            ActionChip(
                label: Text(s.$1),
                onPressed: () => _editar(context,
                    base: ReglaPorcentaje(
                        nombre: s.$1,
                        palabras: [...s.$2],
                        marca: marcas.contains(s.$3) ? s.$3 : '',
                        pct: pctLista))),
        ]),
      ]),
    );
  }
}

/// Diálogo «Cómo se calculan los precios» de una lista (solo para quien
/// gestiona listas). Modo a mano (como hoy) o desde el costo; % sobre el
/// costo, tasa, monto fijo, redondeo hacia arriba y % especial por tipo
/// de producto. Para pasar a «desde el costo» (o cambiar su cuenta)
/// primero se ENSAYA en el servidor y se muestra cuántos precios
/// cambiarían; solo con la confirmación se activa. Devuelve true si algo
/// cambió (la lista ya queda con lo del servidor).
Future<bool> mostrarPreciosDeLista(
    BuildContext context, ListaPrecio lista) async {
  if (!puedeGestionarListasPrecios()) return false;
  if (lista.id == null) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Guarda la lista primero.')));
    return false;
  }
  String n(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
  double? leer(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.'));

  var costo = lista.esModoCosto;
  final pctCtrl = TextEditingController(text: n(lista.pctSobreCosto));
  final montoCtrl = TextEditingController(text: n(lista.montoAdicionalDolares));
  final tasaCtrl = TextEditingController(text: lista.tasaDelDia.toStringAsFixed(2));
  final tasaBsCtrl = TextEditingController(
      text: lista.tasaBs > 0 ? lista.tasaBs.toStringAsFixed(2) : '');
  var tasaFija = lista.tasaFija;
  var redondear = lista.redondearArriba;
  final reglas = [for (final r in lista.reglasPct) r.copia()];
  final esBs = lista.esEnBolivares, esFin = lista.esFinanciamiento;
  final marcas = {
    for (final p in catalogoGlobal)
      if (p.marca.trim().isNotEmpty) p.marca.trim()
  }.toList()
    ..sort();
  final productos = [
    for (final it in lista.items)
      if (!it.fueraDeCatalogo) it.producto
  ];

  Widget campo(String titulo, Widget w) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(titulo, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        w,
      ]));
  Widget numero(TextEditingController c, String pista) => TextField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
          hintText: pista, isDense: true, border: const OutlineInputBorder()));

  final accion = await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
      return AlertDialog(
        title: Text('Precios de «${lista.nombre}»'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(costo == false
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                        color: AppColors.primaryBlue),
                    title: const Text('A mano (como hasta hoy)'),
                    subtitle: const Text(
                        'Los precios se escriben en la lista. Al agregar un '
                        'producto entra con su precio de venta + el % adicional.',
                        style: TextStyle(fontSize: 11)),
                    onTap: () => setD(() => costo = false),
                  ),
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(costo == true
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                        color: AppColors.primaryBlue),
                    title: const Text('Desde el costo (automático)'),
                    subtitle: const Text(
                        'El servidor calcula cada precio desde el costo del '
                        'producto. Las celdas quedan bloqueadas. Antes de '
                        'activarlo se ve cuántos precios cambiarían.',
                        style: TextStyle(fontSize: 11)),
                    onTap: () => setD(() => costo = true),
                  ),
                  const Divider(height: 18),
                  if (costo) ...[
                    if (!esBs || esFin)
                      campo(
                          esFin
                              ? '% sobre el precio de venta (base del equipo)'
                              : '% sobre el costo',
                          numero(pctCtrl, esFin ? '40' : '25')),
                    if (esBs && !esFin)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 10),
                        child: Text(
                            'Una lista en Bs toma el precio de su lista Divisas '
                            '(en modo costo, misma marca y categorías) y lo '
                            'lleva a bolívares. Sin lista Divisas usa su propio %.',
                            style: TextStyle(fontSize: 11, color: Colors.black54)),
                      ),
                    if (esBs && !esFin)
                      campo('% sobre el costo (solo si no tiene lista Divisas)',
                          numero(pctCtrl, '25')),
                  ],
                  campo('Monto fijo adicional en USD', numero(montoCtrl, '0')),
                  if (costo && esBs) ...[
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(tasaFija
                          ? 'Tasa fija de esta lista'
                          : 'Tasa BCV del día',
                          style: const TextStyle(fontSize: 13)),
                      subtitle: const Text(
                          'Con tasa fija la lista no cambia cuando se carga '
                          'una tasa BCV nueva.',
                          style: TextStyle(fontSize: 11)),
                      value: tasaFija,
                      onChanged: (v) => setD(() => tasaFija = v),
                    ),
                    if (tasaFija) campo('Tasa fija (Bs por USD)', numero(tasaCtrl, '36.50')),
                  ],
                  if (costo && !esBs && !esFin)
                    campo('Tasa manual para llevar a Bs (sus listas en Bs). '
                        'Vacío = la BCV del día',
                        numero(tasaBsCtrl, '950.00')),
                  if (costo && (!esBs || esFin))
                    _EditorReglasPct(
                      reglas: reglas,
                      pctLista: leer(pctCtrl) ?? lista.pctSobreCosto,
                      sobreVenta: esFin,
                      marcas: marcas,
                      productos: productos,
                      onCambio: () => setD(() {}),
                    ),
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Redondear precios hacia arriba (sin decimales)',
                        style: TextStyle(fontSize: 13)),
                    subtitle: Text(
                        esBs
                            ? 'Cada precio queda en bolívares enteros: 25.686,99 → 25.687.'
                            : 'Cada precio queda en dólares enteros: 22,30 → 23. '
                                'Así la factura no da vueltos con céntimos.',
                        style: const TextStyle(fontSize: 11)),
                    value: redondear,
                    onChanged: (v) => setD(() => redondear = v),
                  ),
                ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('CANCELAR')),
          ElevatedButton.icon(
            icon: Icon(costo ? Icons.science_outlined : Icons.save, size: 18),
            label: Text(costo ? 'ENSAYAR' : 'GUARDAR'),
            onPressed: () => Navigator.pop(ctx, costo ? 'ensayar' : 'guardar'),
          ),
        ],
      );
    }),
  );
  if (accion == null || !context.mounted) return false;

  // La configuración propuesta, sobre una copia (la lista no cambia hasta
  // que el servidor confirme).
  final propuesta = ListaPrecio.fromMap(lista.toMap())..adoptar(lista);
  propuesta.montoAdicionalDolares = leer(montoCtrl) ?? 0;
  propuesta.redondearArriba = redondear;
  if (accion == 'ensayar') {
    propuesta.pctSobreCosto = leer(pctCtrl) ?? 0;
    propuesta.tasaFija = esBs && tasaFija;
    if (propuesta.tasaFija) propuesta.tasaDelDia = leer(tasaCtrl) ?? lista.tasaDelDia;
    propuesta.tasaBs = (!esBs && !esFin) ? (leer(tasaBsCtrl) ?? 0) : lista.tasaBs;
    propuesta.reglasPct = reglas;
  }

  try {
    if (accion == 'guardar') {
      // Modo manual: si estaba en costo se desactiva (sus precios quedan
      // como están) y el resto se guarda con la fusión de siempre.
      final base = InstantaneaLista.de(lista);
      if (lista.esModoCosto) await operarPreciosCosto(lista.id!, 'desactivar');
      lista.montoAdicionalDolares = propuesta.montoAdicionalDolares;
      lista.redondearArriba = propuesta.redondearArriba;
      lista.modoPrecios = 'manual';
      await guardarCambiosDeLista(lista, base);
      return true;
    }
    final informes = await operarPreciosCosto(lista.id!, 'ensayo',
        config: configPreciosCosto(propuesta));
    if (!context.mounted) return false;
    final total = informes.fold<int>(0, (s, i) => s + i.precios);
    final moneda = lista.esEnBolivares ? 'Bs' : '\$';
    String f(double? v) => v == null ? '—' : v.toStringAsFixed(2);
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ensayo: nada se guardó todavía'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      total == 0
                          ? 'Con esta configuración NINGÚN precio cambia.'
                          : 'Con esta configuración cambiarían $total '
                              'precio${total == 1 ? '' : 's'}:',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  for (final i in informes) ...[
                    Text('«${i.nombre}»: ${i.precios} precio(s) en '
                        '${i.items} producto(s)'
                        '${i.agregados > 0 ? ' · ${i.agregados} entran' : ''}'
                        '${i.montosFijos > 0 ? ' · ${i.montosFijos} inicial/cuota fijas se borran' : ''}',
                        style: const TextStyle(fontSize: 12)),
                    for (final e in i.ejemplos)
                      Text('   ${e.nombre}: ${f(e.antes)} → ${f(e.despues)}',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.black54)),
                    const SizedBox(height: 6),
                  ],
                  const Divider(),
                  Text(
                      'Al activar, «${lista.nombre}» queda en modo costo: el '
                      'servidor recalcula sus precios cuando cambie el costo '
                      'de un producto, la tasa o la configuración. Se guarda '
                      'un respaldo para volver atrás. ($moneda)',
                      style: const TextStyle(fontSize: 11)),
                ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('NO ACTIVAR')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('ACTIVAR')),
        ],
      ),
    );
    if (confirmar != true) return false;
    await operarPreciosCosto(lista.id!, 'activar',
        config: configPreciosCosto(propuesta));
    lista.adoptar(await leerListaDelServidor(lista.id!,
        conocidaTeniaProductos: lista.items.isNotEmpty));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('«${lista.nombre}» calcula sus precios desde el costo'),
          backgroundColor: AppColors.statusGreen));
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('No se pudo: $e'),
          backgroundColor: AppColors.statusRed,
          duration: const Duration(seconds: 6)));
    }
    return false;
  }
}

/// Lista Divisas pareja de una lista en Bs (modo costo, misma marca, la
/// que más categorías comparte). Igual que plParDivisas del servidor.
ListaPrecio? listaDivisasPareja(ListaPrecio lb, List<ListaPrecio> listas) {
  if (!lb.esEnBolivares || lb.esFinanciamiento) return null;
  List<String> cats(ListaPrecio l) => l.categoria
      .split(',')
      .map((c) => c.trim().toLowerCase())
      .where((c) => c.isNotEmpty)
      .toList();
  final mias = cats(lb);
  ListaPrecio? mejor;
  var puntos = 0;
  for (final l in listas) {
    if (l.esEnBolivares || l.esFinanciamiento || !l.esModoCosto) continue;
    if (l.marcaFiltro.toLowerCase() != lb.marcaFiltro.toLowerCase()) continue;
    final suyas = cats(l);
    final comunes = mias.where(suyas.contains).length;
    final p = comunes * 1000 - suyas.where((c) => !mias.contains(c)).length;
    if (comunes > 0 && (mejor == null || p > puntos)) {
      mejor = l;
      puntos = p;
    }
  }
  return mejor;
}

/// Explica de dónde sale el precio de un producto en una lista en modo
/// costo (solo para quien gestiona listas). (Brizuela f8ed6ee)
void explicarPrecioLista(
    BuildContext context, ListaPrecio lista, ItemListaPrecio? item) {
  final p = item?.producto;
  final moneda = lista.esEnBolivares ? 'Bs' : '\$';
  String n(double v) => v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2);
  final par = listaDivisasPareja(lista, listasPreciosGlobal);
  final base = par ?? lista;
  final extra = base.montoAdicionalDolares != 0
      ? ' + \$ ${base.montoAdicionalDolares.toStringAsFixed(2)}'
      : '';
  String pctDe(ListaPrecio l) {
    final r = p == null ? null : reglaPara(l.reglasPct, p.nombre, p.marca);
    return r == null
        ? '${n(l.pctSobreCosto)} %'
        : '${n(r.pct)} % (% especial «${r.nombre}»)';
  }

  final lineas = <String>[
    if (!lista.esModoCosto)
      'Esta lista está A MANO: sus precios se escriben en la lista.'
    else ...[
      if (p != null) 'Costo: \$ ${p.precioCosto.toStringAsFixed(2)}',
      if (lista.esFinanciamiento && p != null) ...[
        'Precio de venta: \$ ${p.precioVenta.toStringAsFixed(2)}',
        '«${lista.nombre}»: precio de venta$extra + ${pctDe(lista)}',
      ] else
        '«${base.nombre}»: costo$extra + ${pctDe(base)}',
      if (base.redondearArriba && !lista.esEnBolivares)
        'Redondeado hacia arriba, sin decimales',
      if (lista.esEnBolivares)
        '× tasa ${lista.tasaDelDia.toStringAsFixed(2)} '
            '${lista.tasaFija ? "(tasa fija de la lista)" : par != null && par.tasaBs > 0 ? "(tasa manual de «${par.nombre}»)" : "(BCV del día)"}',
      if (lista.esEnBolivares && lista.redondearArriba)
        'Redondeado hacia arriba, a bolívares enteros',
    ],
    if (item != null && lista.columnas.isNotEmpty)
      'Precio en la lista: $moneda '
          '${(item.preciosPorColumna[lista.columnas.first.nombre] ?? 0).toStringAsFixed(2)}',
    if (item != null && item.preciosPorColumna.containsKey('\$BCV'))
      'En \$ a la tasa BCV: \$ ${item.preciosPorColumna['\$BCV']!.toStringAsFixed(2)}',
  ];
  showDialog(
      context: context,
      builder: (c) => AlertDialog(
              title: Text(p?.nombre ?? 'Precios automáticos'),
              content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final l in lineas)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(l, style: const TextStyle(fontSize: 13))),
                    const SizedBox(height: 8),
                    if (lista.esModoCosto)
                      const Text(
                          'Los precios de esta lista se calculan solos desde el '
                          'costo. Para cambiarlos, cambia el costo del producto o '
                          'el % y la tasa de la lista.',
                          style: TextStyle(fontSize: 11, color: Colors.grey)),
                  ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c),
                    child: const Text('ENTENDIDO')),
              ]));
}

/// Pregunta cómo recalcular los precios de una lista manual (respetando
/// o no las celdas fijadas a mano). Devuelve 'respetar', 'todos' o null.
Future<String?> preguntarRecalcularPrecios(
    BuildContext context, ListaPrecio lista) async {
  final vivos = lista.items.where((it) => !it.fueraDeCatalogo).toList();
  if (vivos.isEmpty) return null;
  final hayManuales = vivos.any((it) => it.columnasManuales.isNotEmpty);
  final moneda = lista.esEnBolivares ? 'Bs' : '\$';
  final muestra = vivos.first;
  final antes = lista.precioBaseDe(muestra);
  final despues = lista.precioPorDefecto(muestra.producto);
  final verPct = puedeVerPorcentajesDeListas();
  return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
              title: const Text('Recalcular precios'),
              content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (verPct)
                      Text(
                          'Precio de partida: precio de venta'
                          '${lista.montoAdicionalDolares != 0 ? ' + \$${lista.montoAdicionalDolares.toStringAsFixed(2)}' : ''}'
                          ' + ${lista.porcentajeAdicional.toStringAsFixed(2)} %'
                          '${lista.esEnBolivares ? ' × ${lista.tasaParaPoblar.toStringAsFixed(2)}' : ''}',
                          style: const TextStyle(fontSize: 12)),
                    const Divider(height: 18),
                    Text(muestra.producto.nombre,
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis),
                    Text(
                        '$moneda ${antes.toStringAsFixed(2)}   →   '
                        '$moneda ${despues.toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppColors.royalBlue)),
                    const SizedBox(height: 10),
                    Text('Se aplicará a los ${vivos.length} productos.',
                        style: const TextStyle(fontSize: 12)),
                    if (hayManuales) ...[
                      const SizedBox(height: 6),
                      const Text(
                          'Hay precios fijados a mano (✎). Puedes conservarlos '
                          'o rehacerlos también.',
                          style: TextStyle(fontSize: 11, color: Colors.grey)),
                    ],
                  ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('CANCELAR')),
                if (hayManuales)
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, 'todos'),
                      child: const Text('RECALCULAR TODOS')),
                ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, 'respetar'),
                    child: Text(
                        hayManuales ? 'RESPETAR LOS FIJADOS' : 'RECALCULAR')),
              ]));
}
