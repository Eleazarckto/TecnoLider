# Tecno Líder — Publicación en App Store (iPhone/iPad/Mac)

Documento maestro con TODO lo que necesitas para subir la app. Imprime esto
y márcalo paso a paso. Cada sección tiene comandos exactos, validaciones y
los errores más comunes con su solución.

═══════════════════════════════════════════════════════════════════
PREREQUISITOS — VERIFICAR ANTES DE EMPEZAR
═══════════════════════════════════════════════════════════════════

[ ] macOS 14 (Sonoma) o superior
[ ] Xcode 16+ desde App Store (~10GB)
[ ] Cuenta Apple Developer ACTIVA ($99/año pagada)
[ ] Team ID: Y3D33YTV52 (ya configurado)
[ ] Bundle ID elegido: com.tecnolider.tecnoLider (ya configurado)
[ ] Flutter SDK >= 3.24

Para verificar Flutter:
    flutter --version
    flutter doctor

Si flutter doctor reporta problemas con Xcode, ejecuta:
    sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
    sudo xcodebuild -license accept


═══════════════════════════════════════════════════════════════════
PASO 1 — REGISTRAR APP EN APPLE
═══════════════════════════════════════════════════════════════════

A) En developer.apple.com:
   1. Login con tu Apple ID
   2. Certificates, Identifiers & Profiles → Identifiers
   3. Click "+" → App IDs → App
   4. Description:  Tecno Líder POS
      Bundle ID:    Explicit → com.tecnolider.tecnoLider
   5. Capabilities a marcar:
      [ ] Push Notifications  (solo si quieres notificaciones remotas;
                                 si solo locales, NO)
      Sin más capabilities.
   6. Continue → Register

B) En appstoreconnect.apple.com:
   1. My Apps → "+" → New App
   2. Platforms:    iOS  ✓  macOS  ✓
   3. Name:         Tecno Líder POS
   4. Primary Lang: Spanish (Mexico)
   5. Bundle ID:    com.tecnolider.tecnoLider (debe aparecer en lista)
   6. SKU:          tecno-lider-pos
   7. User Access:  Full Access
   8. Create

C) En cPanel (sistemasceccato.com):
   1. Sube politica_privacidad.html a /privacidad/index.html
   2. Verifica que carga: https://sistemasceccato.com/privacidad
   3. Crea página de soporte (puede ser una sola página con contacto):
      /soporte/index.html con tu email y teléfono


═══════════════════════════════════════════════════════════════════
PASO 2 — PREPARAR EL PROYECTO LOCAL EN TU MAC
═══════════════════════════════════════════════════════════════════

1. Descarga el ZIP que te entregué y descomprime en:
   /Users/sistemasceccato/Downloads/TecnoLider-main/

2. Abre Terminal y navega:
   cd /Users/sistemasceccato/Downloads/TecnoLider-main

3. Crea el usuario reviewer en tu BD (para Apple Review):
   Ejecuta en cPanel/phpMyAdmin de sistemasceccato_tecnolider:

   INSERT INTO usuarios
     (nombre, correo, clave, rol, sueldo_base, tienda, gana_comisiones)
   VALUES
     ('Apple Reviewer', 'reviewer@sistemasceccato.com',
      'AppleReviewer2026', 'Dueño', 0, '', 0);

   Verifica que existe:
   SELECT id, nombre, correo, rol FROM usuarios
     WHERE correo = 'reviewer@sistemasceccato.com';

4. Generar iconos automáticamente:
   flutter pub get
   dart run flutter_launcher_icons

   Esto crea automáticamente todos los tamaños de iconos para iOS
   (en ios/Runner/Assets.xcassets/AppIcon.appiconset/) y macOS
   (en macos/Runner/Assets.xcassets/AppIcon.appiconset/).

   Validar que NO tienen alpha channel (causa de rechazo automático):
       sips -g hasAlpha ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png

   Debe decir: hasAlpha: no
   Si dice yes, abre el icono en Vista Previa y exporta como PNG sin
   transparencia (Archivo → Exportar → PNG → desmarca Alpha).


═══════════════════════════════════════════════════════════════════
PASO 3 — INSTALAR PODS Y COMPILAR PARA iOS
═══════════════════════════════════════════════════════════════════

1. Instalar CocoaPods si no lo tienes:
   sudo gem install cocoapods

2. En el proyecto:
   cd ios
   pod install --repo-update
   cd ..

3. Compilar sin firmar (validación):
   flutter clean
   flutter pub get
   flutter build ios --release --no-codesign

   Si falla con error de deployment target, revisar:
     - ios/Podfile línea 1 dice: platform :ios, '13.0'
     - ios/Runner.xcodeproj/project.pbxproj: IPHONEOS_DEPLOYMENT_TARGET = 13.0

