<?php
// ════════════════════════════════════════════════════════════════════
//  Endpoint: ficha técnica de cada producto (traída de Brizuela, SIN IA)
// ════════════════════════════════════════════════════════════════════
//    ?resource=ficha_tecnica                 (GET)  → resumen
//         {total, con_ficha, fichas:[{codigo, origen, llenos}]}
//    ?resource=ficha_tecnica&codigo=X        (GET)  → la ficha (o la
//         plantilla vacía si todavía no tiene)
//    ?resource=ficha_tecnica_guardar         (POST)
//         {usuario_correo, codigo, campos:[{grupo, campo, valor}], por_revisar?}
//
//  Cada producto tiene una ficha con los datos que le corresponden según
//  lo que es: un teléfono lleva pantalla, procesador, cámaras, batería…;
//  un televisor, pulgadas, resolución y conexiones; un forro,
//  compatibilidad y material. Eso lo deciden las PLANTILLAS de abajo.
//
//  En Tecno Líder NO hay IA: la ficha se llena a mano desde el inventario
//  (origen «manual») o con los scripts de backend/herramientas_fichas/
//  (origen «auto», queda para revisar).
//
//  Diferencias con Brizuela:
//   · `productos` tiene una fila por tienda (UNIQUE(codigo, tienda)) y
//     borrado lógico (`eliminado_en`): se busca por código, sin las
//     borradas, y el total cuenta códigos distintos.
//   · No hay tabla de categorías: qué categorías usan IMEI está en
//     `configuracion` (clave cfg_categorias_productos, JSON que guarda la
//     app con [{nombre, usa_imei}]).
//   · No hay sesiones en el servidor: la app manda `usuario_correo` y para
//     GUARDAR se exige que sea un usuario activo con rol de FICHA_ROLES
//     (el maestro de soporte no está en `usuarios`: va por su correo).
//     Ver: cualquiera (como el resto de la API).
//
//  Errores: 400 con {ok:false, error}. La app instalada muestra el texto
//  de un 400; un 403/404/409 lo cambia por un mensaje genérico.
//
//  Las pruebas (backend/tests/ficha_tecnica_test.php) definen
//  FICHA_SOLO_FUNCIONES antes de incluir este archivo: así cargan las
//  funciones sin atender el pedido.
// ════════════════════════════════════════════════════════════════════

const FICHA_ROLES = ['Dueño', 'Dueno', 'Administrador', 'Gerente', 'Encargado', 'Activador', 'Maestro'];
/** El usuario maestro (soporte) vive en la app, no en la tabla usuarios. */
const FICHA_CORREOS_MAESTRO = ['eleazarceccato@gmail.com'];
const FICHA_MAX_VALOR = 300;
const FICHA_MAX_CAMPOS = 80;
const FICHA_CLAVE_CATEGORIAS = 'cfg_categorias_productos';

if (!class_exists('FichaError', false)) {
    final class FichaError extends RuntimeException {}
}

// ────────────────────────────────────────────────────────────────────────
//  Plantillas: qué datos lleva la ficha según el tipo de producto
// ────────────────────────────────────────────────────────────────────────

