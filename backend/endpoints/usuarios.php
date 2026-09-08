<?php
// Endpoint: /api.php?resource=usuarios
// CRUD de usuarios. Filtra al UsuarioMaestro (ese es hardcoded en la app).

$tabla = 'usuarios';
$columnas = [
    'nombre', 'cedula', 'correo', 'clave', 'rol',
    'sueldo_base', 'tienda', 'activo',
    // `gana_comisiones` faltaba en esta lista: la app lo enviaba en
    // cada alta y edición, pero filtrar_columnas() lo descartaba, así
    // que el flag nunca se guardaba y todos los usuarios quedaban con
    // el valor por defecto de la columna.
    'gana_comisiones',
];

// Override del listar para excluir al UsuarioMaestro si por alguna razón
// estuviera en la BD, y permitir login con ?correo=&clave=
if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    $correo = get_param('correo');
    $clave  = get_param('clave');
    if ($correo !== null && $clave !== null) {
        // Login: devuelve UN usuario o nada
        $stmt = db()->prepare(
            "SELECT * FROM usuarios
             WHERE LOWER(correo) = LOWER(?) AND clave = ?
               AND activo = 1 AND eliminado_en IS NULL
             LIMIT 1"
        );
        $stmt->execute([$correo, $clave]);
        $row = $stmt->fetch();
        if (!$row) json_error('Credenciales incorrectas', 401);
        json_response($row);
    }
}

/**
 * Alta de usuario, con reutilización de registros borrados.
 *
 * EL PROBLEMA QUE RESUELVE:
 * El borrado de usuarios es lógico (`eliminado_en = NOW()`), así que la
 * fila sigue en la tabla ocupando el correo, que tiene índice UNIQUE.
 * Como el listado filtra por `eliminado_en IS NULL`, el correo no
 * aparece en la app y parece libre — pero al intentar crearlo de nuevo
 * MySQL respondía "Duplicate entry" y no había forma de volver a dar de
 * alta a esa persona.
 *
 * LA SOLUCIÓN:
 * Si el correo pertenece a un usuario borrado, se reutiliza esa fila:
 * se sobrescriben todos los datos con los nuevos y se limpia
 * `eliminado_en`. Para la app el resultado es idéntico a un alta.
 *
 * Se conserva el mismo `id`, así que las facturas y comisiones viejas
 * que apuntaban a ese usuario vuelven a quedar enlazadas — que es el
 * comportamiento correcto cuando se re-registra a alguien que ya
 * trabajó en el negocio.
 */
function crear_o_revivir_usuario(array $body): int {
    $correo = trim((string)($body['correo'] ?? ''));

    if ($correo !== '') {
        $stmt = db()->prepare(
            "SELECT id FROM usuarios
             WHERE LOWER(correo) = LOWER(?) AND eliminado_en IS NOT NULL
             LIMIT 1"
        );
        $stmt->execute([$correo]);
        $idBorrado = $stmt->fetchColumn();

        if ($idBorrado !== false) {
            $id = (int)$idBorrado;
            // actualizar() ignora las filas con eliminado_en marcado, así
            // que primero hay que revivirla y después escribir los datos.
            restaurar('usuarios', $id);
            $datos = $body;
            $datos['activo'] = 1;
            actualizar('usuarios', $id, $datos, [
                'nombre', 'cedula', 'correo', 'clave', 'rol',
                'sueldo_base', 'tienda', 'activo', 'gana_comisiones',
            ]);
            return $id;
        }
    }

    // Alta normal.
    return insertar('usuarios', $body, [
        'nombre', 'cedula', 'correo', 'clave', 'rol',
        'sueldo_base', 'tienda', 'activo', 'gana_comisiones',
    ]);
}

despachar_crud($tabla, $columnas, 'id DESC', 'crear_o_revivir_usuario');