4. Abrir el proyecto en Xcode:
   open ios/Runner.xcworkspace
   (Importante: usar .xcworkspace, NO .xcodeproj)


═══════════════════════════════════════════════════════════════════
PASO 4 — CONFIGURAR FIRMA EN XCODE (iOS)
═══════════════════════════════════════════════════════════════════

En Xcode (que abriste arriba):

1. Click en "Runner" en el navegador izquierdo (el proyecto)
2. Target Runner → Signing & Capabilities
3. Verificar:
   [ ] Automatically manage signing ✓ marcado
   [ ] Team: tu cuenta (Eleazar Ceccato — Y3D33YTV52)
   [ ] Bundle Identifier: com.tecnolider.tecnoLider
   [ ] Provisioning Profile: Xcode lo crea automáticamente
4. Si dice "Failed to register bundle identifier":
   - Cierra y abre Xcode
   - O agrega el bundle ID manualmente en developer.apple.com (Paso 1A)


═══════════════════════════════════════════════════════════════════
PASO 5 — PROBAR EN SIMULADOR (CRÍTICO)
═══════════════════════════════════════════════════════════════════

Antes de compilar el IPA, prueba en simulador iPad y iPhone:

1. Abrir simulador:
   open -a Simulator

2. En Xcode: Window → Devices and Simulators → tab "Simulators"
   - Si no aparece iPad Pro 13", click "+" y agrégalo
   - Idem iPhone 16 Pro Max

3. Compilar para simulador:
   flutter run -d "iPad Pro 13-inch"

4. Verificar manualmente en la app:
   [ ] La app abre sin crash
   [ ] Login funciona con reviewer@sistemasceccato.com
   [ ] Puedes ver el menú principal
   [ ] Las pantallas no se ven cortadas en horizontal
   [ ] El POS muestra productos correctamente
   [ ] Los reportes cargan datos

5. Repetir con iPhone:
   flutter run -d "iPhone 16 Pro Max"


═══════════════════════════════════════════════════════════════════
PASO 6 — TOMAR SCREENSHOTS (OBLIGATORIO PARA APP STORE)
═══════════════════════════════════════════════════════════════════

Apple exige screenshots en estos tamaños:

iPhone 6.9" (iPhone 16 Pro Max)   →  1320 × 2868  ← OBLIGATORIO
iPad Pro 13" (M4)                  →  2064 × 2752  ← OBLIGATORIO si soportas iPad
Mac (sin barra de menú)            →  1280 × 800 mínimo  ← OBLIGATORIO si Mac

Para tomar screenshots en simulador:
1. Compilar y abrir la app: flutter run -d "iPhone 16 Pro Max"
2. Cuando estés en la pantalla a capturar:
   Cmd + S (guarda en Escritorio automáticamente)

Para Mac: usar Captura de Pantalla (Cmd+Shift+5) y selecciona la ventana.

Capturas sugeridas (5 pantallas):
  1. Login screen con el logo de Tecno Líder
  2. POS facturando con productos en el carrito
  3. Inventario por tienda
  4. Reporte por vendedor con gráficos
  5. Dashboard de finanzas / Estado de Resultados

REGLAS DE SCREENSHOTS QUE APPLE EXIGE:
[ ] Sin barra de estado borrosa o con hora ficticia
[ ] Sin texto "Beta" o "Test"
[ ] Sin marcos de iPhone agregados con texto promocional
[ ] Sin información personal real visible


═══════════════════════════════════════════════════════════════════
PASO 7 — COMPILAR EL IPA Y SUBIR
═══════════════════════════════════════════════════════════════════

1. Asegúrate de cerrar el simulador y Xcode primero.

2. Comando para compilar IPA listo para App Store:

   flutter clean
   flutter pub get
   cd ios && pod install --repo-update && cd ..
   flutter build ipa --release --export-options-plist=ios/ExportOptions.plist

3. El IPA queda en:
   build/ios/ipa/tecno_lider.ipa

4. Subir el IPA — OPCIÓN A (Transporter, recomendado):
   a) Descarga Transporter del Mac App Store (gratis)
   b) Abrir Transporter → Sign in con tu Apple ID
   c) Arrastra build/ios/ipa/tecno_lider.ipa a la ventana
   d) Click DELIVER
   e) Esperar 5-15 minutos a que aparezca en App Store Connect

5. Subir el IPA — OPCIÓN B (línea de comandos):
   xcrun altool --upload-app \
     -f build/ios/ipa/tecno_lider.ipa \
     -t ios \
     -u eleazarceccato@gmail.com \
     -p APP-SPECIFIC-PASSWORD

   (Generar app-specific password en appleid.apple.com → Sign-In and
    Security → App-Specific Passwords)

