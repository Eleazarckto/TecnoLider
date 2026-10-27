<?php
// Endpoint: /api.php?resource=configuracion
//
// Guarda la configuración GLOBAL de la app en la tabla `configuracion`
// como pares clave/valor. Sirve para que valores como días de garantía,
// texto de pie de factura, nombre de empresa, moneda, etc. se
// sincronicen entre PCs — antes solo estaban en SharedPreferences local
// y cada PC tenía su propio valor.
//
// Estructura:
//   GET  → devuelve todos los pares { clave => valor }
//   POST → recibe un objeto { clave1: valor1, clave2: valor2, ... }
//          y hace UPSERT (crea o actualiza) cada uno.
//
// Los valores se guardan como TEXT — la app los parsea a int/double/bool
// según corresponda al leerlos.

$pdo = db();
$pdo->setAttribute(PDO::ATTR_DEFAULT_FETCH_MODE, PDO::FETCH_ASSOC);

// Asegurar tabla (auto-migración idempotente)
$pdo->exec("
    CREATE TABLE IF NOT EXISTS configuracion (
        id             INT AUTO_INCREMENT PRIMARY KEY,
        clave          VARCHAR(120) NOT NULL UNIQUE,
        valor          TEXT NULL,
        actualizado_en TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
");

$metodo = $_SERVER['REQUEST_METHOD'];

if ($metodo === 'GET') {
    try {
        $rows = $pdo->query("SELECT clave, valor FROM configuracion")->fetchAll();
        $out = [];
        foreach ($rows as $r) {
            $out[$r['clave']] = $r['valor'];
        }
        json_response($out);
    } catch (Throwable $e) {
        json_error('Error leyendo configuración: ' . $e->getMessage(), 500);
    }
}

if ($metodo === 'POST' || $metodo === 'PUT') {
    $body = json_decode(file_get_contents('php://input'), true);
    if (!is_array($body)) json_error('JSON inválido', 400);

    try {
        $stmt = $pdo->prepare(
            "INSERT INTO configuracion (clave, valor)
             VALUES (?, ?)
             ON DUPLICATE KEY UPDATE valor = VALUES(valor)"
        );
        $guardados = 0;
        foreach ($body as $clave => $valor) {
            // Ignorar claves con nombres inválidos
            $clave = trim((string) $clave);
            if ($clave === '' || strlen($clave) > 120) continue;
            // Serializar el valor a string (guardamos todo como TEXT)
            $val = is_bool($valor) ? ($valor ? '1' : '0')
                 : (is_null($valor) ? null : (string) $valor);
            $stmt->execute([$clave, $val]);
            $guardados++;
        }
        json_response(['ok' => true, 'guardados' => $guardados]);
    } catch (Throwable $e) {
        json_error('Error guardando configuración: ' . $e->getMessage(), 500);
    }
}

json_error('Método no permitido', 405);
