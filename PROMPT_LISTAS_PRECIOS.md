# Módulo "Listas de Precios" — Análisis y prompt de implementación

Documento en dos partes:

1. **Análisis** del módulo tal como está implementado hoy en Tecno Líder
   (Flutter + API PHP/MySQL): modelo de datos, reglas de negocio, contrato de
   API, sincronización y puntos de integración.
2. **Prompt listo para pegar** en otro sistema (agente de IA o desarrollador),
   escrito de forma independiente del lenguaje y del framework.

---

# PARTE 1 — Análisis del sistema actual

## 1.1 Qué resuelve el módulo

Una **lista de precios** es una tabla de precios derivada del catálogo, con:

- un **subconjunto de productos** (filtrado por categoría y marca),
- una o varias **columnas de precio** por producto (Contado, Mayorista, Detal…),
  cada una con su propia **fórmula de cálculo** o edición manual,
- una **moneda** (USD o Bs con tasa del día),
- opcionalmente un **modo financiamiento** (financiadora, % de inicial, número
  de cuotas, % de recargo, comisión) con condiciones que pueden variar por
  producto.

Se usa para: publicar precios al equipo de ventas, exportar/compartir
(PNG y PDF por WhatsApp), alimentar la **Consulta Rápida** de precios y calcular
el precio correcto en **ventas financiadas** (Cashea / Krece / Weppa).

## 1.2 Modelo de datos (código actual: `lib/main.dart`)

```
ListaPrecio                        (línea ~6562)
├─ id, nombre, fechaCreacion
├─ categoria        "Todos" | <categoría>     ← filtro de auto-población
├─ marcaFiltro      "Todas" | <marca>         ← filtro de auto-población
├─ esEnBolivares, tasaDelDia
├─ porcentajeAdicional          % que se suma al precio de venta del catálogo
├─ esFinanciamiento, financiadora
├─ porcentajeInicial, numeroCuotas, tieneCuotas
├─ porcentajeRecargoCuotas      % sobre el saldo antes de dividir en cuotas
├─ porcentajeComisionWeppa      solo aplica a la financiadora Weppa
├─ columnas: List<ColumnaPrecio>  { nombre, formula }
└─ items:    List<ItemListaPrecio>

ItemListaPrecio                    (línea ~6514)
├─ producto (referencia por código al catálogo)
├─ preciosPorColumna: Map<nombreColumna, precio>
├─ stockDisponible                 (informativo; IMEI o stock manual)
├─ inicialManual?, cuotaManual?    override de MONTO exacto
└─ pctInicialOverride?, cuotasOverride?   override de CONDICIONES por producto

FormulaColumna                     (línea ~6090)
├─ modo: manual | porcentaje | monto | multiplicador | expresion
├─ origen: venta | costo | base | columna   (+ columnaOrigen)
├─ valor, expresion
├─ redondeo: ninguno|dos|entero|arriba|abajo|psicologico|multiplo (+multiplo)
├─ aplicarTasa, aplicarAdicional
└─ auto        (si true, se recalcula sola; si false, solo bajo demanda)
```

## 1.3 Reglas de negocio clave

**Cálculo del precio base al poblar** (el orden importa para el redondeo):

```
factorAdicional  = 1 + porcentajeAdicional/100
precioUsdMargen  = redondear2(producto.precioVenta * factorAdicional)
precioBase       = esEnBolivares ? redondear2(precioUsdMargen * tasa)
                                 : precioUsdMargen
```
Se redondea **en dos pasos** (USD y luego Bs) para no arrastrar decimales.

**Cálculo de una columna con fórmula** (`calcularColumna`):