6. Verificar en App Store Connect → TestFlight:
   La build aparece "Processing" después de subir. Tarda 10-30 minutos.
   Cuando termina, te llega un email.


═══════════════════════════════════════════════════════════════════
PASO 8 — COMPILAR Y SUBIR LA VERSIÓN macOS
═══════════════════════════════════════════════════════════════════

1. Instalar pods de macOS:
   cd macos
   pod install --repo-update
   cd ..

2. Abrir el proyecto Mac en Xcode:
   open macos/Runner.xcworkspace

3. En Xcode:
   - Click Runner → Target Runner → Signing & Capabilities
   - Automatically manage signing ✓
   - Team: tu cuenta
   - Bundle Identifier: com.tecnolider.tecnoLider
   - Cambiar a "Mac App Store" en la sección "Distribution"

4. Capabilities REQUERIDAS para Mac App Store (ya en entitlements):
   [ ] App Sandbox ✓ (obligatorio)
   [ ] Network: client + server ✓
   [ ] Camera ✓ (para mobile_scanner)
   [ ] Bluetooth ✓ (para impresoras)
   [ ] USB ✓ (para impresoras USB)
   [ ] User Selected File ✓

5. Compilar:
   flutter clean
   flutter pub get
   cd macos && pod install --repo-update && cd ..
   flutter build macos --release

6. En Xcode: Product → Archive
   Esto crea el .pkg listo para Mac App Store.

7. Cuando termina el archive:
   - Click "Distribute App"
   - Mac App Store → Upload
   - Sign in y confirmar
   - Esperar a que termine la subida


═══════════════════════════════════════════════════════════════════
PASO 9 — CONFIGURAR APP STORE CONNECT (METADATA)
═══════════════════════════════════════════════════════════════════

En appstoreconnect.apple.com → My Apps → Tecno Líder POS

A) App Information (info general, NO por versión):
   - Name: Tecno Líder POS
   - Subtitle: Gestión de tienda multi-rol
   - Privacy Policy URL: https://sistemasceccato.com/privacidad
   - Category Primary: Productivity
   - Category Secondary: Business

B) Pricing and Availability:
   - Price: Free
   - Availability: Venezuela (mínimo). Otros opcionales.

C) App Privacy (CRÍTICO):
   Click "Get Started" en la sección Data Collection. Responder:
   - Data Types collected: Email, Name, User ID
   - For each: Used for App Functionality, Linked to User Identity,
                NOT used for tracking
   - Sin datos sensibles, sin tracking

D) Version 1.0 → iOS:
   - Promotional Text (170 chars):
     Sistema integral de punto de venta, inventario, comisiones y
     reportes financieros para tiendas de telefonía y tecnología.
     Multi-rol y multi-tienda.

   - Description (4000 chars): copiar de metadata_app_store.md

   - Keywords (100 chars sin espacios):
     POS,inventario,facturación,tienda,comisiones,IMEI,reportes,negocio,Venezuela,financiamiento

   - Support URL: https://sistemasceccato.com/soporte
   - Marketing URL: (vacío)
   - Screenshots: subir las que tomaste en Paso 6
   - Version Release: Manual

E) App Review Information:
   - Sign-in required: ✓ YES
   - Username: reviewer@sistemasceccato.com
   - Password: AppleReviewer2026
   - Notes (en INGLÉS):
     Tecno Líder is an internal business management app for retail
     electronics stores in Venezuela. Login required.

     Demo credentials provided above. After login:
       1. Select any 'tienda' (store) when prompted
       2. Explore POS, Inventory, Reports and Commissions modules

     The app connects to our private API at sistemasceccato.com
     (HTTPS only). No personal data is collected beyond email and
     display name. No advertising, no third-party tracking, no
     location services. Bluetooth is used only for thermal printers.

     WebView is used ONLY for the Cashea financing SDK checkout flow.
     The rest of the app is 100% native Flutter.

   - Contact Information:
     First name: Eleazar
     Last name: Ceccato
     Phone: [tu número con +58]
     Email: eleazarceccato@gmail.com

F) Export Compliance:
   "Does your app use encryption?" → NO (solo HTTPS estándar)

G) Idem para Version 1.0 → macOS (mismos datos, screenshots de Mac)


═══════════════════════════════════════════════════════════════════
PASO 10 — TESTFLIGHT (PROBAR ANTES DE PRODUCCIÓN)
═══════════════════════════════════════════════════════════════════

