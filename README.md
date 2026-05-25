# YJ Delivery — App Flutter (cliente)

Cliente Flutter de la plataforma YJ Delivery. Se conecta al backend Node.js + PostgreSQL para que múltiples dispositivos (Android, iOS, Web, Windows) compartan los mismos datos en tiempo real.

> **Importante:** esta app sola no funciona. Necesita el backend corriendo. El backend está en la carpeta `yj_backend/`. Sigue las instrucciones del `README.md` de esa carpeta primero para tener el servidor activo en `http://localhost:3000`.

## Antes de correr la app por primera vez

```bash
cd yj_delivery
flutter create .
flutter pub get
```

`flutter create .` añade `windows/`, `web/`, `android/`, `ios/`, etc. sin tocar `lib/`.

## Configurar la conexión al backend

La app detecta automáticamente la URL del backend según el dispositivo:

| Dispositivo | URL que usa |
|---|---|
| Web (Chrome/Edge en la misma PC) | `http://localhost:3000` |
| Windows desktop | `http://localhost:3000` |
| Emulador Android | `http://10.0.2.2:3000` |
| Emulador iOS / macOS | `http://localhost:3000` |
| Dispositivo físico (móvil real) | Necesita override — ver abajo |

### Para un teléfono físico en la misma WiFi

Necesitas dos cosas:

**1. Encuentra la IP de tu PC** (la que está corriendo el backend):
- Windows: abre PowerShell y ejecuta `ipconfig`. Busca "Dirección IPv4" (algo como `192.168.1.50`)
- Mac/Linux: ejecuta `ifconfig` o `ip a`

**2. Configura la app**. Edita `lib/main.dart` y antes de `runApp(...)` agrega:

```dart
ApiClient.overrideBaseUrl = 'http://192.168.1.50:3000'; // tu IP real
```

Y agrega el import al inicio:
```dart
import 'services/api_client.dart';
```

**3. Permite el puerto en el firewall de Windows**: cuando arranques el backend Windows preguntará si permites la conexión. Acepta para "redes privadas".

**4. (Solo Android) HTTP en producción**: si vas a hacer un build de release sin HTTPS, edita `android/app/src/main/AndroidManifest.xml` y dentro de `<application>` agrega:
```xml
android:usesCleartextTraffic="true"
```
Para desarrollo (debug build) no es necesario.

## Cómo correr desde el botón "Ejecutar"

### VS Code
1. Instala las extensiones **Flutter** y **Dart**.
2. Abre la carpeta. En la esquina inferior derecha haz clic en el selector y elige Chrome/Edge/Windows.
3. Abre `lib/main.dart` y haz clic en **Run** sobre `main()`. También F5.

### Android Studio / IntelliJ
1. Instala el plugin Flutter.
2. Selecciona el dispositivo en el dropdown superior.
3. Click en ▶ Run o Shift+F10.

### Terminal (lo más rápido)
```bash
flutter run -d chrome     # Chrome
flutter run -d edge       # Edge
flutter run -d windows    # App nativa de Windows
```

## Credenciales para probar

Las que se cargan con `npm run seed` en el backend:

| Rol | Email | Contraseña |
|---|---|---|
| Super Admin (oculto) | brizuelacelularca@gmail.com | Brizu.1508 |
| Empresa demo | empresa@demo.com | demo123 |
| Motorizado demo | motorizado@demo.com | demo123 |
| Operador demo | operador@demo.com | demo123 |

## Cómo se sincroniza entre dispositivos

- Cada dispositivo guarda su token JWT en `shared_preferences` (sesión persistente entre cierres de app).
- Los datos no se almacenan localmente: cada vez que entras a la app o haces una acción, se piden al backend.
- Cuando un usuario crea una orden, los demás la ven al refrescar (próximo login, o cuando se haga `pull-to-refresh` o cambio de pestaña).

> **Nota técnica:** esta versión hace polling implícito al cambiar de pantalla. Si necesitas actualizaciones en tiempo real (ej. el operador ve una orden nueva al instante sin recargar), agregar WebSockets o Server-Sent Events sería el siguiente paso. Pídelo si lo necesitas.

## Estructura

```
lib/
├── main.dart                       # Entry point con session restoration
├── models/models.dart              # Modelos con JSON parsers
├── services/
│   ├── api_client.dart             # HTTP wrapper con JWT + base URL
│   └── database.dart               # Repositorio cacheado (mismo API que antes)
├── widgets/
│   ├── design_system.dart          # Tokens de diseño + theme
│   ├── components.dart             # Logo, chips, KPIs, etc.
│   └── app_shell.dart              # Sidebar/tabs adaptativo
└── screens/
    ├── login_screen.dart
    ├── admin_screen.dart           # + 7 sub-tabs
    ├── company_screen.dart
    ├── operator_screen.dart
    └── rider_screen.dart
```

## Solución de problemas

**"Error de conexión" al hacer login** — el backend no está corriendo o la URL es incorrecta.
- Confirma que `http://localhost:3000/health` devuelve `{"status":"ok"}` en tu navegador.
- Si estás en un dispositivo móvil físico, asegúrate de configurar `overrideBaseUrl` con la IP de tu PC.
- En Windows, acepta el firewall cuando aparezca la primera vez.

**La app dice "Token no provisto"** — algo se desincronizó. Cierra sesión y vuelve a entrar.

**"Este email ya está en uso"** al crear empresa/motorizado — probablemente quedaron datos de pruebas anteriores. Para limpiar la base:
```bash
cd yj_backend
docker compose down -v   # ⚠️ borra TODOS los datos
docker compose up -d
npm run migrate
npm run seed
```

**El emulador Android no se conecta** — verifica que en el emulador la URL sea `http://10.0.2.2:3000` (no `localhost`). Esto se hace automáticamente, pero si modificaste algo, restaura.