```
1. origen  ← venta | costo | base(= precio de la 1ª columna) | otra columna
             (una columna NUNCA puede alimentarse de sí misma → null)
2. bruto   ← según modo:  origen*(1+valor/100) | origen+valor | origen*valor
             o el resultado del evaluador de expresiones
3. si aplicarAdicional → bruto *= (1 + porcentajeAdicional/100)
4. si aplicarTasa      → bruto *= tasaEfectiva
5. redondeo configurado
```
`aplicarFormulas()` recorre las columnas **en orden**, de modo que una columna
que se apoya en otra ya calculada use el valor nuevo. Devuelve cuántos precios
cambiaron.

**Financiamiento** (todo pasa por estos cuatro métodos, para que la pantalla,
el PDF, la imagen, la Consulta Rápida y los reportes coincidan):

```
pctInicialDe(item) = item.pctInicialOverride ?? lista.porcentajeInicial
cuotasDe(item)     = item.cuotasOverride     ?? lista.numeroCuotas
inicialDe(item, base) = item.inicialManual ?? redondear2(base * pct/100)
cuotaDe(item, base)   = item.cuotaManual ?? (
    !tieneCuotas ? 0
                 : redondear2((base - inicial) * (1+recargo/100) / cuotas))
```
`cuotasUniformes` devuelve `null` cuando los productos tienen cuotas distintas,
para que los encabezados no anuncien un número único que sería falso.

**Evaluador de expresiones** (`EvaluadorFormula`, ~línea 6236): intérprete
propio, sin dependencias. Soporta números con `,` o `.`, paréntesis,
`+ − × / ^ mod`, comparaciones `> < >= <= = <>`, conectores `y` / `o`,
funciones `redondear(x;dec) techo piso abs min max pot raiz si(cond;a;b)`,
variables `costo venta base tasa adicional inicial cuotas recargo stock` y
referencias a otras columnas con `[Nombre]`. Separador de argumentos `;` o `,`.
Devuelve `null` ante cualquier error (nunca lanza hacia la UI).

**Auto-población inteligente** (`_poblarLista`): al pulsar "Actualizar",

1. productos nuevos del catálogo → se agregan con precio calculado,
2. productos ya presentes → **se preservan sus precios manuales**, solo se
   actualiza el stock y se rellenan las columnas nuevas,
3. productos que ya no están en el catálogo → se eliminan,
4. se excluyen los subproductos/variantes (solo productos padre); el stock del
   padre suma el de sus variantes (IMEIs o stock manual según categoría).

**Tasa desactualizada**: al abrir una lista en Bs cuya `tasaDelDia` difiere de
la del sistema, se detecta qué precios seguían la fórmula automática
(tolerancia de 1 Bs) y solo esos se recalculan; los editados a mano se respetan.

**Sólo productos con stock**: el stock de cada item se calcula EN VIVO
(`stockVivoDeItem`, índice `_IndiceStockListas`) sumando todas las tiendas
(una fila de `productos` por tienda) y las variantes: IMEIs no vendidos para
categorías con IMEI, `stockManual` para el resto. Al poblar no se agregan
productos nuevos agotados; los que ya estaban y se agotan se CONSERVAN (con sus
precios) pero se ocultan en pantalla (el admin puede mostrarlos), en el PDF, en
la imagen y en la Consulta Rápida (`ListaPrecio.itemsConStock`).

**Cambio de precio en el inventario**: `actualizarListasPorCambioDePrecio`
(llamado al guardar `FormularioProducto`) recalcula el producto en todas las
listas y hace PUT de las afectadas: columnas con función automática siempre;
columnas manuales sólo si su valor era el "por defecto" calculado con el precio
viejo; inicial/cuota fijas sólo si coincidían con el cálculo viejo.

**Cambio de % inicial / cuotas / recargo de la lista**: inicial y cuota se
recalculan solas; si hay montos escritos a mano (`inicialManual`/`cuotaManual`)
con las condiciones viejas, se pregunta si recalcularlos
(`contarMontosFijosAfectados` / `limpiarMontosFijosAfectados`).

**Consulta Rápida**: en listas con varias columnas se elige UNA columna por
lista (guardado por equipo en `consulta_rapida_columna_por_lista`); se
pregunta al abrir si falta la elección.