function fichaPlantillas(): array {
    return [
        'equipo' => [
            'titulo' => 'Teléfono / tablet',
            'grupos' => [
                'Pantalla'     => ['Tamaño', 'Tipo de panel', 'Resolución', 'Frecuencia de actualización'],
                'Rendimiento'  => ['Procesador', 'Memoria RAM', 'Almacenamiento', 'Memoria expandible'],
                'Cámaras'      => ['Cámara principal', 'Cámaras adicionales', 'Cámara frontal', 'Grabación de video'],
                'Batería'      => ['Capacidad', 'Carga rápida', 'Carga inalámbrica'],
                'Sistema'      => ['Sistema operativo', 'Capa de personalización'],
                'Conectividad' => ['Red', 'SIM', 'Wi-Fi', 'Bluetooth', 'NFC', 'Puerto'],
                'Diseño'       => ['Dimensiones', 'Peso', 'Resistencia (IP)', 'Colores'],
                'Seguridad'    => ['Desbloqueo'],
            ],
        ],
        'computadora' => [
            'titulo' => 'Laptop',
            'grupos' => [
                'Pantalla'     => ['Tamaño', 'Resolución', 'Tipo de panel'],
                'Rendimiento'  => ['Procesador', 'Memoria RAM', 'Almacenamiento', 'Gráficos'],
                'Sistema'      => ['Sistema operativo'],
                'Conectividad' => ['Wi-Fi', 'Bluetooth', 'Puertos'],
                'Batería'      => ['Duración', 'Cargador'],
                'Diseño'       => ['Peso', 'Teclado', 'Colores'],
            ],
        ],
        'reloj' => [
            'titulo' => 'Reloj inteligente',
            'grupos' => [
                'Pantalla'      => ['Tamaño', 'Tipo de panel', 'Resolución'],
                'Salud y deporte' => ['Sensores', 'Modos deportivos', 'GPS'],
                'Batería'       => ['Duración', 'Carga'],
                'Conectividad'  => ['Bluetooth', 'Compatibilidad', 'Llamadas'],
                'Diseño'        => ['Material', 'Resistencia al agua', 'Peso', 'Colores'],
            ],
        ],
        'audio' => [
            'titulo' => 'Audio',
            'grupos' => [
                'General'  => ['Tipo', 'Conexión', 'Versión de Bluetooth', 'Alcance'],
                'Sonido'   => ['Controladores', 'Cancelación de ruido', 'Micrófono', 'Potencia'],
                'Batería'  => ['Duración', 'Duración con estuche', 'Carga'],
                'Diseño'   => ['Resistencia al agua', 'Peso', 'Colores'],
                'Compatibilidad' => ['Compatible con'],
            ],
        ],
        // Los accesorios van por tipo (14/10/2026): con una sola plantilla
        // un forro mostraba Potencia, Voltaje y Conector siempre vacíos.
        'forro' => [
            'titulo' => 'Forro',
            'grupos' => ['General' => ['Tipo', 'Compatible con', 'Material', 'Colores']],
        ],
        'carga' => [
            'titulo' => 'Cargador / cable',
            'grupos' => [
                'General'   => ['Tipo', 'Compatible con', 'Material'],
                'Eléctrico' => ['Potencia', 'Voltaje / corriente'],
                'Conexión'  => ['Conector', 'Longitud del cable'],
            ],
        ],
        'bateria' => [
            'titulo' => 'Batería externa',
            'grupos' => [
                'General'   => ['Tipo', 'Compatible con'],
                'Eléctrico' => ['Capacidad', 'Potencia'],
                'Conexión'  => ['Conector'],
            ],
        ],
        'vidrio' => [
            'titulo' => 'Protector de pantalla',
            'grupos' => ['General' => ['Tipo', 'Compatible con']],
        ],
        'red' => [
            'titulo' => 'Router / repetidor',
            'grupos' => ['General' => ['Tipo', 'Velocidad', 'Antenas']],
        ],
        'memoria' => [
            'titulo' => 'Memoria',
            'grupos' => ['General' => ['Tipo', 'Capacidad']],
        ],
        'accesorio' => [
            'titulo' => 'Accesorio',
            'grupos' => ['General' => ['Tipo', 'Compatible con', 'Material', 'Colores']],
        ],
        'televisor' => [
            'titulo' => 'Televisor',
            'grupos' => [
                'Pantalla'   => ['Tamaño', 'Resolución', 'Tipo de panel', 'HDR', 'Frecuencia de actualización'],
                'Smart TV'   => ['Sistema', 'Aplicaciones', 'Control por voz'],
                'Sonido'     => ['Potencia', 'Tecnologías de audio'],
                'Conexiones' => ['HDMI', 'USB', 'Wi-Fi', 'Bluetooth', 'Ethernet'],
                'Físico'     => ['Dimensiones sin base', 'Dimensiones con base', 'Peso', 'Montaje VESA'],
                'Energía'    => ['Consumo', 'Voltaje'],
            ],
        ],
        'linea_blanca' => [
            'titulo' => 'Línea blanca',
            'grupos' => [
                'General' => ['Tipo', 'Capacidad', 'Funciones / programas', 'Color / acabado'],
                'Energía' => ['Consumo', 'Eficiencia energética', 'Voltaje'],
                'Físico'  => ['Dimensiones', 'Peso'],
            ],
        ],
        'linea' => [
            'titulo' => 'Línea / SIM',
            'grupos' => [
                'General' => ['Operadora', 'Tipo de línea', 'Tecnología de red', 'Formato de SIM', 'Plan / datos incluidos'],
            ],
        ],
        'servicio' => [
            'titulo' => 'Servicio técnico',
            'grupos' => [
                'Servicio' => ['Descripción', 'Tiempo estimado', 'Incluye', 'Garantía del servicio', 'Requisitos'],
            ],
        ],
        'generico' => [
            'titulo' => 'Producto',
            'grupos' => [
                'General' => ['Tipo', 'Características principales', 'Material', 'Colores'],
                'Físico'  => ['Dimensiones', 'Peso'],
            ],
        ],
    ];
}

