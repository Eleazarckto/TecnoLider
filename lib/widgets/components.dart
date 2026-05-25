import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/database.dart';
import '../services/sync_service.dart';
import 'design_system.dart';

// ====================== LOGO ======================
/// Refined version of the brand logo - circular, dark inside, orange ring
class YjLogo extends StatelessWidget {
  final double size;
  final bool light;
  const YjLogo({super.key, this.size = 56, this.light = false});

  @override
  Widget build(BuildContext context) {
    final ringWidth = size * 0.055;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: light ? DS.surfaceRaised : DS.dark,
        shape: BoxShape.circle,
        border: Border.all(color: DS.brandOrange, width: ringWidth),
      ),
      child: Center(
        child: RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            children: [
              TextSpan(
                text: 'y',
                style: DS.display(size * 0.42,
                    color: DS.brandBlue, weight: FontWeight.w600),
              ),
              TextSpan(
                text: 'j',
                style: DS.display(size * 0.42,
                    color: DS.brandOrange, weight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ====================== FORMATTERS ======================
String formatMoney(double amount) {
  final db = Database.instance;
  final formatter = NumberFormat.currency(
    locale: 'es',
    symbol: '${db.config.currencySymbol} ',
    decimalDigits: 2,
  );
  return formatter.format(amount);
}

String formatDate(DateTime d) => DateFormat('dd MMM, HH:mm', 'es').format(d);
String formatDateLong(DateTime d) => DateFormat('dd \'de\' MMMM, HH:mm', 'es').format(d);

// ====================== STATUS CHIP ======================
class StatusChip extends StatelessWidget {
  final OrderStatus status;
  final bool small;
  const StatusChip({super.key, required this.status, this.small = false});

  @override
  Widget build(BuildContext context) {
    Color bg, fg;
    IconData icon;
    switch (status) {
      case OrderStatus.awaitingQuote:
        bg = const Color(0xFFFCE7F3);
        fg = const Color(0xFFA21457);
        icon = Icons.request_quote_outlined;
        break;
      case OrderStatus.quoted:
        bg = DS.infoBg;
        fg = DS.info;
        icon = Icons.mark_email_read_outlined;
        break;
      case OrderStatus.rejected:
        bg = DS.dangerBg;
        fg = DS.danger;
        icon = Icons.thumb_down_outlined;
        break;
      case OrderStatus.pending:
        bg = DS.warningBg;
        fg = DS.warning;
        icon = Icons.schedule;
        break;
      case OrderStatus.assigned:
        bg = DS.infoBg;
        fg = DS.info;
        icon = Icons.assignment_ind_outlined;
        break;
      case OrderStatus.inTransit:
        bg = DS.accentBg;
        fg = DS.accent;
        icon = Icons.directions_run;
        break;
      case OrderStatus.delivered:
        bg = DS.successBg;
        fg = DS.success;
        icon = Icons.check_circle_outline;
        break;
      case OrderStatus.cancelled:
        bg = DS.dangerBg;
        fg = DS.danger;
        icon = Icons.cancel_outlined;
        break;
    }
    final fs = small ? 11.0 : 12.0;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: small ? 8 : 10, vertical: small ? 3 : 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(DS.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: fs + 1, color: fg),
          const SizedBox(width: 5),
          Text(
            status.label,
            style: DS.ui(fs, color: fg, weight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// ====================== KPI CARD ======================
/// Editorial-style metric card with eyebrow label and large numeric display
class KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final String? trend;
  final IconData? icon;
  final Color? accentColor;
  final bool compact;

  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    this.trend,
    this.icon,
    this.accentColor,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(compact ? DS.space4 : DS.space5),
      decoration: BoxDecoration(
        color: DS.surfaceRaised,
        borderRadius: BorderRadius.circular(DS.radiusLg),
        border: Border.all(color: DS.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: (accentColor ?? DS.ink).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(DS.radiusSm),
                  ),
                  child: Icon(icon, size: 15, color: accentColor ?? DS.inkSecondary),
                ),
                const SizedBox(width: DS.space3),
              ],
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: DS.eyebrow(),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? DS.space3 : DS.space4),
          Text(
            value,
            style: DS.numeric(compact ? 22 : 28,
                color: accentColor ?? DS.ink, weight: FontWeight.w600),
          ),
          if (trend != null) ...[
            const SizedBox(height: DS.space1),
            Text(trend!, style: DS.ui(12, color: DS.inkMuted)),
          ],
        ],
      ),
    );
  }
}

// ====================== SECTION HEADER ======================
class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? action;
  const SectionHeader({super.key, required this.title, this.subtitle, this.action});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DS.space4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: DS.display(22, weight: FontWeight.w500)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: DS.ui(13, color: DS.inkMuted)),
                ],
              ],
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