1. App Store Connect → TestFlight tab
2. La build aparece después de procesar (5-30 minutos)
3. Click en la build → Aceptar Export Compliance
4. Agregar a un grupo interno (tu propio Apple ID)
5. Instala la app desde la app TestFlight en tu iPhone/iPad
6. Probar al menos 24 horas:
   [ ] Login funciona
   [ ] Crear factura funciona
   [ ] Imprimir por Bluetooth funciona
   [ ] No hay crashes
   [ ] Todas las pantallas se ven bien

7. Si encuentras bugs, arreglar, incrementar build number
   (en pubspec.yaml: 1.0.0+1 → 1.0.0+2) y resubir.


═══════════════════════════════════════════════════════════════════
PASO 11 — SUBMIT FOR REVIEW
═══════════════════════════════════════════════════════════════════

Solo cuando TestFlight funciona perfecto durante 24-48h:

1. App Store Connect → Tu app → Version 1.0
2. Click "Add for Review"
3. Verificar que TODO está completo:
   [ ] Screenshots
   [ ] Descripción
   [ ] Demo account
   [ ] Privacy questionnaire
   [ ] Export compliance
4. Click "Submit for Review"
5. Esperar 24-72 horas para respuesta de Apple


═══════════════════════════════════════════════════════════════════
ERRORES COMUNES Y SOLUCIONES
═══════════════════════════════════════════════════════════════════

ERROR: "Missing privacy manifest for SDK X"
SOLUCIÓN: Actualiza el paquete a su versión más reciente.
          flutter pub upgrade

ERROR: "Invalid signature" o "Code signing failed"
SOLUCIÓN: En Xcode → Signing & Capabilities → "Automatically manage
          signing" UNCHECK y luego CHECK de nuevo. Espera que Xcode
          regenere el provisioning profile.

ERROR: "Bundle identifier not registered"
SOLUCIÓN: Ve a developer.apple.com → Identifiers → registra
          com.tecnolider.tecnoLider manualmente.

ERROR: "Icon contains alpha channel"
SOLUCIÓN: Abre assets/icon/icon_1024.png en Vista Previa, exporta
          como PNG sin Alpha y vuelve a ejecutar dart run
          flutter_launcher_icons.

ERROR: "ITMS-90683: Missing Purpose String in Info.plist"
SOLUCIÓN: Falta un NSUsageDescription. El error te dice cuál.
          Agrégalo al Info.plist con un texto descriptivo.

ERROR: Guideline 2.1 "Demo account doesn't work"
SOLUCIÓN: Verificar que reviewer@sistemasceccato.com existe en la
          BD con rol 'Dueño'. Verificar que el backend responde
          desde fuera de Venezuela (Apple revisa desde USA).

ERROR: Guideline 5.1.1 "Privacy practices unclear"
SOLUCIÓN: Verificar que sistemasceccato.com/privacidad responde
          correctamente desde cualquier país. Verificar que el
          cuestionario de App Privacy coincide con lo que la app
          realmente recolecta.

ERROR: "App rejected for using IDFA without permission"
SOLUCIÓN: Verificar que NO tienes NSUserTrackingUsageDescription
          en Info.plist. Si está, eliminarlo.

ERROR: "App stops responding after launch" (iPad horizontal)
SOLUCIÓN: Probar manualmente en simulador iPad Pro 13". Si la UI
          se rompe en horizontal, agregar LayoutBuilder para
          adaptar el layout a pantallas grandes.


═══════════════════════════════════════════════════════════════════
SI APPLE RECHAZA
═══════════════════════════════════════════════════════════════════

1. Lee el mensaje completo en Resolution Center
2. Identifica la Guideline mencionada
3. Responde EN INGLÉS con explicación clara
4. Si requiere cambios: arregla, incrementa build number, resube
5. Una vez aprobada, queda en estado "Pending Developer Release"
   o se publica automáticamente según tu configuración


═══════════════════════════════════════════════════════════════════
LISTA RÁPIDA DE COMANDOS
═══════════════════════════════════════════════════════════════════

# Setup inicial
flutter pub get
dart run flutter_launcher_icons
cd ios && pod install --repo-update && cd ..

# Probar en simulador iPad
flutter run -d "iPad Pro 13-inch"

# Probar en simulador iPhone
flutter run -d "iPhone 16 Pro Max"

# Compilar IPA para App Store
flutter clean && flutter pub get
flutter build ipa --release --export-options-plist=ios/ExportOptions.plist
# El IPA queda en build/ios/ipa/tecno_lider.ipa

# Compilar macOS para Mac App Store
cd macos && pod install --repo-update && cd ..
flutter build macos --release
# Luego en Xcode: Product → Archive → Distribute App → Mac App Store

# Re-compilar tras cambio (incrementando build):
# Editar pubspec.yaml: 1.0.0+1 → 1.0.0+2
flutter clean && flutter pub get
flutter build ipa --release --export-options-plist=ios/ExportOptions.plist