/** ¿Alguna de las palabras aparece en el texto? (ya en minúsculas y sin acentos) */
function fichaTiene(string $texto, array $palabras): bool {
    foreach ($palabras as $p) {
        if (preg_match('/(^|[^a-z0-9])' . preg_quote($p, '/') . '/', $texto)) return true;
    }
    return false;
}

function fichaSinAcentos(string $s): string {
    $s = mb_strtolower($s, 'UTF-8');
    return strtr($s, ['á' => 'a', 'é' => 'e', 'í' => 'i', 'ó' => 'o', 'ú' => 'u', 'ü' => 'u', 'ñ' => 'n']);
}

/**
 * Qué plantilla le toca a un producto. Pura.
 * El nombre manda sobre la categoría para lo que la categoría no distingue
 * (en «Accesorio» hay forros, cargadores, audífonos y relojes).
 */
function fichaPlantillaPara(string $categoria, string $nombre, bool $usaImei = false): string {
    $cat = fichaSinAcentos($categoria);
    $nom = fichaSinAcentos($nombre);
    $todo = "$cat $nom";

    if (str_contains($cat, 'servicio')) return 'servicio';
    if (trim($cat) === 'linea' || fichaTiene($cat, ['sim', 'chip', 'lineas'])) return 'linea';
    // La categoría Línea Blanca manda («Aire de ventana con control» no es
    // un accesorio), salvo lo que se cargó ahí y es de TV.
    if (str_contains($cat, 'linea blanca') && !fichaTiene($nom, ['tv', 'televisor', 'soporte', 'base'])) {
        return 'linea_blanca';
    }
    // Accesorios que nombran al equipo con el que van: «Cargador Apple
    // Watch», «Forro iPhone 13», «Soporte para TV». Antes que televisor,
    // reloj y teléfono.
    if (fichaTiene($nom, ['cargador', 'cable', 'forro', 'funda', 'estuche', 'protector', 'vidrio', 'mica',
                          'adaptador', 'soporte', 'base', 'power bank', 'powerbank', 'battery pack',
                          'bateria externa', 'correa', 'memoria', 'pendrive', 'tripode', 'aro de luz',
                          'lapiz', 'stylus', 'control', 'gamepad', 'amplificador'])) {
        return fichaTipoDeAccesorio($nom);
    }
    if (fichaTiene($todo, ['laptop', 'lapto', 'laptp', 'macbook', 'notebook', 'laptops'])) return 'computadora';
    if (fichaTiene($todo, ['televisor', 'tv', 'smart tv'])) return 'televisor';
    if (str_contains($cat, 'linea blanca')
        || fichaTiene($nom, ['nevera', 'lavadora', 'secadora', 'cocina', 'microondas', 'aire acondicionado', 'freezer', 'congelador'])) {
        return 'linea_blanca';
    }
    if (fichaTiene($todo, ['reloj', 'watch', 'smartwatch', 'smart band', 'banda inteligente'])) return 'reloj';
    if (fichaTiene($todo, ['audifono', 'audifonos', 'auricular', 'airpods', 'buds', 'corneta', 'parlante',
                           'speaker', 'headset', 'cascos', 'barra de sonido'])) {
        return 'audio';
    }
    if ($usaImei || fichaTiene($todo, ['telefono', 'celular', 'smartphone', 'tablet', 'ipad', 'iphone', 'equipo'])) {
        return 'equipo';
    }
    if (str_contains($cat, 'accesorio')) return fichaTipoDeAccesorio($nom);
    return 'generico';
}

