# Despliegue del backend — Tecno Líder

Servidor: `204.48.24.185`,
`/home/sistemasceccato/htdocs/sistemasceccato.com/tecnolider/`
API: `https://sistemasceccato.com/tecnolider/api.php`

---

# Despliegue 07/09/2026 — traslados, cotizaciones e imágenes

**Todo se resuelve del lado del servidor. La app NO hay que recompilarla.**

## Qué se arregla

El error reportado:

```
Error al trasladar: Recurso no encontrado [POST traslado_aplicar]
```

La pantalla de traslados está programada en la app desde hace tiempo y llama
a `traslado_aplicar`, pero ese recurso nunca se registró en `api.php` ni se
subió el archivo. El servidor respondía 404 y la app traducía ese 404 a
"Recurso no encontrado".

Al revisar los 34 recursos que la app llama contra los 39 que el router
tenía registrados aparecieron **siete** en la misma situación:

| Recurso | Pantalla de la app que lo usa |
|---|---|
| `traslado_aplicar` | Traslados entre tiendas → botón *Aplicar* |
| `cotizaciones` | Historial de cotizaciones |
| `cotizacion_guardar` | Nueva cotización → *Guardar y generar PDF* |
| `cotizacion_cobrar` | Historial → *Cobrar* |
| `cotizacion_eliminar` | Historial → *Eliminar* |
| `producto_imagenes` | Nueva cotización (carga las fotos guardadas) |
| `producto_imagen_guardar` | Nueva cotización → elegir foto de un producto |

Y tres recursos ya registrados que respondían 500:

| Recurso | Causa |
|---|---|
| `tasa_bcv` | La tabla no tiene la columna `eliminado_en` que el CRUD genérico da por sentada |
| `stock_disponible` | La vista `v_stock_disponible` nunca se creó |
| `conciliaciones_bdv` | Error fatal de PHP; devolvía un 500 con el cuerpo vacío, sin ninguna pista |

## Archivos

### Nuevos

| Archivo | Qué hace |
|---|---|
| `lib/esquema.php` | Lee qué columnas tiene cada tabla y arma los INSERT solo con las que existen |
| `endpoints/traslado_aplicar.php` | Traslado atómico: mueve el IMEI o el stock y escribe la bitácora en una transacción |
| `endpoints/cotizaciones.php` | Las cuatro operaciones de cotizaciones (listar, guardar, cobrar, eliminar) |
| `endpoints/producto_imagenes.php` | Guarda y lista las fotos de producto usadas en el PDF de cotización |
| `endpoints/reparar_esquema.php` | Chequeo de salud + reparación idempotente del esquema |

### Modificado

| Archivo | Cambio |
|---|---|
| `api.php` | Registra los 8 recursos nuevos; normaliza los errores 4xx; atrapa los errores fatales de PHP |

## Pasos

**1.** Subir por SFTP o el gestor de archivos del panel, respetando las carpetas:

```
tecnolider/api.php                            (reemplaza el actual)
tecnolider/lib/esquema.php                    (nuevo)
tecnolider/endpoints/traslado_aplicar.php     (nuevo)
tecnolider/endpoints/cotizaciones.php         (nuevo)
tecnolider/endpoints/producto_imagenes.php    (nuevo)
tecnolider/endpoints/reparar_esquema.php      (nuevo)
```

Antes de reemplazar `api.php`, guardá una copia:

```bash
cd /home/sistemasceccato/htdocs/sistemasceccato.com/tecnolider
cp api.php _backup_20260907_api.php
```

**2.** Abrir en el navegador, una sola vez:

```
https://sistemasceccato.com/tecnolider/api.php?resource=reparar_esquema
```

Crea las tablas `cotizaciones`, `cotizacion_items` y `producto_imagenes`,
agrega la columna que le falta a `tasa_bcv` y crea la vista
`v_stock_disponible`. **No borra ni modifica ningún dato.** Correrlo de nuevo
no cambia nada: informa que ya estaba todo hecho.

Tiene que responder:

```json
{ "ok": true, "estado": "Backend sano: esquema completo y todos los handlers subidos." }
```

Si `handlers.faltantes` viene con algo, falta subir ese archivo.

**3.** Probar desde la app: Traslados → Nuevo traslado. No hace falta
actualizar ni reinstalar la app.

## Después de subir: revisar `conciliaciones_bdv`

Ese recurso devolvía un 500 con el cuerpo vacío, así que no había forma de
saber qué le pasaba. Con el `api.php` nuevo el error viene con el archivo y
la línea exactos. Abrir:

