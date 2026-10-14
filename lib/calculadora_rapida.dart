part of 'main.dart';

// ════════════════════════════════════════════════════════════════════
//  CALCULADORA RÁPIDA (con conversión $ ↔ Bs a tasa BCV)
// ════════════════════════════════════════════════════════════════════
//  Los vendedores salían de la app a otra calculadora para sacar
//  cuentas (inicial, porcentaje, pasar dólares a bolívares...). Esta
//  calculadora se abre desde la barra superior de la pantalla principal
//  (y del menú) como diálogo en tablet/PC y como hoja inferior en
//  teléfono, así el vendedor no pierde lo que estaba haciendo.
//
//  El evaluador es propio (sin `eval`): números, + − × ÷, paréntesis y
//  porcentaje con la semántica de una calculadora de mano:
//    200 + 10%  → 220   (suma el 10% de 200)
//    200 − 10%  → 180
//    200 × 10%  → 20
//    50%        → 0,5
// ════════════════════════════════════════════════════════════════════

/// Evalúa [expresion] y devuelve el resultado, o null si la expresión
/// está incompleta o es inválida (o divide entre cero). Acepta coma o
/// punto decimal y los símbolos × ÷ − además de * / -.
double? evaluarExpresionCalculadora(String expresion) {
  final s = expresion
      .replaceAll('×', '*')
      .replaceAll('÷', '/')
      .replaceAll('−', '-')
      .replaceAll(',', '.')
      .replaceAll(' ', '');
  if (s.isEmpty) return null;
  try {
    final p = _ParserCalculadora(s);
    final r = p.expresion();
    if (p.pos != s.length) return null;
    final v = r.esPorcentaje ? r.valor / 100 : r.valor;
    if (v.isNaN || v.isInfinite) return null;
    return v;
  } catch (_) {
    return null;
  }
}

/// Valor intermedio: si [esPorcentaje] es true, [valor] es "N%" todavía
/// sin dividir entre 100 (la suma/resta lo interpreta sobre el operando
/// izquierdo).
class _ValorCalc {
  final double valor;
  final bool esPorcentaje;
  const _ValorCalc(this.valor, [this.esPorcentaje = false]);
  double get comoNumero => esPorcentaje ? valor / 100 : valor;
}

class _ParserCalculadora {
  final String s;
  int pos = 0;
  _ParserCalculadora(this.s);

  String? get _actual => pos < s.length ? s[pos] : null;

  // expresion := termino (('+'|'-') termino)*
  _ValorCalc expresion() {
    var izq = termino();
    while (_actual == '+' || _actual == '-') {
      final op = s[pos++];
      final der = termino();
      final base = izq.comoNumero;
      final delta = der.esPorcentaje ? base * der.valor / 100 : der.valor;
      izq = _ValorCalc(op == '+' ? base + delta : base - delta);
    }
    return izq;
  }

  // termino := unario (('*'|'/') unario)*
  _ValorCalc termino() {
    var izq = unario();
    while (_actual == '*' || _actual == '/') {
      final op = s[pos++];
      final der = unario();
      if (op == '*') {
        izq = _ValorCalc(izq.comoNumero * der.comoNumero);
      } else {
        final d = der.comoNumero;
        if (d == 0) throw const FormatException('División entre cero');
        izq = _ValorCalc(izq.comoNumero / d);
      }
    }
    return izq;
  }

  // unario := ('-'|'+') unario | postfijo
  _ValorCalc unario() {
    if (_actual == '-') {
      pos++;
      final v = unario();
      return _ValorCalc(-v.valor, v.esPorcentaje);
    }
    if (_actual == '+') {
      pos++;
      return unario();
    }
    return postfijo();
  }

  // postfijo := primario '%'?
  _ValorCalc postfijo() {
    final v = primario();
    if (_actual == '%') {
      pos++;
      return _ValorCalc(v.comoNumero, true);
    }
    return v;
  }

