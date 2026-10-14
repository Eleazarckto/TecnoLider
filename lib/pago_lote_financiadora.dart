part of 'main.dart';

// ════════════════════════════════════════════════════════════════════
//  PAGO POR LOTE DE LA FINANCIADORA (Reporte por Financiadora)
// ════════════════════════════════════════════════════════════════════
//  La financiadora (Krece / Cashea / Weppa) le paga a la tienda el LOTE
//  completo y siempre está al día; registrar el pago equipo por equipo
//  era lento. Aquí se seleccionan todos los equipos con saldo (filtrando
//  por período de venta y tienda), se desmarcan los que no entran y el
//  monto se reparte entre los seleccionados con
//  `repartirPagoEntreEquipos` (lib/cuenta_financiadora.dart).
//
//  Cada equipo queda con SU propio registro en `pagos_financiadora`
//  (con la marca `[[fin_eq:NRO|IMEI]]` en notas, igual que el pago
//  individual), así la cuenta por equipo del reporte sigue cuadrando.
//  Todos los registros del lote comparten referencia y una nota común
//  "Pago por lote ..." para poder ubicarlos.
// ════════════════════════════════════════════════════════════════════

extension _PagoLoteFinanciadora on _VentanaReporteFinanciadoraState {
  Future<void> _registrarPagoLote(String financiadora) async {
    final datosFin = _porFinanciadora[financiadora];
    final cuentas = datosFin == null
        ? <EquipoFinanciado>[]
        : List<EquipoFinanciado>.from(
            datosFin['cuentas'] as List<EquipoFinanciado>);
    final conSaldo = cuentas.where((e) => e.saldo > 0.009).toList()
      ..sort((a, b) {
        final fa = parseFechaFlexible(a.fecha);
        final fb = parseFechaFlexible(b.fecha);
        if (fa == null || fb == null) return 0;
        return fa.compareTo(fb);
      });
    if (conSaldo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('No hay equipos de $financiadora con saldo pendiente '
                      'en este rango. Ajusta el rango de fechas.'),
        backgroundColor: AppColors.statusOrange));
      return;
    }

    // Tienda de cada factura (el equipo no la trae).
    final tiendaPorFactura = <String, String>{
      for (final f in ventasGlobal) f.nroFactura: f.tienda,
    };
    String tiendaDe(EquipoFinanciado e) => tiendaPorFactura[e.nroFactura] ?? '';
    final tiendas = conSaldo.map(tiendaDe).where((t) => t.isNotEmpty)
        .toSet().toList()..sort();

    final montoCtrl = TextEditingController();
    final refCtrl = TextEditingController();
    final notasCtrl = TextEditingController();
    DateTime fecha = DateTime.now();
    String? tienda;
    DateTimeRange? periodo;
    String filtro = '';
    // Por defecto TODOS seleccionados: la financiadora paga al día.
    final sel = <String>{for (final e in conSaldo) e.clave};

    String f2(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        final q = filtro.toLowerCase().trim();
        final visibles = conSaldo.where((e) {
          if (tienda != null && tiendaDe(e) != tienda) return false;
          if (periodo != null) {
            final fv = parseFechaFlexible(e.fecha);
            if (fv == null) return false;
            final d = DateTime(fv.year, fv.month, fv.day);
            if (d.isBefore(periodo!.start) || d.isAfter(periodo!.end)) return false;
          }
          if (q.isEmpty) return true;
          return e.descripcion.toLowerCase().contains(q) ||
              e.imei.toLowerCase().contains(q) ||
              e.cliente.toLowerCase().contains(q) ||
              e.nroFactura.toLowerCase().contains(q);
        }).toList();
        // Solo cuenta lo seleccionado que además está visible: si el
        // usuario filtra, el lote es lo que ve marcado.
        final elegidos = visibles.where((e) => sel.contains(e.clave)).toList();
        final totalSel = redondearCentavos(
            elegidos.fold<double>(0, (t, e) => t + e.saldo));
        final monto = redondearCentavos(
            double.tryParse(montoCtrl.text.trim().replaceAll(',', '.')) ?? 0);
        final reparto = repartirPagoEntreEquipos(elegidos, monto);
        final asignado = <String, double>{
          for (var i = 0; i < elegidos.length; i++) elegidos[i].clave: reparto[i],
        };
        final dif = redondearCentavos(monto - totalSel);
        final todosVisiblesSel = visibles.isNotEmpty &&
            visibles.every((e) => sel.contains(e.clave));

        return AlertDialog(
          title: Text('Pago por lote — $financiadora',
            style: const TextStyle(fontWeight: FontWeight.w800)),
          content: SizedBox(
            width: 620,
            child: Column(mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // ── Filtros ──
              Wrap(spacing: 8, runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center, children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.date_range, size: 16),
                  label: Text(periodo == null
                      ? 'Todo el reporte'
                      : '${f2(periodo!.start)} – ${f2(periodo!.end)}'),
                  onPressed: () async {
                    final r = await showDateRangePicker(
                      context: ctx,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 1)),
                      initialDateRange: periodo,
                      helpText: 'Fecha de venta de los equipos',
                    );
                    setS(() => periodo = r);
                  }),
                if (periodo != null)
                  IconButton(
                    tooltip: 'Quitar período',
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () => setS(() => periodo = null)),
                if (tiendas.length > 1)
                  DropdownButton<String?>(
                    value: tienda,
                    hint: const Text('Todas las tiendas'),
                    items: [
                      const DropdownMenuItem<String?>(value: null,
                        child: Text('Todas las tiendas')),
                      ...tiendas.map((t) => DropdownMenuItem<String?>(
                        value: t, child: Text(t))),
                    ],
                    onChanged: (v) => setS(() => tienda = v),
                  ),
              ]),
              const SizedBox(height: 6),
              TextField(
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Buscar por modelo, IMEI, cliente o factura',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder()),
                onChanged: (v) => setS(() => filtro = v),
              ),
              Row(children: [
                Checkbox(
                  value: todosVisiblesSel,
                  onChanged: (v) => setS(() {
                    if (v == true) {
                      sel.addAll(visibles.map((e) => e.clave));
                    } else {
                      sel.removeAll(visibles.map((e) => e.clave));
                    }
                  }),
                ),
                Expanded(child: Text(
                  'Seleccionar todos (${elegidos.length}/${visibles.length})',
                  style: const TextStyle(fontWeight: FontWeight.w700))),
              ]),
              Flexible(child: visibles.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Sin equipos con esos filtros',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textSecondary)))
                  : ListView(shrinkWrap: true, children: visibles.map((e) {
                      final marcado = sel.contains(e.clave);
                      final a = asignado[e.clave];
                      return CheckboxListTile(
                        dense: true,
                        value: marcado,
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: (v) => setS(() {
                          if (v == true) { sel.add(e.clave); } else { sel.remove(e.clave); }
                        }),
                        title: Text(e.descripcion,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(
                          '${e.imei.isNotEmpty ? 'IMEI ${e.imei}' : 'Cód. ${e.codigo}'}'
                          ' · ${e.cliente} · Fact. ${e.nroFactura} · ${e.fecha}'
                          '${tiendaDe(e).isNotEmpty ? ' · ${tiendaDe(e)}' : ''}',
                          style: const TextStyle(fontSize: 11)),
                        secondary: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(formatCurrency(e.saldo),
                              style: const TextStyle(fontWeight: FontWeight.w800,
                                color: AppColors.statusOrange)),
                            if (marcado && monto > 0 && a != null)
                              Text('Aplica ${formatCurrency(a)}',
                                style: TextStyle(fontSize: 10,
                                  color: a + 0.009 < e.saldo
                                      ? AppColors.statusRed
                                      : AppColors.statusGreen)),
                          ]),
                      );
                    }).toList())),
              const Divider(),
              // ── Totales: seleccionado vs pagado ──
              Row(children: [
                Expanded(child: Text('Total seleccionado: ${formatCurrency(totalSel)}',
                  style: const TextStyle(fontWeight: FontWeight.w800))),
                TextButton(
                  onPressed: totalSel <= 0 ? null : () => setS(() =>
                      montoCtrl.text = totalSel.toStringAsFixed(2)),
                  child: const Text('Usar este monto')),
              ]),
              TextField(
                controller: montoCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Monto pagado por la financiadora (USD) *',
                  prefixIcon: Icon(Icons.attach_money),
                  border: OutlineInputBorder()),
                onChanged: (_) => setS(() {}),
              ),
              if (monto > 0) Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  dif.abs() < 0.01
                      ? 'El pago cuadra exacto con los equipos seleccionados.'
                      : dif > 0
                          ? 'El pago supera lo seleccionado por ${formatCurrency(dif)} '
                            '(quedará como sobrepago en el último equipo).'
                          : 'Faltan ${formatCurrency(dif.abs())}: los últimos equipos '
                            'quedarán con abono parcial.',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                    color: dif.abs() < 0.01
                        ? AppColors.statusGreen : AppColors.statusOrange)),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: InkWell(
                  onTap: () async {
                    final p = await showDatePicker(
                      context: ctx,
                      initialDate: fecha,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 30)));
                    if (p != null) setS(() => fecha = p);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      isDense: true, labelText: 'Fecha del pago',
                      border: OutlineInputBorder()),
                    child: Text(f2(fecha))),
                )),
                const SizedBox(width: 8),
                Expanded(child: TextField(
                  controller: refCtrl,
                  decoration: const InputDecoration(
                    isDense: true, labelText: 'Referencia',
                    border: OutlineInputBorder()),
                )),
              ]),
              const SizedBox(height: 8),
              TextField(
                controller: notasCtrl,
                decoration: const InputDecoration(
                  isDense: true, labelText: 'Notas (opcional)',
                  border: OutlineInputBorder()),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
            ElevatedButton.icon(
              onPressed: elegidos.isEmpty || monto <= 0
                  ? null : () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.check),
              label: Text('Registrar (${elegidos.length} equipos)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandBlue,
                foregroundColor: Colors.white),
            ),
          ],
        );
      }),
    );
    if (ok != true || !mounted) return;

    // Recalcular con el estado final del diálogo.
    final elegidos = conSaldo.where((e) {
      if (!sel.contains(e.clave)) return false;
      if (tienda != null && tiendaDe(e) != tienda) return false;
      if (periodo != null) {
        final fv = parseFechaFlexible(e.fecha);
        if (fv == null) return false;
        final d = DateTime(fv.year, fv.month, fv.day);
        if (d.isBefore(periodo!.start) || d.isAfter(periodo!.end)) return false;
      }
      final q = filtro.toLowerCase().trim();
      return q.isEmpty ||
          e.descripcion.toLowerCase().contains(q) ||
          e.imei.toLowerCase().contains(q) ||
          e.cliente.toLowerCase().contains(q) ||
          e.nroFactura.toLowerCase().contains(q);
    }).toList();
    final monto = redondearCentavos(
        double.tryParse(montoCtrl.text.trim().replaceAll(',', '.')) ?? 0);
    final reparto = repartirPagoEntreEquipos(elegidos, monto);
    final idPorFactura = <String, int?>{
      for (final f in ventasGlobal) f.nroFactura: f.id,
    };
    final fechaTxt = f2(fecha);
    final notaLote = [
      'Pago por lote ${elegidos.length} equipos ${formatCurrency(monto)} $fechaTxt',
      if (notasCtrl.text.trim().isNotEmpty) notasCtrl.text.trim(),
    ].join(' · ');

    // Se registra equipo por equipo; si algo falla a mitad se informa
    // cuántos quedaron para no duplicar al reintentar.
    int hechos = 0;
    double registrado = 0;
    try {
      for (var i = 0; i < elegidos.length; i++) {
        final parte = reparto[i];
        if (parte <= 0) continue;
        final e = elegidos[i];
        final idEquipo = e.imei.isNotEmpty ? e.imei : e.codigo;
        final facturaId = idPorFactura[e.nroFactura];
        await _Api.post('pagos_financiadora', {
          'financiadora': financiadora,
          'monto'       : parte,
          'fecha'       : fechaTxt,
          'referencia'  : refCtrl.text.trim(),
          'notas'       : escribirMarcaEquipoPago(notaLote, e.nroFactura, idEquipo),
          if (facturaId != null) 'factura_id': facturaId,
          'nro_factura' : e.nroFactura,
          'imei'        : idEquipo,
        });
        hechos++;
        registrado = redondearCentavos(registrado + parte);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Pago por lote registrado: $financiadora — '
              '${formatCurrency(registrado)} en $hechos equipo(s)'),
          backgroundColor: AppColors.statusGreen));
      }
    } catch (e) {
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('El pago por lote quedó incompleto'),
            content: Text(
              'Se registraron $hechos equipo(s) por ${formatCurrency(registrado)} '
              'antes del error.\n\nNO repitas el lote completo: vuelve a abrir '
              '"Pago por lote" (los equipos ya pagados ya no tendrán saldo) y '
              'registra solo lo que falta.\n\nDetalle: $e'),
            actions: [TextButton(onPressed: () => Navigator.pop(c),
              child: const Text('Entendido'))],
          ),
        );
      }
    }
    await _cargar();
  }
}
