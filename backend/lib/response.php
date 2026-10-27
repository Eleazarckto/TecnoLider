<?php
// ════════════════════════════════════════════════════════════════════
//  response.php — Helpers para respuestas JSON estandarizadas
// ════════════════════════════════════════════════════════════════════

declare(strict_types=1);

/**
 * Devuelve una respuesta JSON con código HTTP y termina la ejecución.
 */
function json_response($data, int $http = 200): void {
    http_response_code($http);
    header('Content-Type: application/json; charset=utf-8');
    header('Access-Control-Allow-Origin: *');
    header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
    header('Access-Control-Allow-Headers: Content-Type, Accept, Authorization');
    echo json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

/**
 * Devuelve un error con formato consistente.
 */
function json_error(string $mensaje, int $http = 400, $detalles = null): void {
    $payload = ['error' => $mensaje];
    if ($detalles !== null) $payload['detalles'] = $detalles;
    json_response($payload, $http);
}

/**
 * Lee el body JSON de la request y lo decodifica.
 */
function json_body(): array {
    $raw = file_get_contents('php://input');
    if ($raw === '' || $raw === false) return [];
    $data = json_decode($raw, true);
    if (!is_array($data)) {
        json_error('Body JSON inválido', 400);
    }
    return $data;
}

/**
 * Devuelve un parámetro GET, con valor por defecto.
 */
function get_param(string $clave, $default = null) {
    return isset($_GET[$clave]) && $_GET[$clave] !== '' ? $_GET[$clave] : $default;
}

/**
 * Maneja preflight CORS (OPTIONS) — termina inmediatamente con 204.
 */
function handle_cors(): void {
    if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
        header('Access-Control-Allow-Origin: *');
        header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
        header('Access-Control-Allow-Headers: Content-Type, Accept, Authorization');
        http_response_code(204);
        exit;
    }
}

/**
 * Wrapper que ejecuta una función con manejo central de errores.
 */
function safe_run(callable $fn): void {
    handle_cors();
    try {
        $fn();
    } catch (PDOException $e) {
        error_log('[PDO] ' . $e->getMessage());
        json_error('Error en base de datos', 500, $e->getMessage());
    } catch (Throwable $e) {
        error_log('[ERR] ' . $e->getMessage() . "\n" . $e->getTraceAsString());
        json_error('Error interno del servidor', 500, $e->getMessage());
    }
}

/**
 * Registra una entrada en la tabla auditoria.
 */
function audit(string $tabla, $registroId, string $accion,
               ?string $usuario = null,
               ?array $antes = null, ?array $despues = null): void {
    try {
        $stmt = db()->prepare(
            'INSERT INTO auditoria (tabla, registro_id, accion, usuario,
                                    datos_antes, datos_despues, ip_origen)
             VALUES (?, ?, ?, ?, ?, ?, ?)'
        );
        $stmt->execute([
            $tabla, (string)$registroId, $accion, $usuario,
            $antes   !== null ? json_encode($antes,   JSON_UNESCAPED_UNICODE) : null,
            $despues !== null ? json_encode($despues, JSON_UNESCAPED_UNICODE) : null,
            $_SERVER['REMOTE_ADDR'] ?? null,
        ]);
    } catch (Throwable $e) {
        error_log('[AUDIT] No se pudo registrar: ' . $e->getMessage());
    }
}