**Exportar PDF / imagen**: ambos salen del mismo documento `pdf` con TODAS las
columnas de precio y, en financiamiento, inicial (monto y %), número de cuotas y
monto de la cuota. La imagen es una página de alto variable rasterizada con
`Printing.raster` (~230 ppp). En escritorio se guarda con "Guardar como" (o en
Descargas) y se abre; en el teléfono se comparte.

## 1.4 Contrato de API

Recurso REST único `listas_precios` (`GET` listar, `POST` crear, `PUT ?id=`
actualizar, `DELETE ?id=` borrar). El payload lleva **arrays anidados** que el
backend descompone en tablas relacionales:

```jsonc
{
  "id": 80, "nombre": "KRECE", "fecha_creacion": "2026-09-10",
  "categoria": "Todos", "marca_filtro": "Todas",
  "es_en_bolivares": 0, "tasa_del_dia": 36.5,
  "porcentaje_adicional": 10.0,
  "es_financiamiento": 1, "financiadora": "Krece",
  "porcentaje_inicial": 40.0, "numero_cuotas": 6, "tiene_cuotas": 1,
  "porcentaje_recargo_cuotas": 20.0, "porcentaje_comision_weppa": 0.0,
  "columnas": [ { "nombre": "Contado", "formula": "{...json...}" } ],
  "items": [ {
      "producto_codigo": "A123", "stock_disponible": 4,
      "valores": [ { "columna_nombre": "Contado", "precio": 199.99 } ]
  } ]
}
```

**Truco de compatibilidad (documentar, pero NO replicar si el esquema nuevo se
puede diseñar bien):** como el backend original solo guardaba el *nombre* de la
columna, la configuración extra viaja disfrazada de columnas virtuales:

- `__fx__<base64url(json)>` → fórmula de una columna real,
- `__inicial_manual__`, `__cuota_manual__`, `__pct_inicial__`, `__n_cuotas__`
  → overrides por ítem, guardados como si fueran precios.

Al leer (`ListaPrecio.fromMap`) se decodifican, se aplican a su destino y se
descartan; nunca se muestran. Cualquier nombre con forma `__x__` se ignora.
En un sistema nuevo, esto debe ser **columnas reales de la base de datos**.

## 1.5 Sincronización multi-dispositivo

- **Listado**: polling cada **10 s**; hash profundo del contenido (id, nombre,
  todos los %, financiadora, tasa, y cada `producto_codigo` con sus
  `columna=precio`) para evitar `setState` innecesarios.
- **Detalle**: polling cada **15 s**, con tres candados para no pisar el trabajo
  del usuario: no sincroniza si está guardando, si hay un debounce pendiente, o
  si el usuario editó hace menos de **8 s**.
- **Escritura**: debounce de **600 ms** al editar precios; si la lista aún no
  tiene `id`, el primer guardado hace `POST` y adopta el id devuelto.
- **Columnas locales**: si el servidor devuelve menos columnas que las locales
  (aún no guardó la recién creada), se conservan las locales y se reenvían.
- **Caché local de fórmulas** en `SharedPreferences`
  (`formulas_columnas_<id>`), que repone la fórmula si el servidor la perdió.

## 1.6 Permisos

`Administrador`, `Dueño` y `Maestro` crean/editan/eliminan listas, columnas y
precios. El resto de los roles las ve en **modo lectura**. Elegir qué listas
aparecen en la Consulta Rápida es exclusivo del dueño.

## 1.7 Integraciones (consumidores de las listas)

