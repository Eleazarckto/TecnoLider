import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'widgets/design_system.dart';
import 'widgets/app_lock_gate.dart';
import 'services/database.dart';
import 'services/permissions.dart';
import 'screens/login_screen.dart';
import 'screens/admin_screen.dart';
import 'screens/company_screen.dart';
import 'screens/operator_screen.dart';
import 'screens/rider_screen.dart';
import 'screens/permissions_screen.dart';
import 'models/models.dart';
import 'services/api_client.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initializeDateFormatting('es', null);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: DS.dark,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  // En produccion la URL viene de api_client.dart (sistemasceccato.com).
  // Para desarrollo local, descomenta la siguiente linea con tu IP:
  // ApiClient.overrideBaseUrl = 'http://192.168.0.198/yj_api';

  runApp(const YjDeliveryApp());
}

class YjDeliveryApp extends StatelessWidget {
  const YjDeliveryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'YJ Delivery',
      debugShowCheckedModeBanner: false,
      theme: DS.buildTheme(),
      home: const _StartupGate(),
    );
  }
}

/// Decide qué pantalla mostrar al arrancar:
///   1. Pantalla de permisos (primera vez)
///   2. Sesión restaurada -> panel del usuario
///   3. Login
class _StartupGate extends StatefulWidget {
  const _StartupGate();

  @override
  State<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<_StartupGate> {
  bool _checking = true;
  bool _showPermissions = false;
  Widget? _destination;

  static const _kPermissionsShownKey = 'permissions_screen_shown';

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    // 1. Verificar si ya se mostró la pantalla de permisos
    final prefs = await SharedPreferences.getInstance();
    final alreadyShown = prefs.getBool(_kPermissionsShownKey) ?? false;

    if (!alreadyShown) {
      // Primera vez - mostrar pantalla de permisos
      if (!mounted) return;
      setState(() {
        _checking = false;
        _showPermissions = true;
      });
      return;
    }

    // 2. Si ya se mostró antes, ir directo al flujo normal
    await _continueToApp();
  }

  Future<void> _continueToApp() async {
    final db = Database.instance;
    final restored = await db.tryRestoreSession();
    if (!mounted) return;

    Widget dest;
    if (restored) {
      switch (db.currentUser!.role) {
        case UserRole.superAdmin:
        case UserRole.admin:
          dest = const AdminScreen();
          break;
        case UserRole.company:
          dest = const CompanyScreen();
          break;
        case UserRole.rider:
          dest = const RiderScreen();
          break;
        case UserRole.operator:
          dest = const OperatorScreen();
          break;
      }
    } else {
      dest = const LoginScreen();
    }

    setState(() {
      _checking = false;
      _showPermissions = false;
      _destination = dest;
    });
  }

  Future<void> _onPermissionsContinue() async {
    // Marcar como mostrada
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPermissionsShownKey, true);
    if (!mounted) return;
    setState(() => _checking = true);
    await _continueToApp();
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        backgroundColor: DS.dark,
        body: Center(
          child: CircularProgressIndicator(color: DS.brandOrange),
        ),
      );
    }

    if (_showPermissions) {
      return PermissionsScreen(onContinue: _onPermissionsContinue);
    }

    return AppLockGate(child: _destination!);
  }
}
