// Pruebas de la lógica pura de inventario y acceso por tienda:
// a qué fila va un ingreso de stock, filtros de exportación y qué
// tienda puede usar cada rol.
import 'package:flutter_test/flutter_test.dart';
import 'package:tecno_lider/main.dart';

Producto _p({
  String codigo = 'CAR1',
  String nombre = 'Cargador tipo C',
  String categoria = 'Accesorios',
  String marca = 'Samsung',
  String modelo = 'N/A',
  String tienda = '',
  int stock = 0,
}) =>
    Producto(
      codigo: codigo, nombre: nombre, categoria: categoria, marca: marca,
      modelo: modelo, tipo: nombre, precioCosto: 2, precioVenta: 5,
      stockManual: stock, tienda: tienda,
    );

void main() {
  group('planIngresoStock', () {
    test('suma en la fila de la misma tienda', () {
      final filas = [_p(tienda: 'Principal', stock: 10), _p(tienda: 'Sucursal', stock: 3)];
      final plan = planIngresoStock(filas, 'Sucursal');
      expect(plan.accion, AccionIngresoStock.sumarFila);
      expect(plan.fila!.tienda, 'Sucursal');
    });

    test('nunca suma en la principal si la tienda no tiene fila', () {
      final filas = [_p(tienda: 'Principal', stock: 10)];
      final plan = planIngresoStock(filas, 'Sucursal');
      expect(plan.accion, AccionIngresoStock.crearFila);
      // La fila de la principal sólo sirve de plantilla (datos).
      expect(plan.fila!.tienda, 'Principal');
    });

    test('la fila general vacía se asigna a la tienda', () {
      final filas = [_p(tienda: '', stock: 0), _p(tienda: 'Principal', stock: 4)];
      final plan = planIngresoStock(filas, 'Sucursal');
      expect(plan.accion, AccionIngresoStock.asignarFilaGeneral);
    });

    test('la fila general con stock no se toca: se crea la de la tienda', () {
      final filas = [_p(tienda: '', stock: 7)];
      expect(planIngresoStock(filas, 'Sucursal').accion,
          AccionIngresoStock.crearFila);
    });

    test('inventario general explícito suma en la fila general', () {
      final filas = [_p(tienda: '', stock: 7)];
      expect(planIngresoStock(filas, '').accion, AccionIngresoStock.sumarFila);
    });

    test('copia para otra tienda conserva los datos', () {
      final c = copiaProductoParaTienda(
          _p(tienda: 'Principal', stock: 10), 'Sucursal', 10);
      expect(c.tienda, 'Sucursal');
      expect(c.stockManual, 10);
      expect(c.nombre, 'Cargador tipo C');
      expect(c.precioVenta, 5);
      expect(c.id, isNull);
    });
  });

  group('errores del servidor', () {
    test('endpoint faltante', () {
      expect(esErrorEndpointFaltante(
          "Exception: Recurso 'stock_ingresar' no existe"), isTrue);
      expect(esErrorEndpointFaltante(
          'Error del servidor 500 [POST stock_ingresar]: Handler no encontrado: stock_ingresar.php'),
          isTrue);
      expect(esErrorEndpointFaltante('Recurso no encontrado [POST x].'), isTrue);
      expect(esErrorEndpointFaltante('La cantidad debe ser mayor a 0'), isFalse);
    });
    test('duplicado', () {
      expect(esErrorDuplicado("SQLSTATE[23000]: Duplicate entry 'X-Sucursal'"), isTrue);
      expect(esErrorDuplicado('Timeout'), isFalse);
    });
  });

  group('filtros de exportación', () {
    final forro = _p(codigo: 'F1', nombre: 'Forro iPhone 13', marca: 'Genérico');
    final cargador = _p(codigo: 'C1', nombre: 'Cargador 20W', marca: 'Apple');
    final tel = _p(codigo: 'T1', nombre: 'Galaxy A15', categoria: 'Telefonos',
        marca: 'Samsung', modelo: 'A15');

    test('sin filtros pasa todo', () {
      const f = FiltroExportInventario();
      expect(f.vacio, isTrue);
      expect([forro, cargador, tel].where((p) => coincideFiltroExport(p, f)).length, 3);
    });

    test('categoría + texto "forro"', () {
      const f = FiltroExportInventario(categoria: 'accesorios', texto: 'forro');
      expect(coincideFiltroExport(forro, f), isTrue);
      expect(coincideFiltroExport(cargador, f), isFalse);
      expect(coincideFiltroExport(tel, f), isFalse);
    });

    test('marca y modelo', () {
      expect(coincideFiltroExport(tel,
          const FiltroExportInventario(marca: 'SAMSUNG', modelo: 'a15')), isTrue);
      expect(coincideFiltroExport(cargador,
          const FiltroExportInventario(marca: 'Samsung')), isFalse);
    });

    test('texto con varias palabras exige todas', () {
      expect(coincideFiltroExport(forro,
          const FiltroExportInventario(texto: 'forro 13')), isTrue);
      expect(coincideFiltroExport(forro,
          const FiltroExportInventario(texto: 'forro 15')), isFalse);
    });

    test('valores distintos sin repetir ni vacíos', () {
      final v = valoresDistintos(
          [forro, cargador, tel, _p(marca: 'apple'), _p(marca: '')],
          (p) => p.marca);
      expect(v, ['Apple', 'Genérico', 'Samsung']);
    });

    test('modelo N/A cuenta como vacío', () {
      expect(esModeloVacio('N/A'), isTrue);
      expect(esModeloVacio(''), isTrue);
      expect(esModeloVacio('A15'), isFalse);
    });
  });

  group('acceso por tienda', () {
    const tiendas = ['Principal', 'Sucursal'];

    test('roles altos no están restringidos', () {
      for (final r in ['Dueño', 'Administrador', 'Gerente', 'Maestro']) {
        expect(rolRestringidoATienda(r), isFalse, reason: r);
      }
      expect(rolRestringidoATienda('Vendedor'), isTrue);
      expect(rolRestringidoATienda('Encargado'), isTrue);
    });

    test('vendedor con tienda asignada entra a la suya', () {
      expect(tiendaForzadaParaLogin(
          rol: 'Vendedor', tiendaAsignada: ' sucursal', tiendas: tiendas),
          'Sucursal');
    });

    test('vendedor sin tienda asignada o tienda inexistente elige', () {
      expect(tiendaForzadaParaLogin(
          rol: 'Vendedor', tiendaAsignada: '', tiendas: tiendas), isNull);
      expect(tiendaForzadaParaLogin(
          rol: 'Vendedor', tiendaAsignada: 'Vieja', tiendas: tiendas), isNull);
    });

    test('dueño nunca es forzado', () {
      expect(tiendaForzadaParaLogin(
          rol: 'Dueño', tiendaAsignada: 'Principal', tiendas: tiendas), isNull);
    });

    test('facturar sólo en la tienda asignada', () {
      expect(motivoNoPuedeFacturar(
          rol: 'Vendedor', tiendaAsignada: 'Principal', tiendaVenta: 'Principal'),
          isNull);
      expect(motivoNoPuedeFacturar(
          rol: 'Vendedor', tiendaAsignada: 'Principal', tiendaVenta: 'Sucursal'),
          isNotNull);
      expect(motivoNoPuedeFacturar(
          rol: 'Administrador', tiendaAsignada: 'Principal', tiendaVenta: 'Sucursal'),
          isNull);
      expect(motivoNoPuedeFacturar(
          rol: 'Vendedor', tiendaAsignada: '', tiendaVenta: 'Sucursal'),
          isNull);
    });
  });

  group('tienda asignada en la ficha del usuario', () {
    Usuario u(String rol, String tienda) => Usuario(nombre: 'X', cedula: '',
        correo: '$rol$tienda@x.com', clave: '1234', rol: rol, tienda: tienda);

    test('opciones: "sin tienda" primero y luego las tiendas', () {
      expect(opcionesTiendaUsuario(['Principal', 'Sucursal'], ''),
          ['', 'Principal', 'Sucursal']);
    });

    test('una tienda que ya no existe se conserva para no romper el selector', () {
      expect(opcionesTiendaUsuario(['Principal'], 'Vieja'),
          ['', 'Principal', 'Vieja']);
      expect(opcionesTiendaUsuario(['Principal'], 'Principal'),
          ['', 'Principal']);
    });

    test('etiqueta de la tarjeta', () {
      expect(etiquetaTiendaUsuario(''), 'Sin tienda (todas)');
      expect(etiquetaTiendaUsuario(' Sucursal '), 'Sucursal');
    });

    test('cuenta sólo vendedores (roles restringidos) sin tienda', () {
      final lista = [
        u('Vendedor', ''), u('Vendedor', 'Principal'), u('Activador', ''),
        u('Dueño', ''), u('Administrador', ''),
      ];
      expect(contarSinTiendaAsignada(lista), 2);
      expect(avisoSinTiendaAsignada(lista), '2 vendedores sin tienda asignada');
      expect(avisoSinTiendaAsignada([u('Vendedor', '')]),
          '1 vendedor sin tienda asignada');
      expect(avisoSinTiendaAsignada([u('Dueño', '')]), isNull);
    });

    test('la tienda viaja en toMap/fromMap', () {
      final m = u('Vendedor', 'Sucursal').toMap();
      expect(m['tienda'], 'Sucursal');
      expect(Usuario.fromMap({...m, 'id': '7'}).tienda, 'Sucursal');
    });
  });
}
