import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// ── FIRMA DE RELEASE ────────────────────────────────────────────
// Las credenciales viven en android/key.properties, FUERA del
// control de versiones. Si el archivo no esta (por ejemplo en una
// maquina nueva o en CI sin secretos), el build cae a la firma de
// depuracion como antes, pero ese APK NO sirve para actualizar los
// equipos: Android rechaza instalar encima una firma distinta.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hayFirmaRelease = keystorePropertiesFile.exists()
if (hayFirmaRelease) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.tecnolider.tecno_lider"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Desactivamos desugaring si no hay librerías de Java 8+ pesadas que lo requieran explícitamente, 
        // ya que desincroniza las referencias de FlutterActivity en Kotlin.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.tecnolider.tecno_lider"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hayFirmaRelease) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hayFirmaRelease) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

dependencies {
    // Requerido por desugaring para flutter_local_notifications
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
    
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("androidx.core:core-splashscreen:1.0.1")
}

flutter {
    source = "../.."
}