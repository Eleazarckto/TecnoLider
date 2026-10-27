# Bitácora de TecnoLider

Registro de lo que se fue trabajando sesión por sesión. **Lo más reciente va
arriba.** Cada entrada dice qué se hizo, por qué se decidió así y qué quedó
pendiente. Fechas absolutas. No se repite lo que el código ya dice.

---

## 2026-10-27 · Backend desplegado y 1.0.18 publicada (orden del dueño)

**Orden del dueño:** «sube todas las actualizaciones pendientes»: solo
TecnoLider, desplegar el backend (era la orden que pedía la entrada del
16/10 10:40) y publicar la 1.0.18 (el dueño quitó `PUBLICACION_BLOQUEADA`).
Luego: «sube a github todo».

- `desplegar.sh tecnolider`: 50 `.php` compilan, respaldo
  `/root/respaldos_despliegue/tecnolider_20261027_132903.tar.gz`, API sana.
- `?resource=reparar_esquema`: creó `listas_precios.lista_base_id`,
  `listas_precios.vista_bs` y `facturas.direccion`; 0 errores, 50 handlers.
- Login de los 11 usuarios activos contra producción: 11 con HTTP 200.
- Suite Flutter: 338 pruebas pasan. APK firmado con la llave de la flota
  (40083ad5…). Notas de version.json con lo del 19 y 23/10 y el panel;
  `sha256`/`tamano` de cada paquete. Instaladores en `updates/` (HTTP 200).
- Los interruptores siguen apagados (`precios_auto_activo`,
  `factura_cuadre_servidor`): publicar no los enciende.

---

## 2026-10-23 · Dirección del cliente en la factura + listas en Bs con vista BCV (sin desplegar)

**Órdenes del dueño:** «que en la facturación le pida la dirección del
cliente» y «que las listas de bolívares tengan la opción de mostrar solo el
precio BCV deseado usando porcentaje (100 $ + 10 % = BCV 110 $) o la opción
de que sí muestre también el equivalente a Bs».

**Dirección:** campo «DIRECCIÓN» en la factura (después del teléfono). Una
factura NUEVA no se guarda sin ella (mínimo 3 letras); una ya emitida se
edita sin exigirla. Se guarda en `facturas.direccion` (columna nueva,
`fc_columnas_nuevas`, la crea `reparar_esquema`), va en el borrador, sale en
el ticket y en las dos facturas A4, y se recuerda por cédula (al escribir la
cédula de un cliente que ya compró se rellena). La 1.0.17 no la manda y no la
borra (el PUT solo toca lo que llega).

**Listas en Bs — «Mostrar precios»** (Editar lista y Nueva lista, solo en
Bs): `bs` como siempre, `bcv` solo el precio BCV en $, `bcv_bs` el BCV y
debajo su equivalente en Bs. **Decisión técnica:** lo guardado sigue en Bs
(base × (1 + %) × tasa, como desde el 19/10) y el precio BCV es lo guardado ÷
la tasa de la lista. Así la 1.0.17, el servidor (modo costo) y el cambio de
tasa no cambian nada. Con «sin decimales hacia arriba» se vuelve al dólar
entero (4.023 Bs → 110 $). En vista BCV lo que se escribe a mano (celdas,
diálogo de precio, «Nuevo valor» del editor masivo) es en $ BCV y se guarda
× tasa. Respetan la vista: la pantalla de la lista, el PDF/imagen, la
consulta rápida, la tarjeta de la lista y el editor masivo. El cuadre de la
factura toma el precio BCV de una lista llamada «BCV»: si esa lista es en Bs
con vista BCV, ahora lee el $ (antes habría leído los Bs como dólares).
Columna `listas_precios.vista_bs` (VARCHAR, 'bs' por defecto) en
`reparar_esquema`, lista blanca del endpoint y `PL_CAMPOS_NUEVOS`.

**Pruebas:** `test/listas_bs_vista_bcv_test.dart` (10, con el ejemplo del
dueño), `precios_listas_test.php` 138 → 142, `factura_cuadre_test.php` 80 →
82. Suite Flutter: 338, 0 errores de análisis.
**Sin probar en la app corriendo** (solo pruebas automáticas).
**Pendiente:** desplegar el backend y correr `?resource=reparar_esquema`
(crea `facturas.direccion` y `listas_precios.vista_bs`); va con la 1.0.18,
que sigue bloqueada (`PUBLICACION_BLOQUEADA`).