/** Qué plantilla de accesorio le toca, por el nombre. Pura. */
function fichaTipoDeAccesorio(string $nom): string {
    if (fichaTiene($nom, ['forro', 'funda'])) return 'forro';
    if (fichaTiene($nom, ['power bank', 'powerbank', 'power band', 'battery pack', 'bateria externa', 'ups', 'mini ups'])) {
        return 'bateria';
    }
    if (fichaTiene($nom, ['cargador', 'cable', 'car charger', 'taco', 'adaptador'])) return 'carga';
    if (fichaTiene($nom, ['vidrio', 'mica', 'protector de pantalla'])) return 'vidrio';
    if (fichaTiene($nom, ['router', 'repetidor', 'extensor'])) return 'red';
    if (fichaTiene($nom, ['pendrive', 'tarjeta de memoria', 'memoria'])) return 'memoria';
    return 'accesorio';
}

/** La plantilla como lista plana [{grupo, campo, valor:''}]. */
function fichaCamposVacios(string $plantilla): array {
    $p = fichaPlantillas()[$plantilla] ?? fichaPlantillas()['generico'];
    $campos = [];
    foreach ($p['grupos'] as $grupo => $nombres) {
        foreach ($nombres as $c) $campos[] = ['grupo' => $grupo, 'campo' => $c, 'valor' => ''];
    }
    return $campos;
}

/**
 * Limpia lo que manda la app (o un script): textos recortados, sin duplicados,
 * con tope de cantidad y de largo. Los campos vacíos se conservan: la app
 * muestra la plantilla completa.
 */
function fichaNormalizarCampos($crudos): array {
    if (!is_array($crudos)) return [];
    $vistos = [];
    $salida = [];
    foreach ($crudos as $c) {
        if (!is_array($c)) continue;
        $grupo = trim(preg_replace('/\s+/u', ' ', (string)($c['grupo'] ?? '')));
        $campo = trim(preg_replace('/\s+/u', ' ', (string)($c['campo'] ?? '')));
        $valor = trim((string)($c['valor'] ?? ''));
        if ($campo === '') continue;
        if ($grupo === '') $grupo = 'General';
        $clave = mb_strtolower("$grupo|$campo", 'UTF-8');
        if (isset($vistos[$clave])) continue;
        $vistos[$clave] = true;
        $salida[] = [
            'grupo' => mb_substr($grupo, 0, 60),
            'campo' => mb_substr($campo, 0, 60),
            'valor' => mb_substr($valor, 0, FICHA_MAX_VALOR),
        ];
        if (count($salida) >= FICHA_MAX_CAMPOS) break;
    }
    return $salida;
}

/**
 * Lo guardado sobre la plantilla: primero los campos de la plantilla en su
 * orden (con el valor guardado si lo hay) y después los que se agregaron a
 * mano. Así una plantilla que gane campos los muestra en fichas viejas.
 */
function fichaCombinar(string $plantilla, array $guardados): array {
    $porClave = [];
    foreach ($guardados as $c) $porClave[mb_strtolower("{$c['grupo']}|{$c['campo']}", 'UTF-8')] = $c;
    $salida = [];
    foreach (fichaCamposVacios($plantilla) as $c) {
        $k = mb_strtolower("{$c['grupo']}|{$c['campo']}", 'UTF-8');
        if (isset($porClave[$k])) {
            $c['valor'] = $porClave[$k]['valor'];
            unset($porClave[$k]);
        }
        $salida[] = $c;
    }
    // Los que no están en la plantilla solo si tienen valor: una ficha vieja
    // con «Garantía» vacía no tiene que seguir mostrándola.
    foreach ($porClave as $c) {
        if (trim((string)$c['valor']) !== '') $salida[] = $c;
    }
    return $salida;
}