// ====================== EMPTY STATE ======================
class EmptyState extends StatelessWidget {
  final String message;
  final String? hint;
  final IconData icon;
  final Widget? action;
  const EmptyState({
    super.key,
    required this.message,
    this.hint,
    this.icon = Icons.inbox_outlined,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DS.space8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: DS.surfaceMuted,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 28, color: DS.inkMuted),
            ),
            const SizedBox(height: DS.space5),
            Text(
              message,
              textAlign: TextAlign.center,
              style: DS.ui(15, color: DS.ink, weight: FontWeight.w500),
            ),
            if (hint != null) ...[
              const SizedBox(height: DS.space2),
              Text(
                hint!,
                textAlign: TextAlign.center,
                style: DS.ui(13, color: DS.inkMuted, height: 1.5),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: DS.space5),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

// ====================== INFO ROW ======================
class InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final int maxLines;
  const InfoRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.maxLines = 2,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DS.space2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: DS.inkMuted),
          const SizedBox(width: DS.space3),
          SizedBox(
            width: 84,
            child: Text(label,
                style: DS.ui(12, color: DS.inkMuted, weight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              style: DS.ui(13, color: DS.ink),
            ),
          ),
        ],
      ),
    );
  }
}

// ====================== SECTION DIVIDER ======================
class SectionDivider extends StatelessWidget {
  final String? label;
  const SectionDivider({super.key, this.label});

  @override
  Widget build(BuildContext context) {
    if (label == null) {
      return const Divider(color: DS.border, thickness: 1, height: DS.space5);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DS.space4),
      child: Row(
        children: [
          Text(label!.toUpperCase(), style: DS.eyebrow()),
          const SizedBox(width: DS.space3),
          const Expanded(child: Divider(color: DS.border, thickness: 1)),
        ],
      ),
    );
  }
}

// ====================== ENTITY ROW (lists) ======================
class EntityRow extends StatelessWidget {
  final IconData icon;
  final String name;
  final String subtitle;
  final List<Widget>? metaChips;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final Color? accentColor;

  const EntityRow({
    super.key,
    required this.icon,
    required this.name,
    required this.subtitle,
    this.metaChips,
    this.onTap,
    this.onDelete,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? DS.brandOrange;
    return Material(
      color: DS.surfaceRaised,
      borderRadius: BorderRadius.circular(DS.radiusLg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DS.radiusLg),
        child: Container(
          padding: const EdgeInsets.all(DS.space4),
          decoration: BoxDecoration(
            border: Border.all(color: DS.border, width: 1),
            borderRadius: BorderRadius.circular(DS.radiusLg),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(DS.radiusMd),
                ),
                child: Icon(icon, color: accent, size: 18),
              ),
              const SizedBox(width: DS.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: DS.ui(14, color: DS.ink, weight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: DS.ui(12, color: DS.inkMuted, height: 1.5)),
                    if (metaChips != null && metaChips!.isNotEmpty) ...[
                      const SizedBox(height: DS.space2),
                      Wrap(
                          spacing: DS.space2,
                          runSpacing: DS.space1,
                          children: metaChips!),
                    ],
                  ],
                ),
              ),
              if (onDelete != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      color: DS.inkMuted, size: 18),
                  onPressed: onDelete,
                  splashRadius: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ====================== META CHIP (small, inline) ======================
class MetaChip extends StatelessWidget {
  final IconData? icon;
  final String label;
  final Color? color;
  const MetaChip({super.key, required this.label, this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? DS.inkMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: DS.surfaceMuted,
        borderRadius: BorderRadius.circular(DS.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: c),
            const SizedBox(width: 4),
          ],
          Text(label, style: DS.ui(11, color: c, weight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ====================== CONFIRMATION DIALOG ======================
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Eliminar',
  String cancelLabel = 'Cancelar',
  bool destructive = true,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierColor: DS.ink.withValues(alpha: 0.4),
    builder: (ctx) => AlertDialog(
      title: Text(title, style: DS.display(20)),
      content: Text(message, style: DS.ui(14, color: DS.inkSecondary, height: 1.5)),
      actionsPadding: const EdgeInsets.fromLTRB(DS.space4, 0, DS.space4, DS.space4),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(cancelLabel),
        ),
        ElevatedButton(
          style: destructive
              ? ElevatedButton.styleFrom(backgroundColor: DS.danger)
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

// ====================== SUCCESS SNACKBAR ======================
void showSuccessSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          const Icon(Icons.check_circle, color: DS.success, size: 18),
          const SizedBox(width: DS.space2),
          Expanded(
            child: Text(message,
                style: DS.ui(13, color: Colors.white, weight: FontWeight.w500)),
          ),
        ],
      ),
    ),
  );
}

void showErrorSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: DS.danger,
      content: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.white, size: 18),
          const SizedBox(width: DS.space2),
          Expanded(
            child: Text(message,
                style: DS.ui(13, color: Colors.white, weight: FontWeight.w500)),
          ),
        ],
      ),
    ),
  );
}

// ====================== LIVE SYNC BADGE ======================
/// Small "live" pill that pulses while the app is polling the server
/// for changes. Lets users see at a glance that data is up-to-date.
class LiveSyncBadge extends StatefulWidget {
  final Color? textColor;
  const LiveSyncBadge({super.key, this.textColor});

