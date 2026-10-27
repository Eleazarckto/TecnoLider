# Listas de precios — guía para la administración

Desde esta versión cada lista de precios puede calcular sus precios **sola,
desde el costo del producto**. Viene **apagado**: todas las listas siguen
exactamente como hoy (precios a mano) hasta que alguien de la administración
(Dueño, Administrador o Gerente) cambie una lista a «desde el costo».

## Qué cambió para todos

- **Nada se pierde al guardar.** Si dos personas editan la misma lista a la
  vez, cada una guarda solo lo que cambió; ya no gana «el último que guarda».
- Arriba en la lista se ve el estado: **Pendiente · Guardando… · Guardado ·
  Sin guardar**. Mientras no diga *Guardado*, el cambio no está en el
  servidor. Tocarlo fuerza el envío. Si se intenta salir con cambios sin
  guardar, la app espera y, si no puede, pregunta.
- Un precio escrito a mano queda marcado con **✎**. Las columnas con fórmula
  ya no lo pisan.
- **Re-poblar** ya no borra precios ni lo agregado a mano: agrega los
  productos nuevos con stock y saca los que ya no están en el inventario.
  Para volver al precio de partida: menú **Columnas → Recalcular precios**
  (se elige si respetar o no los precios marcados ✎).
- Los vendedores y demás roles **no ven** el % que se le suma al costo ni los
  botones de configuración.

## Listas en Bs que toman el precio de una lista en divisas

Desde el 19/10/2026 una lista en bolívares puede tomar sus precios de una
lista en divisas: lápiz de la lista → **Tomar precios de (lista en
divisas)** → elegir la lista (la sugerida sale primero) → GUARDAR.

- Precio en Bs = **precio en la lista en divisas + % adicional de la lista
  en Bs, × tasa**. Ej.: $100 en divisas, 15 % → $115 × tasa.
- Un producto que no está en la lista en divisas sale, como antes, de su
  precio de venta + % × tasa.
- Al guardar se recalcula la lista entera. Después sigue sola: cuando se
  cambia un precio en la lista en divisas, cuando cambia la tasa y cuando
  se abre la lista. Los precios marcados **✎** (escritos a mano) no se tocan.
- Para volver a como era: elegir **— Ninguna (precio de venta) —**.

## Cómo pasar una lista a «desde el costo»

1. Listas de precios → lápiz de la lista → **Precios: a mano · cambiar…**
   (o dentro de la lista: **Columnas → Cómo se calculan los precios**).
2. Elegir **Desde el costo (automático)** y llenar:
   - **% sobre el costo** (en una lista de financiadora: % sobre el precio de
     venta, que es el precio del producto en su lista Divisas).
   - **Monto fijo en USD** (opcional, se suma antes del %).
   - Lista en Bs: **Tasa BCV del día** o **tasa fija**. Lista Divisas:
     **tasa manual para llevar a Bs** (la usan sus listas en Bs; vacío = BCV).
3. Tocar **ENSAYAR**. No se guarda nada: aparece cuántos precios cambiarían
   y unos ejemplos (antes → después). Si da muchos cambios, ajustar el %.
4. **ACTIVAR**. Se guarda un respaldo de la lista y, desde ese momento, el
   servidor recalcula sus precios cuando cambia el costo de un producto, la
   tasa BCV o la configuración. En esa lista los precios ya no se escriben a
   mano: tocar un precio explica de dónde sale.

Para volver a manual: el mismo diálogo → **A mano** → GUARDAR (los precios
quedan como están). Para deshacer una activación con sus precios de antes,
pedirlo a soporte (`precios_listas_sincronizar.php --revertir --lista ID`).

Consejo: el soporte puede correr `--sugeridos` para saber qué % mantiene los
precios de hoy en cada lista, y empezar por ese número.

## % especial por tipo de producto

Dentro de una lista en modo costo, unos productos pueden llevar otro %:
Forros, Cargadores, iPhone, Cornetas, Vidrios… En el diálogo, sección
**% especial por tipo de producto**: tocar un atajo o **Agregar**, escribir
las palabras del nombre (separadas por coma) o elegir una marca, y el %.
Abajo se ve qué productos de la lista calzan. Vale la **primera** regla que
calce; los demás productos llevan el % de la lista.

## Redondear precios hacia arriba

Interruptor **Redondear precios hacia arriba (sin decimales)**: 22,30 → 23;
en Bs, a bolívares enteros (25.686,99 → 25.687). Así la factura no da vueltos
con céntimos. Vale también para los productos nuevos de una lista a mano.

## Qué costo se usa

Si el mismo producto tiene un costo distinto en cada tienda, vale el
**mayor**. Un producto sin costo cargado conserva el precio que tenga.
