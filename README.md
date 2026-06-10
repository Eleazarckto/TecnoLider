# Tecno Líder — Sistema de Gestión Comercial

App Flutter (Android / iOS / Web / Desktop) para el sistema POS + ERP de **Tecno Líder C.A.** Cubre ventas, inventario, cuentas por cobrar/pagar, servicio técnico, líneas telefónicas, contratos financiados, comisiones, reportes, mensajería interna, conciliación BDV, integración Cashea e impresión térmica directa.

---

## 📦 Contenido del paquete

```
tecno_lider/
├── lib/
│   └── main.dart                                    ← Código completo (39.5k líneas)
├── pubspec.yaml                                     ← Dependencias + launcher icons + splash
├── README.md
│
├── assets/icon/
│   └── logo_tecno_lider.jpeg                        ← Logo corporativo
│
├── android/
│   ├── build.gradle                                 ← Build raíz
│   ├── settings.gradle                              ← Plugin management
│   ├── gradle.properties                            ← Tunings de build
│   ├── key.properties.example                       ← Plantilla de signing
│   └── app/
│       ├── build.gradle                             ← Build app + signing release
│       └── src/main/
│           ├── AndroidManifest.xml                  ← Permisos + USB filter + USB intent
│           └── res/
│               ├── values/styles.xml                ← Splash theme (Android < 12)
│               ├── values/colors.xml                ← Paleta Tecno Líder
│               ├── values-night/styles.xml          ← Splash modo oscuro
│               ├── values-v31/styles.xml            ← Splash Android 12+ API
│               ├── drawable/launch_background.xml   ← Splash drawable
│               ├── drawable-v21/launch_background.xml
│               └── xml/device_filter.xml            ← VID/PID impresoras USB
│
└── ios/Runner/
    ├── Info.plist                                   ← Permisos iOS + ATS + URL schemes
    ├── Base.lproj/LaunchScreen.storyboard           ← Splash iOS
    └── Assets.xcassets/LaunchImage.imageset/
        └── Contents.json                            ← Asset catalog del splash
```

> **Nota:** Este paquete contiene los archivos *modificados/creados específicamente*. El resto del esqueleto (gradle wrapper, MainActivity, ios/Runner.xcodeproj, etc.) lo genera Flutter automáticamente con el comando del paso 1.

---

## 🚀 Cómo crear el proyecto desde cero

### Requisitos
- Flutter SDK `>= 3.19.0` (Dart `>= 3.3.0`)
- Android Studio + emulador o dispositivo Android físico
- Para iOS: Mac con Xcode 15+

### Paso 1 — Crear el proyecto base

```bash
flutter create --org com.tecnolider --project-name tecno_lider tecno_lider
cd tecno_lider
```

### Paso 2 — Reemplazar archivos por los del paquete

```bash
# Sobre el directorio del proyecto recién creado:
PAQUETE=<ruta-al-paquete-extraido>/tecno_lider

# Código y configuración Flutter
cp $PAQUETE/lib/main.dart                                 lib/main.dart
cp $PAQUETE/pubspec.yaml                                  pubspec.yaml
cp $PAQUETE/README.md                                     README.md

# Logo
mkdir -p assets/icon
cp $PAQUETE/assets/icon/logo_tecno_lider.jpeg             assets/icon/

# Android
cp $PAQUETE/android/build.gradle                          android/build.gradle
cp $PAQUETE/android/settings.gradle                       android/settings.gradle
cp $PAQUETE/android/gradle.properties                     android/gradle.properties
cp $PAQUETE/android/key.properties.example                android/key.properties.example
cp $PAQUETE/android/app/build.gradle                      android/app/build.gradle
cp $PAQUETE/android/app/src/main/AndroidManifest.xml      android/app/src/main/AndroidManifest.xml
cp -r $PAQUETE/android/app/src/main/res/                  android/app/src/main/

# iOS
cp $PAQUETE/ios/Runner/Info.plist                         ios/Runner/Info.plist
cp $PAQUETE/ios/Runner/Base.lproj/LaunchScreen.storyboard ios/Runner/Base.lproj/
mkdir -p ios/Runner/Assets.xcassets/LaunchImage.imageset
cp $PAQUETE/ios/Runner/Assets.xcassets/LaunchImage.imageset/Contents.json \
   ios/Runner/Assets.xcassets/LaunchImage.imageset/
```

### Paso 3 — Instalar dependencias

```bash
flutter pub get
```

Si hay conflictos, eliminar `pubspec.lock` y volver a correr.

### Paso 4 — Generar iconos de la app

```bash
dart run flutter_launcher_icons
```

Genera todos los tamaños de icono Android/iOS a partir del logo Tecno Líder.

### Paso 5 — Generar el splash screen nativo

```bash
dart run flutter_native_splash:create
```

Sincroniza la configuración del bloque `flutter_native_splash:` del pubspec con todos los archivos nativos.

⚠️ **Si modificaste manualmente** los archivos en `res/values*/styles.xml` o el storyboard de iOS, **NO corras este comando** — los sobrescribe.

### Paso 6 — Configurar el signing de Android (release)

Genera el keystore (UNA sola vez en la vida del proyecto — guárdalo como oro):

```bash
keytool -genkey -v -keystore android/app/tecno_lider_keystore.jks \
        -keyalg RSA -keysize 2048 -validity 10000 \
        -alias tecnolider
```

Luego copia y rellena el `key.properties`:

```bash
cp android/key.properties.example android/key.properties
# editar android/key.properties con las claves que pusiste arriba
```

