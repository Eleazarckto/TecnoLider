import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/database.dart';
import '../widgets/design_system.dart';
import '../widgets/components.dart';
import '../widgets/app_shell.dart';
import 'admin_tabs/admin_dashboard.dart';
import 'admin_tabs/admin_orders.dart';
import 'admin_tabs/admin_companies.dart';
import 'admin_tabs/admin_riders.dart';
import 'admin_tabs/admin_operators.dart';
import 'admin_tabs/admin_admins.dart';
import 'admin_tabs/admin_config.dart';
import 'admin_tabs/admin_payment_methods.dart';
import 'admin_tabs/admin_debts.dart';
import 'admin_tabs/admin_payouts.dart';
import 'admin_tabs/admin_app_lock.dart';
import 'admin_tabs/admin_tracking.dart';
import 'admin_new_order.dart';
import 'login_screen.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final db = Database.instance;

  @override
  void initState() {
    super.initState();
    db.addListener(_onChange);
  }

  @override
  void dispose() {
    db.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<void> _logout() async {
    await db.logout();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = db.currentUser!;
    final isSuperAdmin = user.role == UserRole.superAdmin;

    final toQuoteCount = db.awaitingQuoteOrders().length;
    final pendingCount = db.pendingOrders().length;
    final activeCount = db.activeOrders().length;
    final ordersBadge = toQuoteCount + pendingCount + activeCount;

    final debtsCount = db.debtOrders().length;
    final ridersOnline = db.riderLocations.where((l) => l.isFresh).length;

    return AppShell(
      userName: user.name,
      userRoleLabel: isSuperAdmin ? 'Super Admin' : 'Administrador',
      userSubtitle: 'Panel central',
      onLogout: _logout,
      roleColor: DS.brandOrange,
      items: [
        const NavItem(
            label: 'Dashboard',
            icon: Icons.insights_outlined,
            body: AdminDashboard()),
        const NavItem(
            label: 'Nueva orden',
            icon: Icons.add_circle_outline,
            body: AdminNewOrderScreen()),
        NavItem(
            label: 'Operaciones',
            icon: Icons.receipt_long_outlined,
            body: const AdminOrders(),
            badge: ordersBadge > 0 ? ordersBadge : null),
        NavItem(
            label: 'Seguimiento',
            icon: Icons.location_on_outlined,
            body: const AdminTracking(),
            badge: ridersOnline > 0 ? ridersOnline : null),
        NavItem(
            label: 'Cuentas pendientes',
            icon: Icons.account_balance_wallet_outlined,
            body: const AdminDebts(),
            badge: debtsCount > 0 ? debtsCount : null),
        const NavItem(
            label: 'Liquidaciones',
            icon: Icons.payments_outlined,
            body: AdminPayouts()),
        const NavItem(
            label: 'Empresas',
            icon: Icons.apartment_outlined,
            body: AdminCompanies()),
        const NavItem(
            label: 'Motorizados',
            icon: Icons.two_wheeler_outlined,
            body: AdminRiders()),
        const NavItem(
            label: 'Operadores',
            icon: Icons.headset_mic_outlined,
            body: AdminOperators()),
        const NavItem(
            label: 'Administradores',
            icon: Icons.shield_outlined,
            body: AdminAdmins()),
        const NavItem(
            label: 'Métodos de pago',
            icon: Icons.payment_outlined,
            body: AdminPaymentMethods()),
        const NavItem(
            label: 'Configuración',
            icon: Icons.tune,
            body: AdminConfig()),
        if (isSuperAdmin)
          NavItem(
            label: 'Bloqueo de app',
            icon: db.appLock.isLocked
                ? Icons.lock
                : Icons.lock_open_outlined,
            body: const AdminAppLock(),
            badge: db.appLock.isLocked ? 1 : null,
          ),
      ],
    );
  }
}