  // primario := numero | '(' expresion ')'
  _ValorCalc primario() {
    if (_actual == '(') {
      pos++;
      final v = expresion();
      if (_actual != ')') throw const FormatException('Falta )');
      pos++;
      return _ValorCalc(v.comoNumero);
    }
    final ini = pos;
    while (pos < s.length && RegExp(r'[0-9.]').hasMatch(s[pos])) {
      pos++;
    }
    if (ini == pos) throw const FormatException('Se esperaba un número');
    final n = double.tryParse(s.substring(ini, pos));
    if (n == null) throw const FormatException('Número inválido');
    return _ValorCalc(n);
  }
}

/// Formatea el resultado sin ceros de sobra ("12,5" en vez de "12.50").
String formatoResultadoCalculadora(double v) {
  if (v == v.roundToDouble() && v.abs() < 1e15) return v.toStringAsFixed(0);
  var t = v.toStringAsFixed(6);
  t = t.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return t;
}

/// Abre la calculadora: diálogo en pantallas anchas (tablet/PC), hoja
/// inferior en teléfono.
Future<void> mostrarCalculadoraRapida(BuildContext context) {
  final ancho = MediaQuery.of(context).size.width;
  if (ancho >= 600) {
    return showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: const SizedBox(width: 380, child: _CalculadoraRapida()),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (_) => const SafeArea(child: _CalculadoraRapida()),
  );
}

/// Botón para la barra superior que abre la calculadora.
class BotonCalculadora extends StatelessWidget {
  const BotonCalculadora({super.key});
  @override
  Widget build(BuildContext context) => IconButton(
        icon: const Icon(Icons.calculate_outlined),
        tooltip: 'Calculadora',
        onPressed: () => mostrarCalculadoraRapida(context),
      );
}

class _CalculadoraRapida extends StatefulWidget {
  const _CalculadoraRapida();
  @override
  State<_CalculadoraRapida> createState() => _CalculadoraRapidaState();
}

class _CalculadoraRapidaState extends State<_CalculadoraRapida> {
  String _expr = '';
  /// Última operación terminada (se muestra arriba en pequeño).
  String _anterior = '';
  final _foco = FocusNode();