---

## 2026-10-19 · Listas en Bs desde la lista en divisas + reporte de IMEIs por tienda, marca y modelo (sin desplegar)

**Órdenes del dueño:** «en las listas de precios en bolívares tome el precio de
las listas en divisas y sea a esa lista la que se le aumente el porcentaje» y
«los reportes de IMEI por tienda, modelo y marca».

**Decisiones del dueño (preguntadas en la sesión):**
- Cada lista en Bs **elige** su lista base en divisas («Tomar precios de» en
  Editar/Nueva lista). Sin elegir, la lista sigue como siempre.
- Precio en Bs = precio del producto en la lista base (primera columna) ×
  (1 + % adicional de la lista en Bs) × tasa.
- Producto que no está en la base (o con precio 0 ahí): precio de venta × % × tasa.
- Se recalcula ya: al elegir la base la lista entera se pone al día
  (respetando los ✎), y después sigue sola a su base (al abrirla, al guardar
  la lista en divisas, al cambiar la tasa y el precio de un producto).
- Reporte de IMEIs: filtros de tienda, marca y modelo antes de generar +
  totales por tienda, marca y modelo (disponibles y vendidos).

**En código:** `lib/listas_bs_desde_divisas.dart` (base, `seguirListaBase`,
`actualizarListasBsDeBase`, selector), `ListaPrecio.listaBaseId` y
`precioPorDefecto`; columna `listas_precios.lista_base_id` (INT, 0 = ninguna)
en `reparar_esquema.php`, lista blanca del endpoint y `PL_CAMPOS_NUEVOS` (la
1.0.17 no la manda y no la borra). En modo costo el servidor hace la misma
cuenta (`plBaseDeBs`/`plPrecioEnBase` en `backend/lib/precios_listas.php`):
ahora la lista Bs suma SU % sobre el precio de la base (con 0 % da lo de antes).
`migrarMarcasManuales` no toca listas con base. Reporte: `lib/reporte_imei.dart`,
`generarReporteIMEI(filtro:)`, hoja «Por tienda, marca y modelo» en el Excel;
tienda = `ubicacion` del IMEI (vacía = «Sin asignar»), modelo = modelo del
producto o, si no tiene, el nombre del equipo. El resumen del visor ahora se
desplaza (con muchos modelos tapaba la tabla).
**Pruebas:** `test/listas_bs_desde_divisas_test.dart` (11),
`test/reporte_imei_test.dart` (7), `precios_listas_test.php` 124 → 138.
Suite: 328 pruebas, 0 errores de análisis.

**Sin probar en la app corriendo** (solo pruebas automáticas): el diálogo con
el selector y los filtros del reporte. No se pudo leer la base de producción
para ver qué tienen hoy `modelo` y `ubicacion` de los IMEIs (permiso denegado).
**Pendiente:** desplegar el backend y correr `?resource=reparar_esquema`
(crea `lista_base_id`) — el backend de producción está en el respaldo del
16/10 por orden del dueño; va con la 1.0.18, que sigue bloqueada.

## 2026-10-16 · Panel Corporativo de Brizuela (rama `panel`, sin publicar)

**Orden del dueño:** «agrega el panel corporativo tal cual lo tiene Brizuela», sin CRM.

- Regla (en código: `debeEntrarAlPanelCorporativo` en `lib/main.dart`, ruteo en `_login`):
  Dueño, Gerente, Administrador y Maestro entran PRIMERO al panel y desde ahí
  eligen tienda; los demás roles siguen eligiendo tienda y entran a vender.
- `lib/panel_corporativo.dart` (part de main): barra, saludo, 5 indicadores,
  «Tus tiendas» en Ciudad (`lib/ciudad/vista_ciudad.dart`, copia de Brizuela) o
  Tarjetas, y la grilla de Administración. Tocar una tienda abre
  `VentasPrincipal(desdePanel: true)`; el botón de la barra (cuadrícula) vuelve
  al panel. En el menú de ventas hay «Panel Corporativo» para los roles altos.
- Solo usa lo que el servidor de producción (1.0.17) ya tiene: GET `facturas`
  (las 1000 más recientes; el mes se filtra en la app) y GET `traslados`, más el
  catálogo cargado al iniciar sesión. Abrir el panel no escribe nada.