function fichaLlenos(array $campos): int {
    return count(array_filter($campos, fn($c) => trim((string)$c['valor']) !== ''));
}


// ────────────────────────────────────────────────────────────────────────
//  Base de datos
// ────────────────────────────────────────────────────────────────────────

/**
 * Crea la tabla si falta (aditivo: no toca nada existente). La misma
 * sentencia está en reparar_esquema.php; si se cambia acá, cambiarla allá.
 */
function fichaEsquema(PDO $pdo): void {
    static $hecho = false;
    if ($hecho) return;
    $mysql = $pdo->getAttribute(PDO::ATTR_DRIVER_NAME) === 'mysql';
    $pdo->exec("CREATE TABLE IF NOT EXISTS fichas_tecnicas (
        producto_codigo VARCHAR(100) NOT NULL PRIMARY KEY,
        plantilla   VARCHAR(30)  NOT NULL DEFAULT '',
        campos      TEXT,
        origen      VARCHAR(10)  NOT NULL DEFAULT '',
        nota        VARCHAR(500) NOT NULL DEFAULT '',
        actualizado DATETIME NULL,
        por         VARCHAR(150) NOT NULL DEFAULT ''
    )" . ($mysql ? ' ENGINE=InnoDB DEFAULT CHARSET=utf8mb4' : ''));
    $hecho = true;
}

/**
 * ` AND eliminado_en IS NULL` si la tabla tiene esa columna (como
 * filtro_no_eliminado() de lib/esquema.php, pero con el PDO que se le
 * pasa, para poder probarlo con SQLite).
 */
function fichaSinBorrados(PDO $pdo, string $tabla): string {
    static $cache = [];
    if (!array_key_exists($tabla, $cache)) {
        try {
            $pdo->query("SELECT eliminado_en FROM $tabla WHERE 1 = 0");
            $cache[$tabla] = true;
        } catch (Throwable $e) {
            $cache[$tabla] = false;
        }
    }
    return $cache[$tabla] ? ' AND eliminado_en IS NULL' : '';
}

