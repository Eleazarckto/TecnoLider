// Pruebas del historial de precios y de la foto de precios por factura:
// una venta vieja NO cambia de ganancia cuando el dueño actualiza el
// precio del producto (reclamo del audio de oct-2026).
import 'package:flutter_test/flutter_test.dart';
import 'package:tecno_lider/finanzas_tienda.dart';
import 'package:tecno_lider/historial_precios.dart';

void main() {
  // Venta del 10/10 a las 11:00 de un equipo de costo 88 y contado 100.
  final venta = DateTime(2026, 10, 10, 11);
  // El 14/10 el dueño subió el producto a costo 95 y contado 115.
  final cambio = CambioPrecioCF(
    vigenteHasta: DateTime(2026, 10, 14, 9, 30),
    costo: 88,
    venta: 100,
    listas: const [
      PrecioListaCF(lista: 'KRECE', financiadora: 'Krece', precio: 127),
    ],
    usuario: 'Dueño',
  );

  group('Precio vigente en la fecha de la venta', () {
    test('Ejemplo del dueño: subir el precio no cambia la venta anterior',
        () {
      final p = preciosVigentesEn([cambio], venta,
          costoActual: 95, ventaActual: 115);
      expect(p.origen, origenPrecioHistorial);
      expect(p.costo, 88);
      expect(p.venta, 100);
      expect(p.listas!.single.precio, 127);
      // La ganancia real de esa venta sigue siendo 12 (no 20).
      final v = analizarFactura(
          FacturaCF(
            nroFactura: 'F1',
            tienda: 'T1',
            fecha: DateTime(2026, 10, 10),
            equipos: [
              EquipoVendidoCF(
                  costo: p.costo, precioContado: p.venta,
                  origenPrecio: p.origen),
            ],
            pagos: const [PagoClienteCF(monto: 100, enBolivares: false)],
          ),
          const TasasCF(tasaBcv: 879, tasaDivisa: 1015));
      expect(v.gananciaReal, 12);
    });

    test('Una venta posterior al cambio usa el precio nuevo', () {
      final p = preciosVigentesEn([cambio], DateTime(2026, 10, 14, 10),
          costoActual: 95, ventaActual: 115);
      expect(p.origen, origenPrecioActual);
      expect(p.costo, 95);
      expect(p.venta, 115);
    });

    test('Con varios cambios manda el primero posterior a la venta', () {
      final h = [
        CambioPrecioCF(
            vigenteHasta: DateTime(2026, 10, 14), costo: 88, venta: 100),
        CambioPrecioCF(
            vigenteHasta: DateTime(2026, 10, 5), costo: 80, venta: 90),
      ];
      expect(preciosVigentesEn(h, DateTime(2026, 10, 3),
              costoActual: 95, ventaActual: 115)
          .venta, 90);
      expect(preciosVigentesEn(h, DateTime(2026, 10, 7),
              costoActual: 95, ventaActual: 115)
          .venta, 100);
    });

    test('Sin historial: el precio actual (no hay otro dato)', () {
      final p = preciosVigentesEn(const [], venta,
          costoActual: 95, ventaActual: 115);
      expect(p.origen, origenPrecioActual);
      expect(p.venta, 115);
    });
  });

  group('Persistencia en configuracion', () {
    test('Historial ida y vuelta, ordenado y con límite', () {
      expect(claveHistorialPrecio('A15'), 'hist_precio_A15');
      var guardado = agregarCambioPrecio(null, cambio);
      guardado = agregarCambioPrecio(
          guardado,
          CambioPrecioCF(
              vigenteHasta: DateTime(2026, 10, 1), costo: 80, venta: 90));
      final h = leerHistorialPrecio(guardado);
      expect(h.length, 2);
      expect(h.first.venta, 90);
      expect(h.last.listas.single.lista, 'KRECE');
      expect(h.last.usuario, 'Dueño');
      final corto = agregarCambioPrecio(guardado,
          CambioPrecioCF(vigenteHasta: DateTime(2026, 10, 20), costo: 1, venta: 2),
          maximo: 2);
      expect(leerHistorialPrecio(corto).map((c) => c.venta), [100, 2]);
    });

    test('Foto de la factura ida y vuelta; busca por IMEI o por código', () {
      final foto = SnapshotFacturaCF(
        momento: DateTime(2026, 10, 14, 15, 20),
        tasaBcv: 879,
        tasaDivisa: 1015,
        financiadora: 'Krece',
        lista: 'KRECE',
        items: const [
          ItemSnapshotCF(codigo: 'A15', imei: '3505', costo: 88, venta: 100,
              precioFinanciadora: 127),
          ItemSnapshotCF(codigo: 'FORRO', costo: 2, venta: 5),
        ],
      );
      expect(claveSnapshotFactura('F-1'), 'snap_fac_F-1');
      final f = SnapshotFacturaCF.fromJson(foto.toJson());
      expect(f.tasaBcv, 879);
      expect(f.tasaDivisa, 1015);
      expect(f.item('A15', '3505')!.precioFinanciadora, 127);
      expect(f.item('FORRO', '')!.venta, 5);
      expect(f.item('FORRO', '')!.precioFinanciadora, isNull);
      expect(f.item('OTRO', ''), isNull);
    });
  });
}
