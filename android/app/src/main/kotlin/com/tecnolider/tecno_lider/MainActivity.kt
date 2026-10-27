package com.tecnolider.tecno_lider

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Actualizador (traído de Brizuela): el canal `tl/instalador` deja a Dart
 * saber si la app puede instalar APKs, llevar al usuario al interruptor
 * «Permitir desde esta fuente» e instalar con PackageInstaller
 * (Actualizador.kt). Ver lib/actualizador.dart.
 */
class MainActivity : FlutterActivity() {

    // El actualizador muestra la confirmación de Android solo con la app en
    // pantalla (desde segundo plano Android no deja abrirla).
    override fun onResume() {
        super.onResume()
        InstaladorApk.actividadVisible = this
        InstaladorApk.mostrarPendiente()
    }

    override fun onPause() {
        if (InstaladorApk.actividadVisible === this) InstaladorApk.actividadVisible = null
        super.onPause()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tl/instalador")
            .setMethodCallHandler { llamada, resultado ->
                when (llamada.method) {
                    "puedeInstalar" -> resultado.success(
                        Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                            packageManager.canRequestPackageInstalls())
                    "abrirPermiso" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            try {
                                startActivity(Intent(
                                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                    Uri.parse("package:$packageName")))
                                resultado.success(true)
                            } catch (e: Exception) {
                                resultado.success(false)
                            }
                        } else {
                            resultado.success(true)
                        }
                    }
                    // Instala el APK descargado con PackageInstaller (ver
                    // Actualizador.kt). Copiar el APK no va en el hilo de la
                    // pantalla.
                    "instalar" -> {
                        val ruta = llamada.argument<String>("ruta") ?: ""
                        val principal = Handler(Looper.getMainLooper())
                        Thread {
                            try {
                                InstaladorApk.instalar(applicationContext, ruta)
                                principal.post { resultado.success(true) }
                            } catch (e: Exception) {
                                InstaladorApk.guardar(applicationContext, "error",
                                    "No se pudo instalar: ${e.message}")
                                principal.post { resultado.error("INSTALAR", e.message, null) }
                            }
                        }.start()
                    }
                    "resultado" -> resultado.success(InstaladorApk.leer(applicationContext))
                    "limpiarResultado" -> {
                        InstaladorApk.limpiar(applicationContext)
                        resultado.success(true)
                    }
                    "equipo" -> resultado.success(mapOf(
                        "modelo" to "${Build.MANUFACTURER} ${Build.MODEL}".trim(),
                        "android" to Build.VERSION.SDK_INT,
                    ))
                    else -> resultado.notImplemented()
                }
            }
    }
}