| Consumidor | Uso |
|---|---|
| **Consulta Rápida** | Por producto, muestra `[lista, columna, precio, moneda, inicial %, cuotas]` de las listas marcadas como visibles. La selección se guarda por `id:<n>` (y también por nombre normalizado, por compatibilidad con versiones viejas de la app). |
| **Venta financiada** | Al elegir financiadora, se ofrecen las listas cuya `financiadora` coincide; si hay una sola se autoselecciona. Sin lista se muestra una advertencia. |
| **Reportes / comisiones** | El precio de venta financiada se busca por nombre de lista exacto y, si falla, por financiadora; se toma la primera columna no virtual. |
| **Panel admin** | Pestaña "Financiadoras" derivada de las listas con `esFinanciamiento`. |
| **Exportación** | PNG (render de un `RepaintBoundary` a 3× y `share`) y PDF (tabla agrupada por marca, `Printing.sharePdf`). |

## 1.8 Deudas técnicas a NO heredar

1. Las columnas virtuales `__fx__` / `__x__` son un parche por un esquema que no
   se podía tocar. Con base de datos nueva, usar columnas reales.
2. Todo el módulo vive dentro de un `main.dart` de 56 000 líneas. Separar en
   `modelo / servicio / repositorio / pantallas` desde el inicio.
3. El polling por hash completo transfiere la lista entera cada 10–15 s. Con un
   campo `actualizado_en` (o ETag) basta con pedir la cabecera.
4. La detección de "precio automático" por tolerancia de 1 Bs es heurística.
   Con una bandera `es_manual` por celda, el problema desaparece.
5. No hay historial de cambios de precio ni vigencias por fecha.

---

# PARTE 2 — Prompt para implementar el módulo en otro sistema

> Copiar todo lo que sigue y pegarlo en el agente/desarrollador que trabaje
> sobre el sistema destino. Ajustar solo la sección **CONTEXTO DEL SISTEMA
> DESTINO**.

---

## PROMPT

Necesito que implementes un módulo de **Listas de Precios** completo en este
sistema. A continuación tienes la especificación funcional, el modelo de datos,
las fórmulas exactas y los criterios de aceptación. Sigue las convenciones, el
stack y la arquitectura que ya existen en este proyecto: no introduzcas
librerías nuevas si el proyecto ya tiene una equivalente.

### CONTEXTO DEL SISTEMA DESTINO *(completar antes de usar el prompt)*

- Stack / framework:
- Base de datos y forma de crear migraciones:
- Cómo se define un endpoint / servicio nuevo:
- Módulo de catálogo de productos existente (tabla, campos `codigo`, `nombre`,
  `marca`, `categoria`, `precio_costo`, `precio_venta`, stock):
- Sistema de roles y cómo se consulta el rol del usuario en sesión:
- Configuración global de tasa de cambio (si existe):

### 1. Alcance

Un **catálogo de listas de precios**. Cada lista es una tabla derivada del
catálogo de productos, con una o más columnas de precio por producto. Las listas
sirven para publicar precios al equipo comercial, exportarlas y alimentar las
ventas financiadas.

### 2. Modelo de datos

**Lista de precios**

| Campo | Tipo | Descripción |
|---|---|---|
| `id` | pk | |
| `nombre` | texto | |
| `fecha_creacion` | fecha | |
| `categoria` | texto | `"Todos"` o una categoría — filtro de auto-población |
| `marca_filtro` | texto | `"Todas"` o una marca — filtro de auto-población |
| `es_moneda_local` | bool | si los precios van convertidos a moneda local |
| `tasa_del_dia` | decimal | tasa usada por la lista |
| `porcentaje_adicional` | decimal | margen % sobre el precio de venta del catálogo |
| `es_financiamiento` | bool | activa el modo financiamiento |
| `financiadora` | texto? | nombre de la financiadora |
| `porcentaje_inicial` | decimal | % de inicial por defecto |
| `numero_cuotas` | entero | cuotas por defecto (default 12) |
| `tiene_cuotas` | bool | si la financiadora divide el saldo en cuotas (default **true**) |
| `porcentaje_recargo_cuotas` | decimal | % sobre el saldo antes de dividir |
| `porcentaje_comision` | decimal | % de comisión del vendedor |
| `actualizado_en` | timestamp | para sincronización incremental |