⚠️ **CRÍTICO:** agrega `key.properties` y `*.jks` a tu `.gitignore`. Si pierdes el keystore, no podrás publicar updates en Google Play.

### Paso 7 — iOS (solo si compilas para iOS)

1. Abre `ios/Runner.xcworkspace` en Xcode.
2. Target `Runner` → Signing & Capabilities → configura Team y Bundle ID (`com.tecnolider.tecnoLider`).
3. Activa capabilities: **Background Modes** (Bluetooth, Background fetch, Remote notifications).

### Paso 8 — Configurar la IP del backend

En `lib/main.dart`, busca `_ipFisica` (línea ~700):

```dart
const String _ipFisica = "192.168.1.XXX"; // ← tu IP de LAN
```

### Paso 9 — Configurar valores específicos del negocio

Búscalos rápido con `grep -nE "TODO|XXXXXXX" lib/main.dart`:

| Qué | Placeholder | Notas |
|---|---|---|
| Correo del admin maestro | `tecnolider@gmail.com` | 2 ocurrencias |
| RIF de Tecno Líder C.A. | `J-XXXXXXXX-X` | PDF del contrato FPB |
| Teléfono atención al cliente | `0414-XXXXXXX` | Pie de PDF |
| IP del backend | `_ipFisica` | Línea ~700 |

### Paso 10 — Correr la app

```bash
flutter run                    # dispositivo conectado
flutter build apk --release    # APK Android
flutter build appbundle        # AAB para Google Play (recomendado)
flutter build ios --release    # iOS (requiere Mac + Xcode)
```

---

## 🎨 Branding aplicado

### Paleta (Flutter `AppColors` + Android `colors.xml`)

| Token Flutter | Token Android | Color | Uso |
|---|---|---|---|
| `primaryBlue` | `tecnolider_blue` | `#2E3192` | Color primario, splash, badges |
| `royalBlue` | `tecnolider_blue_dark` | `#1F2270` | AppBar, navegación, sombras |
| `accentYellow` | `tecnolider_yellow` | `#FFC20E` | FAB, highlights, CTA secundario |
| `accentYellowDark` | `tecnolider_yellow_dark` | `#E5A800` | Hover/pressed amarillo |

El **FAB** es amarillo con texto azul royal — refleja el contraste del logo.

### Splash screen
- Fondo azul royal `#2E3192`
- Logo Tecno Líder centrado
- Soporte: Android < 12, Android 12+ (nueva API), modo oscuro, iOS

### Cambios de marca completos

| Antes | Ahora |
|---|---|
| `Brizuela` (título app) | `Tecno Líder` |
| `logo_brizuela_pro.png` | `logo_tecno_lider.jpeg` |
| `SISTEMA BRIZUELA` (drawer) | `SISTEMA TECNO LÍDER` |
| `BRIZUELA CELULAR C.A.` (contratos) | `TECNO LÍDER C.A.` |
| `Contrato Financiado por Brizuela` | `Contrato Financiado por Tecno Líder` |
| `Brizuela App` (Cashea merchant) | `Tecno Líder App` |
| `Brizuela Celular`, `Brizuela 2000` | `Tecno Líder Principal`, `Tecno Líder Sucursal` |
| `brizuela_alertas_v2` (canal Android) | `tecnolider_alertas_v1` |
| `/brizuela/api.php` | `/tecnolider/api.php` |
| `brizuela-app.local` | `tecnolider-app.local` |
| `Contrato_Brizuela_<ci>.pdf` | `Contrato_TecnoLider_<ci>.pdf` |
| RIF `J507066398` hardcoded | Placeholder `J-XXXXXXXX-X` configurable |

---

## 🖨️ Filtro USB (`device_filter.xml`)

Cubre los VID/PID de las marcas más comunes en Venezuela:
- **Epson** (TM-T20, TM-T88)
- **Bixolon** (SRP-270, SRP-350)
- **Star Micronics** (TSP100, TSP143)
- **Xprinter** (XP-58, XP-58IIH, XP-80) — muy comunes en Venezuela
- **Citizen** (CT-S310)
- **HPRT** (TP80x)
- **Genéricos / clones chinos** (CH340, Prolific PL2303, STMicro)

Si una impresora no se detecta, mira su VID/PID en el Administrador de Dispositivos de Windows y agrega la línea correspondiente. Instrucciones detalladas en los comentarios del archivo.

---

## ⚠️ Cosas a tener presentes

1. **Backend separado:** la app es solo el cliente. El servidor PHP en `/tecnolider/api.php` debe existir aparte; no se incluye aquí.

2. **Canal de notificación nuevo:** al renombrar el canal Android, en updates desde la versión vieja el canal viejo quedará huérfano (cosmético, no funcional).

3. **Archivo monolítico:** `main.dart` con 39.5k líneas. Compila bien pero la mantenibilidad sufre. Para una segunda iteración: dividir en módulos.

4. **iOS y `firebase_messaging`:** notificaciones por polling al backend (no push reales) por conflicto entre `firebase_messaging` y `mobile_scanner` en iOS.

5. **Logo en JPEG:** funciona pero para iconos un PNG transparente da mejor resultado en Android adaptativo. Si lo cambias, vuelve a correr los generadores del paso 4 y 5.

6. **HTTP claro:** la app habla con el backend por HTTP. Habilitado en Android (`usesCleartextTraffic="true"`) e iOS (`NSAllowsArbitraryLoads`). Al migrar a HTTPS, deshabilita ambos.

---

## 📞 Soporte rápido

```bash
flutter clean && flutter pub get && flutter run
```

Si Gradle falla por memoria, sube el `Xmx` en `android/gradle.properties`.
