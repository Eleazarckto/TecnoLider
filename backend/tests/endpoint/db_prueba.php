<?php
// ════════════════════════════════════════════════════════════════════
//  db_prueba.php — db() de PRUEBA con SQLite, para facturas_endpoint_test.
//  En el directorio temporal de la prueba se copia como lib/db.php.
//  NUNCA se sube al servidor real ni se pone en backend/lib/.
// ════════════════════════════════════════════════════════════════════
declare(strict_types=1);
// Solo por consola o `php -S` de la prueba: en el sitio real no hace nada.
if (!in_array(PHP_SAPI, ['cli', 'cli-server'], true)) { http_response_code(404); exit; }

function db(): PDO {
    static $pdo = null;
    if ($pdo !== null) return $pdo;
    $ruta = getenv('TL_PRUEBA_SQLITE') ?: (__DIR__ . '/../prueba.sqlite');
    $pdo = new PDO('sqlite:' . $ruta);
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    $pdo->setAttribute(PDO::ATTR_DEFAULT_FETCH_MODE, PDO::FETCH_ASSOC);
    // Funciones de MySQL que usan los endpoints.
    $pdo->sqliteCreateFunction('NOW', static fn() => date('Y-m-d H:i:s'), 0);
    $pdo->sqliteCreateFunction('GREATEST', static fn(...$a) => max($a));
    return $pdo;
}