**Columna de precio** (1 lista → N columnas, con orden explícito)

`id`, `lista_id`, `nombre`, `orden`, y la fórmula: `modo`, `origen`,
`columna_origen`, `valor`, `expresion`, `redondeo`, `multiplo`,
`aplicar_tasa`, `aplicar_adicional`, `auto`.

**Ítem** (1 lista → N ítems, uno por producto)

`id`, `lista_id`, `producto_codigo`, `stock_disponible`, `inicial_manual?`,
`cuota_manual?`, `pct_inicial_override?`, `cuotas_override?`.

**Valor** (1 ítem → N valores, uno por columna)

`item_id`, `columna_id`, `precio`, `es_manual` (bool: true si el usuario editó
la celda a mano; protege el valor de los recálculos automáticos).

> Importante: crea **columnas reales** para las fórmulas y los overrides. El
> sistema original las serializaba dentro del *nombre* de columnas ficticias
> (`__fx__…`, `__inicial_manual__`) porque no podía tocar el esquema; eso es
> deuda técnica que no debes reproducir.

### 3. Fórmulas de columna

Cada columna calcula su precio con uno de estos modos:

- `manual` — el usuario escribe el precio (no se recalcula nunca).
- `porcentaje` — `origen * (1 + valor/100)`
- `monto` — `origen + valor`
- `multiplicador` — `origen * valor`
- `expresion` — expresión libre evaluada por el intérprete (ver 3.2).

El **origen** puede ser: `venta` (precio de venta del producto), `costo`,
`base` (precio de la **primera** columna de la lista) u `otra columna`
(por nombre). Una columna **no puede** alimentarse de sí misma: en ese caso el
cálculo devuelve nulo y la celda no se toca.

**Orden de cálculo, exacto:**

```
1. obtener `origen`
2. bruto = aplicar el modo
3. si aplicar_adicional → bruto *= (1 + porcentaje_adicional/100)
4. si aplicar_tasa      → bruto *= tasa_efectiva
5. aplicar el redondeo configurado
```

`tasa_efectiva` = `tasa_del_dia` si es > 0, si no la tasa global del sistema,
si no 1.

**Redondeos:** `ninguno`, `dos` (2 decimales, default), `entero`, `arriba`,
`abajo`, `psicologico` (siempre termina en `,99`: 149,30 → 149,99;
150,00 → 149,99), `multiplo` (al múltiplo de `multiplo` más cercano).

Recalcular **en el orden de las columnas**, para que una columna que se apoya en
otra use el valor recién calculado. La función de recálculo debe:

- aceptar "solo columnas automáticas" (`auto = true`) o una columna concreta,
- **nunca** sobrescribir una celda marcada `es_manual`,
- devolver cuántos precios cambiaron.

#### 3.2 Intérprete de expresiones

Implementa un evaluador propio (o usa uno ya presente en el proyecto) con:

- números con `.` o `,` como decimal; paréntesis;
- operadores `+ - * / ^` y `mod`;
- comparaciones `> < >= <= = <>` y conectores `y` / `o` (devuelven 1 / 0);
- funciones: `redondear(x;dec=2)`, `techo(x)`, `piso(x)`, `abs(x)`,
  `min(a;b)`, `max(a;b)`, `pot(a;b)`, `raiz(x)`, `si(cond;a;b)`;
- variables: `costo`, `venta`, `base`, `tasa`, `adicional`, `inicial`,
  `cuotas`, `recargo`, `stock`;
- referencia a otra columna con `[Nombre]` (sin distinguir mayúsculas) y
  también por su nombre suelto si es una sola palabra;
- separador de argumentos `;` **o** `,`.

Ante cualquier error (variable inexistente, paréntesis sin cerrar, división
entre cero, texto sobrante, NaN o infinito) devuelve **nulo**, nunca una
excepción hacia la interfaz. Expón además una función `validar(expresion)` que
devuelva el mensaje de error para mostrarlo mientras el usuario escribe.

