<?php
// Endpoint: /api.php?resource=tiendas
//
// CRUD de tiendas. Guarda además de nombre/direccion/telefono/rif/activa
// los datos de encabezado que se usan en las facturas y ticketes:
//   · correo
//   · logo_base64 (LONGTEXT — el logo en base64 dataURI para reproducir
//                  desde cualquier PC sin tener el archivo local)
//
// HISTORIAL: antes el logo, RIF, dirección, correo, teléfono se
// guardaban SOLO en SharedPreferences local de cada PC. Al abrir sesión
// en otra máquina, no aparecían. Ahora se persisten en la BD y bajan
// automáticamente al hacer login desde cualquier lugar.

$pdo = db();
$pdo->setAttribute(PDO::ATTR_DEFAULT_FETCH_MODE, PDO::FETCH_ASSOC);

// Asegurar tabla + columnas nuevas (auto-migración idempotente).
$pdo->exec("
    CREATE TABLE IF NOT EXISTS tiendas (
        id          INT AUTO_INCREMENT PRIMARY KEY,
        nombre      VARCHAR(120) NOT NULL DEFAULT '',
        direccion   VARCHAR(255) NOT NULL DEFAULT '',
        telefono    VARCHAR(60)  NOT NULL DEFAULT '',
        rif         VARCHAR(40)  NOT NULL DEFAULT '',
        correo      VARCHAR(120) NOT NULL DEFAULT '',
        logo_base64 LONGTEXT     NULL,
        activa      TINYINT(1)   NOT NULL DEFAULT 1
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
");
// Migración suave: agregar columnas si venimos de una versión previa
// que solo tenía nombre/direccion/telefono/rif/activa.
$columnasExpected = [
    'direccion'   => "VARCHAR(255) NOT NULL DEFAULT ''",
    'telefono'    => "VARCHAR(60)  NOT NULL DEFAULT ''",
    'rif'         => "VARCHAR(40)  NOT NULL DEFAULT ''",
    'correo'      => "VARCHAR(120) NOT NULL DEFAULT ''",
    'logo_base64' => "LONGTEXT NULL",
    'activa'      => "TINYINT(1) NOT NULL DEFAULT 1",
];
foreach ($columnasExpected as $col => $def) {
    try {
        $exists = (int) $pdo->query(
            "SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
             WHERE TABLE_SCHEMA = DATABASE()
               AND TABLE_NAME   = 'tiendas'
               AND COLUMN_NAME  = '$col'"
        )->fetchColumn();
        if ($exists === 0) {
            $pdo->exec("ALTER TABLE tiendas ADD COLUMN $col $def");
        }
    } catch (Throwable $_) { /* continuar */ }
}

$tabla = 'tiendas';
// Whitelist con TODAS las columnas editables (incluidas las nuevas).
$columnas = ['nombre', 'direccion', 'telefono', 'rif',
             'correo', 'logo_base64', 'activa'];

// ────────────────────────────────────────────────────────────────
//  Override del DELETE: proteger contra eliminar la última tienda
// ────────────────────────────────────────────────────────────────
if ($_SERVER['REQUEST_METHOD'] === 'DELETE') {
    $id = (int) get_param('id');
    if ($id <= 0) json_error('id inválido', 400);
    $cnt = (int) $pdo->query('SELECT COUNT(*) FROM tiendas WHERE activa = 1')
                     ->fetchColumn();
    if ($cnt <= 1) {
        json_error('No se puede eliminar la última tienda', 409);
    }
    $stmt = $pdo->prepare('DELETE FROM tiendas WHERE id = ?');
    $stmt->execute([$id]);
    if ($stmt->rowCount() === 0) {
        json_error('Tienda no encontrada', 404);
    }
    json_response(['ok' => true, 'id' => $id]);
}

// GET listar, POST crear, PUT editar → flujo estándar del router
despachar_crud($tabla, $columnas);