- Cifras con las reglas de Tecno Líder: divisas con `totalesPagosPorMoneda`
  (tasa de cada pago), ganancia con `precioRealVentaEnFactura` (sacada del
  Reporte por Vendedor para que las dos pantallas den lo mismo).
- Omitido por no existir en Tecno Líder: asistente (botón flotante), CRM y los
  módulos Activación, Líneas, Movimientos y Financiamiento. «Almacén / Inventario»
  abre `VentanaInventario` y «Clientes» `VentanaHistorialClientes`.
- Distinto de Brizuela a propósito: módulos con alto fijo y una columna en
  teléfono (la proporción de Brizuela desbordaba a 400 px de ancho).
- Prueba: `test/panel_corporativo_test.dart`. Captura: `panel_corporativo*.png`.

## 2026-10-16 10:40 · Backend devuelto al respaldo de la mañana (orden del dueño)

- El dueño reportó que su cliente no podía iniciar sesión y ordenó arreglarlo ya.
  Se restauró `tecnolider_20261016_095450.tar.gz` (archivos idénticos a antes del
  despliegue; el estado previo quedó en `tecnolider_antes_rollback_*.tar.gz`).
- Antes y después del rollback los 10 usuarios activos inician sesión (HTTP 200);
  `usuarios.php` nunca cambió. Las columnas nuevas de la base quedan (aditivas).
- La app 1.0.18 necesita el backend nuevo: NO volver a desplegarlo sin orden del dueño.

## 2026-10-16 · Backend desplegado (inerte); app 1.0.18 sin publicar

- Con permiso del dueño: `desplegar.sh tecnolider` (respaldo
  `/root/respaldos_despliegue/tecnolider_20261016_095450.tar.gz`) y
  `?resource=reparar_esquema`: 22 columnas/tablas nuevas, 0 errores, 50 handlers.
- Verificado en producción: `precios_listas_sincronizar.php --prueba` = 0 listas
  en modo costo, 0 precios cambiarían; interruptores en 0; cuadre de facturas
  en el servidor apagado. La 1.0.17 da las mismas respuestas (79 comprobaciones).
- `endpoints/conciliaciones_bdv.php` YA estaba roto en producción (`$body[]` en
  la línea 24: no compila, responde 500). No se tocó: quedó excluido en
  `sitios.conf` para que la compuerta de sintaxis no frene los despliegues.
  Arreglo propuesto: `$body['monto_bs']`. Lo decide el dueño.
- `sitios.conf` de tecnolider ahora excluye `tests` y `herramientas_fichas`.
- App 1.0.18 (pubspec, kAppVersion y backend/version.json) lista para que el
  dueño la compile. NO publicada: `PUBLICACION_BLOQUEADA` sigue puesto.
- Arreglado (venía de la 1.0.17): el diálogo «Registrar Pago» liberaba los
  campos de Pago Móvil antes de terminar de cerrarse (error solo en depuración).
  Prueba: `test/dialogo_pago_movil_test.dart`. Verificación final: 305 pruebas,
  0 errores de análisis. Notas: `Downloads/TecnoLider-1.0.18-notas-de-la-version.pdf`.

## 2026-10-16 · Listas de precios de Brizuela (rama `listas`, sin desplegar)

**Decisiones del dueño (escritas en código, aquí y en docs/LISTAS_DE_PRECIOS_TL.md):**
los precios automáticos desde el costo se incluyen **apagados**; cada lista
sigue a mano hasta que la administración la pase a «desde el costo», y antes
hay un ensayo que dice cuántos precios cambian. Al desplegar el backend y al
instalar la app nueva **ningún precio cambia**; la 1.0.17 sigue funcionando
contra el backend nuevo. Sin CRM, chips, líneas ni activación.
**En código:** columna `modo_precios` nace en 'manual'; interruptores
`precios_auto_activo`, `listas_auto_agregar`, `precio_venta_desde_lista` en 0
(ausentes = 0); los enganches salen si el interruptor no vale 1 y solo tocan
listas en modo costo; un PUT normal nunca cambia `modo_precios`; el PUT
conserva `es_manual` y los campos nuevos que la 1.0.17 no manda. Pruebas:
`backend/tests/precios_listas_test.php` (124) y `test/listas_precios_motor_test.dart`.

## 2026-10-16 · Mejoras de Brizuela traídas a TecnoLider (en curso, sin publicar)