### 4. Auto-población desde el catálogo

Al crear una lista y al pulsar "Actualizar":

1. Filtrar el catálogo por `categoria` y `marca_filtro`, **excluyendo
   subproductos/variantes** (solo productos padre).
2. Ordenar por marca y luego por modelo/nombre.
3. Calcular el precio base, **redondeando en dos pasos**:
   ```
   factor        = 1 + porcentaje_adicional/100
   precioMoneda1 = redondear2(producto.precio_venta * factor)
   precioBase    = es_moneda_local ? redondear2(precioMoneda1 * tasa)
                                   : precioMoneda1
   ```
4. **Preservar el trabajo manual**: si el producto ya estaba en la lista, no
   toques sus precios; actualiza solo el stock y rellena las columnas nuevas
   con el precio por defecto.
5. Quitar de la lista los productos que ya no existen en el catálogo.
6. Recalcular al final las columnas con fórmula automática.
7. El stock del producto padre suma el de sus variantes (unidades serializadas
   no vendidas si la categoría las usa, o stock manual en caso contrario).

Registra el resultado: *N preservados, M nuevos, K eliminados*.

### 5. Modo financiamiento

Cuando `es_financiamiento` está activo, cada ítem muestra **precio base,
inicial y cuota**. Las condiciones pueden variar por producto (una financiadora
puede pedir 30 % en una marca y 40 % en otra). Centraliza el cálculo en cuatro
funciones —la pantalla, el PDF, la imagen exportada, la consulta de precios y
los reportes deben usar **exactamente estas**:

```
pctInicial(item)      = item.pct_inicial_override ?? lista.porcentaje_inicial
cuotas(item)          = item.cuotas_override      ?? lista.numero_cuotas
inicial(item, base)   = item.inicial_manual ?? redondear2(base * pctInicial/100)
cuota(item, base)     = item.cuota_manual ?? (
      !lista.tiene_cuotas ? 0
      : redondear2((base - inicial(item,base)) * (1 + recargo/100) / max(cuotas,1)))
```

Si `tiene_cuotas` es falso, la interfaz **oculta** los campos de número de
cuotas y cuota mensual y muestra solo `Base − Inicial = Deuda`.

Expón `cuotasUniformes`: el número de cuotas si **todos** los ítems coinciden,
o nulo si difieren (los encabezados no deben anunciar un número que no aplica a
toda la lista).

### 6. Interfaz

**Pantalla 1 — Listado de listas**: tarjetas con nombre, fecha, moneda,
cantidad de productos y badge de financiadora. Acciones: crear, editar
configuración, actualizar (re-poblar), eliminar (con confirmación), abrir.

**Pantalla 2 — Detalle de una lista**: buscador por nombre/marca/modelo,
productos **agrupados por marca**, una celda por columna. Para administradores:

- editar el precio de una celda (marca la celda como manual);
- **ajustar una columna completa** por porcentaje o monto fijo, avisando si la
  columna es automática (el ajuste se perderá en el próximo recálculo);
- agregar, renombrar, reordenar y eliminar columnas;
- editor de fórmula por columna con validación en vivo y vista previa sobre un
  producto de muestra;
- en modo financiamiento: fijar inicial/cuota manual y condiciones propias por
  producto (por marca o por modelo).

**Modo lectura** para los demás roles: mismos datos, sin ninguna acción de
edición.

**Exportación**: imagen (PNG de alta resolución con el encabezado de la tienda)
y PDF (tabla agrupada por marca), ambos compartibles por los canales del
sistema. En financiamiento, las columnas exportadas son
`Producto | Precio | Inicial | Cuota`.

### 7. Sincronización

- Guardado con **debounce de ~600 ms** al editar precios.
- Si la lista aún no existe en el servidor, el primer guardado la **crea** y
  adopta el id devuelto (no perder el trabajo hecho antes de guardar).