```
https://sistemasceccato.com/tecnolider/api.php?resource=conciliaciones_bdv
```

y leer el campo `detalles`. La app no usa este recurso todavía, así que no
bloquea nada.

## Qué cambió en `api.php` y por qué

Tres cosas, además del mapa de recursos:

**1. Los errores 4xx ahora llevan `ok: false`.** La app instalada
(`_Api._parse` en `main.dart`) tiene dos comportamientos que hay que
compensar desde el servidor, porque el cliente ya está compilado:

- Ante un **404 o un 409 descarta el mensaje del servidor** y muestra uno
  genérico. Un "No hay suficiente stock en Principal. Disponible: 5" le
  llegaba al usuario como *"Conflicto: el recurso ya existe o hay un
  duplicado"*.
- Ante **cualquier otro 4xx, si el JSON no trae la clave `ok`, no lo toma
  como error**: devuelve el cuerpo como si fuera un resultado válido. Una
  validación fallida se mostraba en pantalla **como si hubiera salido bien**.

Ahora `api.php` agrega `ok: false` a toda respuesta de error y baja los
404/409 a 400. Con eso la app lanza el error con el texto real. Vale para
todos los endpoints, no solo los nuevos. Los 401 y 403 se dejan como están:
sus mensajes genéricos ya son correctos.

**2. Los errores fatales de PHP devuelven JSON.** `safe_run()` atrapa
excepciones, pero no un fatal de verdad (memoria agotada, timeout). En esos
casos PHP cortaba y nginx devolvía un 500 con el cuerpo vacío: la app no
encontraba ningún mensaje y mostraba "Error interno del servidor". Ahora un
`register_shutdown_function` lo convierte en un JSON con el archivo y la
línea.

**3. Se sacó una clave duplicada** (`diagnostico_bd` estaba dos veces en el
mapa).

## Para el próximo endpoint nuevo

Registrar un recurso en `api.php` **y no subir el archivo** produce
exactamente el error de este despliegue, y no se descubre hasta que un
usuario usa la función. Después de cada despliegue, abrir
`?resource=reparar_esquema`: la sección `handlers` lista los recursos
registrados cuyo archivo no está subido.

---

# Despliegue 28/08/2026 (histórico)

### Archivos nuevos

| Archivo | Qué hace |
|---|---|
| `endpoints/cuenta_cobrar_aumentar.php` | Aumenta la deuda de una cuenta; consume primero el saldo a favor |
| `endpoints/cuenta_cobrar_eliminar.php` | Borra la cuenta con sus cuotas, abonos y comprobantes |
| `endpoints/abono_eliminar.php` | Borra un abono puntual |
| `endpoints/comprobantes.php` | Guarda y lista las fotos/PDF adjuntos |
| `lib/comprobantes.php` | Helpers de la tabla `comprobantes` |

### Archivos modificados

| Archivo | Cambio |
|---|---|
| `api.php` | Registra los 5 recursos nuevos en el mapa de endpoints |
| `endpoints/usuarios.php` | Revive el usuario borrado en vez de fallar por correo duplicado, y agrega `gana_comisiones` a la lista blanca |
| `endpoints/cuentas_cobrar.php` | Agrega `saldo_favor` a la lista blanca |

Los tres archivos originales quedaron en `_backup_20260828/`.

### Dos bugs extra que aparecieron y se corrigieron

- **`gana_comisiones` nunca se guardaba.** No estaba en la lista blanca de
  columnas de `usuarios.php`, así que `filtrar_columnas()` lo descartaba en
  cada alta y edición.
- **`saldo_favor` se borraba en cada guardado** de una cuenta por cobrar, por
  el mismo motivo en `cuentas_cobrar.php`.

---

# App — versionado y OTA

La versión sincronizada es `1.0.12` (`kAppVersion` y `pubspec.yaml`, que va
`1.0.12+12` — el `+12` es el versionCode de Android y también tiene que subir).

## Firma de Android — LO MÁS IMPORTANTE DE ESTA SECCIÓN

Hasta la 1.0.11 el APK se firmaba con el **keystore de depuración de la
máquina que compilaba** (`signingConfig = signingConfigs.getByName("debug")`).
Como ese keystore es distinto en cada equipo y en cada agente de CI, cada
compilación producía una firma distinta y **Android rechazaba instalar la
actualización encima** ("aplicación no instalada"). Se comprobó comparando
certificados:

| APK | SHA-256 del certificado |
|---|---|
| 1.0.10 publicado | `b5270982bb55…4d8872` |
| 1.0.12 con la firma vieja | `cfbf79bcc39f…f65607` |