  @override
  State<LiveSyncBadge> createState() => _LiveSyncBadgeState();
}

class _LiveSyncBadgeState extends State<LiveSyncBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final SyncService _sync;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _sync = SyncService.instance;
    _sync.addListener(_flash);
  }

  @override
  void dispose() {
    _sync.removeListener(_flash);
    _pulse.dispose();
    super.dispose();
  }

  void _flash() {
    if (!mounted) return;
    // Briefly accelerate the pulse when data changes
    _pulse.duration = const Duration(milliseconds: 400);
    _pulse.forward(from: 0).then((_) {
      if (!mounted) return;
      _pulse.duration = const Duration(milliseconds: 1400);
      _pulse.repeat(reverse: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.textColor ?? DS.success;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) {
            return Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.4 + 0.6 * _pulse.value),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.4 * _pulse.value),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(width: 6),
        Text(
          'EN VIVO',
          style: DS.ui(10,
              color: color, weight: FontWeight.w700, spacing: 0.8),
        ),
      ],
    );
  }
}
// ============================================================
// MEJORAS UX v13
// ============================================================

/// Boton que muestra un spinner mientras ejecuta una accion async.
/// Previene doble-tap y errores de "boton presionado dos veces".
///
/// Uso:
/// ```dart
/// LoadingButton(
///   label: 'Guardar',
///   icon: Icons.save,
///   onPressed: () async {
///     await api.save();
///   },
/// )
/// ```
class LoadingButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final Future<void> Function()? onPressed;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final bool outlined;

  const LoadingButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.backgroundColor,
    this.foregroundColor,
    this.outlined = false,
  });

  @override
  State<LoadingButton> createState() => _LoadingButtonState();
}

class _LoadingButtonState extends State<LoadingButton> {
  bool _loading = false;

  Future<void> _handle() async {
    if (_loading || widget.onPressed == null) return;
    setState(() => _loading = true);
    try {
      await widget.onPressed!();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onPressed == null;
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_loading)
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(
                widget.outlined
                    ? (widget.backgroundColor ?? DS.brandBlue)
                    : (widget.foregroundColor ?? Colors.white),
              ),
            ),
          )
        else if (widget.icon != null)
          Icon(widget.icon, size: 18),
        if (_loading || widget.icon != null) const SizedBox(width: 8),
        Text(widget.label),
      ],
    );

    if (widget.outlined) {
      return OutlinedButton(
        onPressed: disabled || _loading ? null : _handle,
        child: content,
      );
    }

    return ElevatedButton(
      onPressed: disabled || _loading ? null : _handle,
      style: ElevatedButton.styleFrom(
        backgroundColor: widget.backgroundColor ?? DS.brandBlue,
        foregroundColor: widget.foregroundColor ?? Colors.white,
      ),
      child: content,
    );
  }
}

/// Estado vacio con icono, mensaje principal y mensaje secundario opcional.
/// Mejora respecto al EmptyState basico: agrega accion opcional.
class EmptyStateV2 extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? hint;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyStateV2({
    super.key,
    required this.icon,
    required this.message,
    this.hint,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DS.space6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(DS.space4),
              decoration: BoxDecoration(
                color: DS.surfaceMuted,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: DS.inkMuted),
            ),
            const SizedBox(height: DS.space4),
            Text(
              message,
              style: DS.ui(15, weight: FontWeight.w600, color: DS.ink),
              textAlign: TextAlign.center,
            ),
            if (hint != null) ...[
              const SizedBox(height: DS.space2),
              Text(
                hint!,
                style: DS.ui(12, color: DS.inkSecondary, height: 1.4),
                textAlign: TextAlign.center,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: DS.space4),
              ElevatedButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Banner que muestra cuando la conexion a internet esta caida.
/// Se oculta automaticamente cuando vuelve la conexion.
class ConnectionStatusBanner extends StatelessWidget {
  final bool isOnline;
  final String? message;

  const ConnectionStatusBanner({
    super.key,
    required this.isOnline,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    if (isOnline) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
          horizontal: DS.space4, vertical: DS.space2),
      color: DS.warning,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.wifi_off, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message ?? 'Sin conexión - mostrando datos guardados',
              style: DS.ui(12, color: Colors.white, weight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Dialog de confirmacion estandarizado para acciones destructivas.
///
/// Uso:
/// ```dart
/// final confirmed = await confirmAction(
///   context,
///   title: 'Eliminar tramo',
///   message: 'Esta accion no se puede deshacer',
///   confirmLabel: 'Eliminar',
///   isDangerous: true,
/// );
/// if (confirmed == true) { ... }
/// ```
Future<bool?> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirmar',
  String cancelLabel = 'Cancelar',
  bool isDangerous = false,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(cancelLabel),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: isDangerous ? DS.danger : DS.brandBlue,
            foregroundColor: Colors.white,
          ),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}