/** El producto (una fila de cualquier tienda: nombre y categoría son los mismos). */
function fichaProducto(PDO $pdo, string $codigo): ?array {
    if ($codigo === '') return null;
    $st = $pdo->prepare('SELECT codigo, nombre, categoria, marca, modelo FROM productos
                         WHERE codigo = ?' . fichaSinBorrados($pdo, 'productos') . ' ORDER BY id LIMIT 1');
    $st->execute([$codigo]);
    $p = $st->fetch(PDO::FETCH_ASSOC);
    return $p ?: null;
}

/**
 * ¿La categoría usa IMEI? Sale de configuracion.cfg_categorias_productos
 * ([{nombre, usa_imei}], lo guarda la app). Si falta o falla, no.
 */
function fichaUsaImei(PDO $pdo, string $categoria): bool {
    try {
        $st = $pdo->prepare('SELECT valor FROM configuracion WHERE clave = ? LIMIT 1');
        $st->execute([FICHA_CLAVE_CATEGORIAS]);
        $lista = json_decode((string)$st->fetchColumn(), true);
        if (!is_array($lista)) return false;
        $buscada = mb_strtolower(trim($categoria), 'UTF-8');
        foreach ($lista as $c) {
            if (!is_array($c)) continue;
            if (mb_strtolower(trim((string)($c['nombre'] ?? '')), 'UTF-8') !== $buscada) continue;
            $u = $c['usa_imei'] ?? false;
            return $u === true || $u === 1 || $u === '1' || $u === 'true';
        }
    } catch (Throwable $e) {
        // Sin tabla configuracion o JSON roto: la plantilla sale por el nombre.
    }
    return false;
}

function fichaPlantillaDeProducto(PDO $pdo, array $p): string {
    return fichaPlantillaPara((string)$p['categoria'], (string)$p['nombre'],
        fichaUsaImei($pdo, (string)$p['categoria']));
}

function fichaFila(PDO $pdo, string $codigo): ?array {
    $st = $pdo->prepare('SELECT * FROM fichas_tecnicas WHERE producto_codigo = ?');
    $st->execute([$codigo]);
    $f = $st->fetch(PDO::FETCH_ASSOC);
    return $f ?: null;
}

function fichaEscribir(PDO $pdo, string $codigo, string $plantilla, array $campos, string $origen,
                       string $por, string $nota = ''): void {
    $valores = [$plantilla, json_encode($campos, JSON_UNESCAPED_UNICODE), $origen,
                mb_substr($nota, 0, 500), date('Y-m-d H:i:s'), mb_substr($por, 0, 150), $codigo];
    $st = $pdo->prepare('UPDATE fichas_tecnicas SET plantilla = ?, campos = ?, origen = ?, nota = ?,
                         actualizado = ?, por = ? WHERE producto_codigo = ?');
    $st->execute($valores);
    if ($st->rowCount() === 0 && fichaFila($pdo, $codigo) === null) {
        $pdo->prepare('INSERT INTO fichas_tecnicas (plantilla, campos, origen, nota, actualizado, por, producto_codigo)
                       VALUES (?, ?, ?, ?, ?, ?, ?)')->execute($valores);
    }
}

/** La ficha completa para la app. */
function fichaDe(PDO $pdo, array $p): array {
    $f = fichaFila($pdo, (string)$p['codigo']);
    $plantilla = fichaPlantillaDeProducto($pdo, $p);
    $guardados = $f ? fichaNormalizarCampos(json_decode((string)$f['campos'], true)) : [];
    $campos = fichaCombinar($plantilla, $guardados);
    return [
        'codigo'      => (string)$p['codigo'],
        'nombre'      => (string)$p['nombre'],
        'plantilla'   => $plantilla,
        'titulo'      => fichaPlantillas()[$plantilla]['titulo'] ?? 'Producto',
        'campos'      => $campos,
        'llenos'      => fichaLlenos($campos),
        'origen'      => $f['origen'] ?? '',
        'nota'        => $f['nota'] ?? '',
        'actualizado' => $f['actualizado'] ?? null,
        'por'         => $f['por'] ?? '',
    ];
}

// ────────────────────────────────────────────────────────────────────────
//  Recursos
// ────────────────────────────────────────────────────────────────────────

/**
 * Quién pide. Ver: cualquiera. Guardar: un usuario activo (no borrado)
 * con rol de FICHA_ROLES, o el maestro de soporte.
 */
function fichaIdentidad(PDO $pdo, array $q, bool $editar): array {
    $correo = trim((string)($q['usuario_correo'] ?? ''));
    if (!$editar) return ['correo' => $correo, 'rol' => ''];
    if ($correo === '') {
        throw new FichaError('Falta el usuario: actualice la aplicación e inicie sesión de nuevo.', 400);
    }
    if (in_array(mb_strtolower($correo, 'UTF-8'), FICHA_CORREOS_MAESTRO, true)) {
        return ['correo' => $correo, 'rol' => 'Maestro'];
    }
    $st = $pdo->prepare('SELECT correo, rol, activo FROM usuarios
                         WHERE LOWER(correo) = LOWER(?)' . fichaSinBorrados($pdo, 'usuarios') . ' LIMIT 1');
    $st->execute([$correo]);
    $u = $st->fetch(PDO::FETCH_ASSOC);
    if (!$u || (isset($u['activo']) && (int)$u['activo'] !== 1)) {
        throw new FichaError('Ese usuario no existe o está desactivado.', 400);
    }
    if (!in_array((string)$u['rol'], FICHA_ROLES, true)) {
        throw new FichaError('Solo el Dueño, un Administrador, un Gerente, un Encargado o un Activador '
            . 'puede cambiar la ficha técnica.', 400);
    }
    return ['correo' => (string)$u['correo'], 'rol' => (string)$u['rol']];
}

function fichaResumen(PDO $pdo): array {
    $total = (int)$pdo->query("SELECT COUNT(DISTINCT codigo) FROM productos WHERE codigo <> ''"
        . fichaSinBorrados($pdo, 'productos'))->fetchColumn();
    $fichas = [];
    foreach ($pdo->query('SELECT producto_codigo, campos, origen FROM fichas_tecnicas') as $f) {
        $campos = fichaNormalizarCampos(json_decode((string)$f['campos'], true));
        $fichas[] = ['codigo' => (string)$f['producto_codigo'], 'origen' => (string)$f['origen'],
                     'llenos' => fichaLlenos($campos)];
    }
    $conFicha = count(array_filter($fichas, fn($f) => $f['llenos'] > 0));
    return ['total' => $total, 'con_ficha' => $conFicha, 'fichas' => $fichas];
}

function fichaGuardar(PDO $pdo, array $b, array $id): array {
    $p = fichaProducto($pdo, trim((string)($b['codigo'] ?? '')));
    if ($p === null) throw new FichaError('No existe ese producto.', 400);
    $campos = fichaNormalizarCampos($b['campos'] ?? []);
    $plantilla = fichaPlantillaDeProducto($pdo, $p);
    // `por_revisar`: la carga con los scripts de herramientas_fichas/ queda
    // «auto» (para revisar); lo que se guarda desde la app queda «manual».
    $origen = !empty($b['por_revisar']) ? 'auto' : 'manual';
    fichaEscribir($pdo, (string)$p['codigo'], $plantilla, $campos, $origen, (string)$id['correo']);
    return fichaDe($pdo, $p);
}

/**
 * Atiende ficha_tecnica*. Devuelve [código HTTP, cuerpo] o null si el
 * método/recurso no corresponde. No escribe nada: lo hace quien llama.
 */
function fichaAtender(PDO $pdo, string $method, string $resource, array $body, array $get): ?array {
    $rutas = [
        'GET'  => ['ficha_tecnica' => false],
        'POST' => ['ficha_tecnica_guardar' => true],
    ];
    if (!isset($rutas[$method][$resource])) return null;
    $q = $method === 'GET' ? $get : $body;

    try {
        fichaEsquema($pdo);
        $id = fichaIdentidad($pdo, $q, $rutas[$method][$resource]);
        if ($resource === 'ficha_tecnica') {
            $codigo = trim((string)($q['codigo'] ?? ''));
            if ($codigo === '') {
                $datos = fichaResumen($pdo);
            } else {
                $p = fichaProducto($pdo, $codigo);
                if ($p === null) throw new FichaError('No existe ese producto.', 400);
                $datos = fichaDe($pdo, $p);
            }
        } else {
            $datos = fichaGuardar($pdo, $body, $id);
        }
    } catch (FichaError $e) {
        return [400, ['ok' => false, 'error' => $e->getMessage()]];
    } catch (Throwable $e) {
        error_log("[ficha_tecnica] $resource: " . $e->getMessage() . ' en ' . $e->getFile() . ':' . $e->getLine());
        $tipo = $e instanceof PDOException ? 'base de datos ' . $e->getCode() : get_class($e);
        return [500, ['ok' => false, 'error' => "No se pudo completar la operación ($tipo)."]];
    }
    return [200, ['ok' => true, 'data' => $datos]];
}

// ── Atender el pedido (no en las pruebas) ──────────────────────────
if (!defined('FICHA_SOLO_FUNCIONES')) {
    $fichaMetodo  = $_SERVER['REQUEST_METHOD'] ?? 'GET';
    $fichaRecurso = (string) get_param('resource', 'ficha_tecnica');
    $fichaCuerpo  = $fichaMetodo === 'POST' ? json_body() : [];
    $fichaRes = fichaAtender(db(), $fichaMetodo, $fichaRecurso, $fichaCuerpo, $_GET);
    if ($fichaRes === null) {
        json_error('Método no permitido', 405);
    } else {
        json_response($fichaRes[1], $fichaRes[0]);
    }
}