Desde la 1.0.12 el proyecto tiene **keystore de release propio**:

- `android/tecnolider-release.jks` — el keystore (RSA 4096, válido 30 años).
- `android/key.properties` — alias y contraseñas.
- Los dos están en `.gitignore` y **no se suben al repositorio**.

⚠️ **Hay que respaldarlos fuera de esta PC** (gestor de contraseñas o disco
cifrado). Si se pierde el keystore no se puede volver a firmar igual, y la
única salida vuelve a ser desinstalar y reinstalar a mano en cada equipo.

Si `key.properties` no existe, el build cae a la firma de depuración y
produce un APK que **no sirve para actualizar**: sirve solo para pruebas.

### Reinstalación manual, por única vez (Android)

Los teléfonos que tienen la 1.0.10 están firmados con la clave vieja, así que
la 1.0.12 **no se les instala encima**. Una sola vez, en cada teléfono:
desinstalar Tecno Líder e instalar el APK 1.0.12. No se pierde información —
todos los datos viven en el servidor. De ahí en adelante el OTA se sostiene
solo, porque la firma ya no vuelve a cambiar.

### Compilar

```bash
flutter clean && flutter pub get
flutter build apk --release        # Android
flutter build windows --release    # Windows
```

### Subir primero los archivos a `/tecnolider/updates/`

| Archivo | De dónde sale |
|---|---|
| `tecnolider-1.0.12.apk` | `build/app/outputs/flutter-apk/app-release.apk`, renombrado |
| `tecnolider-windows-1.0.12.zip` | zip del contenido de `build/windows/x64/runner/Release/` |

⚠️ Al comprimir Windows, **excluir los `.zip`**: la carpeta `Release/` suele
quedar con el zip del release anterior adentro y se cuela en el nuevo (paso
de 17 MB a 34 MB sin que nadie lo note).

```powershell
$items = Get-ChildItem "build\windows\x64\runner\Release" -Exclude *.zip
Compress-Archive -Path $items -DestinationPath "tecnolider-windows-1.0.12.zip" -Force
```

El `.exe` y la carpeta `data/` tienen que quedar en la **raíz** del zip.

### Recién DESPUÉS, subir el `version.json`

⚠️ **En este orden.** Si se sube el `version.json` antes que los archivos,
todos los equipos ven que hay una actualización y la descarga falla.

## Por qué el OTA de Android nunca funcionó

Eran tres cosas a la vez, y cada una sola ya alcanzaba para romperlo:

1. **Nunca se subió ningún APK.** En `updates/` solo había ZIPs de Windows. Y
   el servidor responde `HTTP 200` con una página de 15 bytes
   (`Hello World :-)`) para cualquier archivo que no existe, en vez de un
   404 — así que la app descargaba eso *creyendo que era el APK*. Desde
   1.0.9 verifica la firma del archivo.
2. **Faltaba el permiso `REQUEST_INSTALL_PACKAGES`** en el AndroidManifest.
   Sin él, Android descarta el instalador sin mostrar nada.
3. **El `version.json` decía `1.0.8`**, la misma versión instalada.
4. **La firma cambiaba en cada compilación** (ver arriba). Resuelto en 1.0.12
   con el keystore de release propio.

## Lo que pasó con la 1.0.11

La 1.0.11 se compiló y su zip de Windows se subió, pero **nunca se publicó el
`version.json`**: siguió anunciando `1.0.10`. Ningún cliente la recibió, ni en
Windows ni en Android (su APK tampoco se había subido). Por eso la 1.0.12 sale
directo desde la 1.0.10 instalada. Antes de dar por cerrado un release,
comprobar siempre:

```bash
curl https://sistemasceccato.com/tecnolider/updates/version.json
curl -o /dev/null -w "%{http_code} %{size_download}
"      https://sistemasceccato.com/tecnolider/updates/tecnolider-1.0.12.apk
```

El servidor responde `HTTP 200` con 15 bytes (`Hello World :-)`) para los
archivos que no existen, así que **un 200 no alcanza**: hay que mirar el
tamaño.

En Windows el OTA sí venía funcionando.

## Primera instalación manual en Android (solo esa vez)

Los teléfonos con la versión vieja necesitan **una** instalación manual del
APK 1.0.9, porque la versión instalada no pide el permiso de instalación. De
1.0.9 en adelante el OTA se sostiene solo. Android va a pedir una vez
*"Permitir instalar aplicaciones desconocidas"*: hay que aceptarlo.