- Refresco periódico desde el servidor (10–15 s) usando `actualizado_en` o
  ETag; **no** transfieras la lista completa en cada sondeo.
- El refresco **no debe pisar** el trabajo del usuario: sáltalo si hay un
  guardado en curso, si hay cambios pendientes de enviar, o si el usuario editó
  hace menos de ~8 segundos.
- Si el servidor devuelve menos columnas de las que hay en local (una recién
  creada que aún no se guardó), conserva las locales y vuelve a enviarlas.
- Ante error de guardado, muestra el detalle y ofrece **Reintentar**.

### 8. Permisos

Roles administrativos (adaptar a los del sistema destino: administrador, dueño,
maestro) crean, editan y eliminan. Todos los demás ven en modo lectura.
La selección de qué listas se muestran en la consulta rápida de precios es del
rol dueño.

### 9. Integraciones a dejar preparadas

- **Consulta de precios por producto**: dado un código, devolver
  `[nombre de lista, columna, precio, moneda, es_financiamiento, financiadora,
  % inicial del ítem, tiene_cuotas, nº de cuotas del ítem]` de las listas
  marcadas como visibles. Referencia las listas por **id**, no por nombre (dos
  listas pueden llamarse igual).
- **Venta financiada**: al elegir financiadora, ofrecer las listas cuya
  `financiadora` coincida; autoseleccionar si hay una sola; advertir si no hay
  ninguna. El precio de venta sale de la lista elegida, con respaldo al precio
  del catálogo si el producto no está en ella.
- **Tasa de cambio**: si la lista está en moneda local y su `tasa_del_dia`
  difiere de la del sistema, recalcular los precios automáticos y actualizar la
  tasa, **preservando los precios marcados como manuales** (por eso existe
  `es_manual`, en vez de adivinar por tolerancia numérica).

### 10. Criterios de aceptación

1. Crear una lista con filtro de categoría/marca la puebla con los productos
   correctos, sin subproductos, ordenada por marca y modelo.
2. Editar un precio a mano y pulsar "Actualizar" **no** pierde ese precio.
3. Una columna `venta + 15 %` con redondeo psicológico produce precios
   terminados en `,99` para todos los productos.
4. Una columna con la expresión `si(stock > 0; [Contado] * 0,95; [Contado])`
   evalúa correctamente y no rompe si `Contado` no existe (queda sin calcular).
5. Una columna que se referencia a sí misma no produce ningún cambio ni error.
6. En financiamiento con 40 % de inicial, 6 cuotas y 20 % de recargo, un
   producto de 100 da inicial 40 y cuota 12.
7. Un producto con `cuotas_override = 12` muestra 12 cuotas en la pantalla, en
   el PDF, en la imagen y en la consulta de precios, y `cuotasUniformes` pasa a
   ser nulo.
8. Con `tiene_cuotas = false` no aparecen ni el número de cuotas ni la cuota.
9. Dos usuarios editando la misma lista: los cambios de uno aparecen en la
   pantalla del otro sin pisar la edición que este tenga en curso.
10. Un usuario sin rol administrativo no ve ninguna acción de edición.
11. Cambiar la tasa del sistema recalcula los precios automáticos y respeta los
    manuales.
12. La lista se exporta a PDF y a imagen con los datos correctos, incluidos
    inicial y cuota cuando es de financiamiento.

### 11. Entregables

- Migraciones de las cuatro tablas.
- Modelos con serialización y **pruebas unitarias del evaluador de
  expresiones, de los redondeos y de los cálculos de financiamiento**.
- Endpoints CRUD que persistan la lista con sus columnas, ítems y valores de
  forma transaccional.
- Las dos pantallas, la exportación y las integraciones de la sección 9.
- Un README corto del módulo con las fórmulas de las secciones 3 y 5.

Antes de escribir código, revisa el proyecto e indícame: qué partes ya existen
y puedes reutilizar, qué convenciones vas a seguir y en qué archivos vas a
trabajar.