  double get _tasa => ConfigSistema.tasaCambio;
  double? get _resultado => evaluarExpresionCalculadora(_expr);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _foco.requestFocus());
  }

  @override
  void dispose() {
    _foco.dispose();
    super.dispose();
  }

  void _tecla(String t) {
    setState(() {
      switch (t) {
        case 'C':
          _expr = '';
          _anterior = '';
          break;
        case '⌫':
          if (_expr.isNotEmpty) _expr = _expr.substring(0, _expr.length - 1);
          break;
        case '=':
          final r = _resultado;
          if (r != null) {
            _anterior = '$_expr =';
            _expr = formatoResultadoCalculadora(r);
          }
          break;
        default:
          _expr += t;
      }
    });
  }

  /// Convierte el resultado actual: × tasa ($ → Bs) o ÷ tasa (Bs → $).
  void _convertir({required bool aBs}) {
    final r = _resultado;
    if (r == null || _tasa <= 0) return;
    setState(() {
      _anterior = aBs
          ? '\$${formatoResultadoCalculadora(r)} × ${_tasa.toStringAsFixed(2)} ='
          : 'Bs ${formatoResultadoCalculadora(r)} ÷ ${_tasa.toStringAsFixed(2)} =';
      final v = aBs ? r * _tasa : r / _tasa;
      _expr = formatoResultadoCalculadora(
          (v * 100).roundToDouble() / 100);
    });
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      _tecla('=');
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.backspace) {
      _tecla('⌫');
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape) return KeyEventResult.ignored;
    if (k == LogicalKeyboardKey.delete) {
      _tecla('C');
      return KeyEventResult.handled;
    }
    final c = e.character;
    if (c != null && RegExp(r'^[0-9.,+\-*/()%xX]$').hasMatch(c)) {
      _tecla(c == '*' || c == 'x' || c == 'X' ? '×'
          : c == '/' ? '÷'
          : c == '-' ? '−'
          : c);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final r = _resultado;
    final tasa = _tasa;
    final fechaTasa = TasaBCVScheduler.ultimaTasa?.fechaFormateada;
    return Focus(
      focusNode: _foco,
      onKeyEvent: _onKey,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const Icon(Icons.calculate, color: AppColors.brandBlue),
            const SizedBox(width: 8),
            const Expanded(child: Text('Calculadora',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
            IconButton(
              tooltip: 'Copiar resultado',
              icon: const Icon(Icons.copy, size: 20),
              onPressed: r == null ? null : () {
                Clipboard.setData(ClipboardData(
                    text: formatoResultadoCalculadora(r)));
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                  const SnackBar(content: Text('Resultado copiado'),
                    duration: Duration(seconds: 1)));
              }),
            IconButton(
              tooltip: 'Cerrar',
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop()),
          ]),
          // ── Pantalla ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceGrey,
              borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(_anterior,
                style: const TextStyle(fontSize: 12,
                  color: AppColors.textSecondary)),
              Text(_expr.isEmpty ? '0' : _expr,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 26,
                  fontWeight: FontWeight.w700)),
              Text(r == null ? ' ' : '= ${formatoResultadoCalculadora(r)}',
                style: const TextStyle(fontSize: 15,
                  color: AppColors.brandBlue, fontWeight: FontWeight.w700)),
            ]),
          ),
          const SizedBox(height: 8),
          // ── Conversión a tasa BCV ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.brandBlue.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10)),
            child: tasa <= 0
                ? const Text('Sin tasa BCV cargada: no se puede convertir.',
                    style: TextStyle(fontSize: 12, color: AppColors.statusRed))
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Tasa BCV: Bs ${tasa.toStringAsFixed(2)}'
                         '${fechaTasa != null ? '  ($fechaTasa)' : ''}',
                      style: const TextStyle(fontSize: 12,
                        fontWeight: FontWeight.w700)),
                    if (r != null) ...[
                      Text('Si son \$: ${formatBolivares(r * tasa)}',
                        style: const TextStyle(fontSize: 12)),
                      Text('Si son Bs: ${formatCurrency(r / tasa)}',
                        style: const TextStyle(fontSize: 12)),
                    ],
                  ]),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _botonConv('\$ → Bs', () => _convertir(aBs: true))),
            const SizedBox(width: 6),
            Expanded(child: _botonConv('Bs → \$', () => _convertir(aBs: false))),
          ]),
          const SizedBox(height: 6),
          // ── Teclado ──
          for (final fila in const [
            ['C', '(', ')', '⌫'],
            ['7', '8', '9', '÷'],
            ['4', '5', '6', '×'],
            ['1', '2', '3', '−'],
            ['0', '.', '%', '+'],
          ])
            Row(children: fila.map((t) => Expanded(child: _tecleado(t))).toList()),
          Row(children: [Expanded(child: _tecleado('='))]),
        ]),
      ),
    );
  }

  Widget _botonConv(String texto, VoidCallback onTap) => OutlinedButton(
        onPressed: _resultado == null || _tasa <= 0 ? null : onTap,
        child: Text(texto, style: const TextStyle(fontWeight: FontWeight.w700)),
      );

  Widget _tecleado(String t) {
    final esOp = '÷×−+%()'.contains(t);
    final esIgual = t == '=';
    final esBorrar = t == 'C' || t == '⌫';
    return Padding(
      padding: const EdgeInsets.all(3),
      child: SizedBox(
        height: 48,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            elevation: 0,
            padding: EdgeInsets.zero,
            backgroundColor: esIgual
                ? AppColors.brandBlue
                : esBorrar
                    ? AppColors.statusRed.withValues(alpha: 0.12)
                    : esOp
                        ? AppColors.brandBlue.withValues(alpha: 0.10)
                        : Colors.white,
            foregroundColor: esIgual
                ? Colors.white
                : esBorrar ? AppColors.statusRed : AppColors.textPrimary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: const BorderSide(color: AppColors.surfaceGrey)),
          ),
          onPressed: () => _tecla(t),
          child: Text(t, style: const TextStyle(
            fontSize: 20, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}