**Pedido del dueño:** agregar a TecnoLider las mejoras de Brizuela en listas
de precios y facturación, el estilo visual nuevo (con logo y colores de
TecnoLider), Reportes por rol (Brizuela 1.0.71), el actualizador para Xiaomi
(1.0.72) y las fichas técnicas. **Sin CRM**, sin tasación, KPI ni vueltos.
Más un PDF de notas de la versión como el de Brizuela 1.0.70.

**Regla del dueño (escrita en código, CLAUDE.md y aquí):** la versión nueva
**no se publica** al cliente hasta que el cliente confirme; primero el dueño
la compila y la prueba. En código: `desplegar.sh --publicar-version` se niega
mientras exista `TecnoLider-main/PUBLICACION_BLOQUEADA`. Solo el dueño lo borra.

**Decisiones del dueño (2026-10-16):**
- Facturación **mixta**: se conserva contado/financiado por producto (F/D); de
  Brizuela se trae el cuadre obligatorio, moneda y tasa por pago, vuelto en
  efectivo en la factura, FPB creado por el servidor, búsqueda en todo el
  historial e idempotencia. Sin modalidad por factura.
- Contado en Bs **como hoy en TecnoLider**: precio BCV × tasa BCV.
- **Nada de chips, líneas ni activación.** Sin DPF ni comisión por %.
- Listas: precios desde el costo, % especial por tipo, redondeo hacia arriba y
  % oculto **incluidos y apagados**; cada lista sigue igual hasta que la
  administración la active, con ensayo previo.
- Estilo del Panel de Brizuela con **logo y colores de TecnoLider**.

**Origen:** la carpeta `BrizuelaApp-main/prueba` estaba en la 1.0.69; la 1.0.70
a 1.0.72 solo estaban en GitHub (`origin/main`, b3d93db). Se trabajó sobre esa.

### Facturación (rama `facturacion`)

**Reglas del dueño (en código: `lib/factura_cuadre.dart` y
`backend/lib/factura_cuadre.php`):**

1. **Mixto.** Se conserva el contado/financiado POR PRODUCTO (chip F/D): una
   factura puede llevar un teléfono por Krece y un forro de contado. No se
   trae la modalidad por factura de Brizuela. Objetivo del cuadre =
   Σ contado de las líneas de contado + Σ inicial de las financiadas.
2. **Tasa como hoy en TecnoLíder:** contado pagado en Bs = precio BCV (lista
   o columna «BCV») × tasa BCV; financiadoras a BCV. NO la «tasa de divisas».
3. **Fuera:** chips/líneas/activación, modalidad Chip, DPF, comisión por %,
   vuelto por Pago Móvil/BDV, ventana de Vueltos, CRM.
4. **Activación gradual:** lo que cambia el comportamiento del servidor
   (rechazar con 422 la factura que no cuadra y crear la deuda FPB) queda
   tras `configuracion.factura_cuadre_servidor` = '1' (por defecto '0') y solo
   para la app nueva (la que manda `cuadre`). La 1.0.17 factura EXACTAMENTE
   igual: lo prueba `backend/tests/endpoint/facturas_endpoint_test.php`
   (mismas respuestas y filas que el backend viejo, llave 0 y 1).

**Qué se hizo:** cuadre obligatorio sin «Continuar» en facturas nuevas;
inicial aprobada por línea financiada; cada pago con moneda y tasa (nunca $ y
Bs crudos); vuelto solo en efectivo/divisas como pago negativo `es_vuelto`;
FPB sale con lo que pague el cliente, deuda propuesta = total − pagado y
editable, la crea el servidor con `factura_id` (idempotente, se anula al
borrar la factura si no tiene abonos) o, con la llave apagada, la app (ahora
con `factura_id` y avisando si falla); factura impresa con solo lo pagado,
vuelto rotulado y la tasa del cobro; búsqueda en todo el historial
(`GET facturas?q=`); `clave_idempotencia` para no duplicar facturas al
reintentar. Esquema aditivo en `reparar_esquema.php` (bloque propio).

**Pendiente de decidir (dueño):** al EDITAR una factura ya emitida el cuadre
avisa con «Continuar» (los precios del catálogo pueden haber cambiado desde
la venta); el servidor tampoco valida el PUT. Rechazar la app vieja con la
llave encendida (como Brizuela) tampoco se hizo: la orden fue validar solo a
la app nueva.
