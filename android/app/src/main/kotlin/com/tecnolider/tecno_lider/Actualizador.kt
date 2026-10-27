package com.tecnolider.tecno_lider

import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.FileProvider
import java.io.File
import java.io.FileInputStream

/**
 * Actualización de la app desde la propia app. Traído de Brizuela (dueño,
 * 10/10/2026: «el sistema OTA es para que se actualice sin otras cosas»;
 * 15/10/2026: tablets Xiaomi con HyperOS).
 *
 * Antes se abría el APK con `OpenFilex` y el instalador de Android pedía
 * «Instalar» SIEMPRE. Con una sesión de `PackageInstaller`:
 *
 *  · Android 12 o más nuevo: la app se actualiza a sí misma SIN preguntar
 *    (`USER_ACTION_NOT_REQUIRED` + permiso UPDATE_PACKAGES_WITHOUT_USER_ACTION).
 *    La primera vez que se instaló a mano Android puede pedir confirmar una
 *    vez más; desde ahí, solo.
 *  · Android 11 o más viejo: Android exige tocar «Instalar». La confirmación
 *    se muestra en cuanto la app está en pantalla, nunca se pierde.
 *
 * El resultado (instalada o el motivo del fallo) queda guardado para que
 * Dart lo lea y lo reporte al servidor.
 *
 * XIAOMI (15/10/2026). Las tablets Redmi Pad SE con HyperOS (Android 16)
 * cancelaban la sesión con «código 3: INSTALL_FAILED_ABORTED: Permission
 * denied» y se quedaban en versiones viejas: HyperOS no deja que una app se
 * actualice sola y su pantalla de seguridad aborta la sesión. Por eso:
 *  · En Xiaomi/Redmi/POCO no se pide la actualización silenciosa: Android
 *    muestra la confirmación normal.
 *  · Si igual la sesión se cancela (código 3), se abre el APK ya descargado
 *    con el instalador clásico —el mismo camino que instalarlo desde el
 *    navegador—, que pide «Instalar».
 */
object InstaladorApk {
    private const val PREFS = "tl_actualizador"
    private const val ACCION = "com.tecnolider.tecno_lider.INSTALACION"
    const val CANAL_AVISO = "tecnolider_actualizaciones"

    /** Confirmación que pidió Android y todavía no se mostró. */
    @Volatile var confirmacionPendiente: Intent? = null

    /** Actividad en pantalla (null si la app está en segundo plano). */
    @Volatile var actividadVisible: Activity? = null

    /** APK que hay que abrir con el instalador clásico (la sesión se canceló). */
    @Volatile var clasicoPendiente: String? = null

    /** Xiaomi, Redmi o POCO: HyperOS/MIUI no acepta la actualización silenciosa. */
    fun esXiaomi(): Boolean {
        val marca = "${Build.MANUFACTURER} ${Build.BRAND}".lowercase()
        return listOf("xiaomi", "redmi", "poco").any { marca.contains(it) }
    }

    fun instalar(contexto: Context, ruta: String) {
        val apk = File(ruta)
        require(apk.isFile && apk.length() > 0) { "No existe el APK descargado" }
        val instalador = contexto.packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
        params.setAppPackageName(contexto.packageName)
        params.setSize(apk.length())
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            params.setInstallReason(PackageManager.INSTALL_REASON_USER)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !esXiaomi()) {
            params.setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
        }
        val id = instalador.createSession(params)
        val sesion = instalador.openSession(id)
        try {
            sesion.openWrite("base.apk", 0, apk.length()).use { salida ->
                FileInputStream(apk).use { it.copyTo(salida, 1 shl 16) }
                sesion.fsync(salida)
            }
            val intento = Intent(contexto, ReceptorInstalacion::class.java).setAction(ACCION)
            var flags = PendingIntent.FLAG_UPDATE_CURRENT
            // El instalador del sistema completa el intent: tiene que ser mutable.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) flags = flags or PendingIntent.FLAG_MUTABLE
            val pendiente = PendingIntent.getBroadcast(contexto, id, intento, flags)
            guardar(contexto, "instalando", "")
            // Para el instalador clásico, si la sesión se cancela.
            contexto.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putString("apk", apk.absolutePath).apply()
            sesion.commit(pendiente.intentSender)
        } catch (e: Exception) {
            sesion.abandon()
            throw e
        } finally {
            sesion.close()
        }
    }

    /**
     * Abre el APK con el instalador clásico de Android (pide «Instalar»).
     * Devuelve false si no se pudo; el error queda guardado.
     */
    fun abrirInstaladorClasico(contexto: Context, ruta: String): Boolean {
        return try {
            val apk = File(ruta)
            require(apk.isFile && apk.length() > 0) { "No está el APK descargado" }
            val uri = FileProvider.getUriForFile(contexto, "${contexto.packageName}.instalador", apk)
            @Suppress("DEPRECATION")
            val abrir = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                putExtra(Intent.EXTRA_NOT_UNKNOWN_SOURCE, true)
            }
            contexto.startActivity(abrir)
            guardar(contexto, "clasico", "Se abrió el instalador clásico")
            true
        } catch (e: Exception) {
            guardar(contexto, "error", "No se pudo abrir el instalador clásico: ${e.message}")
            false
        }
    }

    /** Ruta del último APK que se intentó instalar (para el instalador clásico). */
    fun ultimoApk(contexto: Context): String? =
        contexto.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("apk", null)

    /** Muestra la confirmación de Android, o el instalador clásico, si quedó uno pendiente. */
    fun mostrarPendiente() {
        val act = actividadVisible ?: return
        clasicoPendiente?.let { ruta ->
            clasicoPendiente = null
            act.runOnUiThread { abrirInstaladorClasico(act, ruta) }
            return
        }
        val confirmar = confirmacionPendiente ?: return
        confirmacionPendiente = null
        act.runOnUiThread {
            try {
                act.startActivity(confirmar)
            } catch (e: Exception) {
                guardar(act, "error", "No se pudo abrir la confirmación: ${e.message}")
            }
        }
    }

    fun guardar(contexto: Context, estado: String, detalle: String) {
        contexto.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString("estado", estado)
            .putString("detalle", detalle)
            .putLong("cuando", System.currentTimeMillis())
            .apply()
    }

    /** Último resultado guardado: estado, detalle y cuándo. */
    fun leer(contexto: Context): Map<String, Any?> {
        val p = contexto.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        return mapOf(
            "estado" to p.getString("estado", ""),
            "detalle" to p.getString("detalle", ""),
            "cuando" to p.getLong("cuando", 0L),
        )
    }

    fun limpiar(contexto: Context) {
        contexto.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().clear().apply()
    }

    fun crearCanalAviso(contexto: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = contexto.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CANAL_AVISO) != null) return
        nm.createNotificationChannel(NotificationChannel(
            CANAL_AVISO, "Actualizaciones", NotificationManager.IMPORTANCE_HIGH).apply {
            description = "Avisa cuando Tecno Líder se actualizó"
        })
    }
}

/** FileProvider propio para el instalador clásico (no choca con el de los plugins). */
class ProveedorApk : FileProvider()

/** Resultado de la sesión de instalación. */
class ReceptorInstalacion : BroadcastReceiver() {
    override fun onReceive(contexto: Context, intento: Intent) {
        val estado = intento.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
        val mensaje = intento.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE) ?: ""
        when (estado) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                @Suppress("DEPRECATION")
                val confirmar: Intent? = if (Build.VERSION.SDK_INT >= 33)
                    intento.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                else intento.getParcelableExtra(Intent.EXTRA_INTENT)
                if (confirmar == null) {
                    InstaladorApk.guardar(contexto, "error", "Android pidió confirmar sin pantalla")
                    return
                }
                confirmar.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                InstaladorApk.confirmacionPendiente = confirmar
                InstaladorApk.guardar(contexto, "confirmar", "")
                // Si la app está en pantalla se muestra ya; si no, al volver.
                InstaladorApk.mostrarPendiente()
            }
            PackageInstaller.STATUS_SUCCESS -> InstaladorApk.guardar(contexto, "instalada", "")
            // Código 3: Android (HyperOS en las tablets Xiaomi) canceló la
            // sesión. Se abre el instalador clásico con el mismo APK: en
            // cuanto la app esté en pantalla, o ya mismo si lo está.
            PackageInstaller.STATUS_FAILURE_ABORTED -> {
                val ruta = InstaladorApk.ultimoApk(contexto)
                InstaladorApk.guardar(contexto, "error", "Android: código $estado. $mensaje")
                if (ruta != null) {
                    InstaladorApk.clasicoPendiente = ruta
                    InstaladorApk.mostrarPendiente()
                }
            }
            else -> InstaladorApk.guardar(contexto, "error", "Android: código $estado. $mensaje")
        }
    }
}

/**
 * La app se reemplazó con la versión nueva: Android cierra la anterior y no
 * deja abrir una pantalla desde acá, así que se avisa con una notificación
 * que la abre al tocarla.
 */
class ReceptorActualizada : BroadcastReceiver() {
    override fun onReceive(contexto: Context, intento: Intent) {
        if (intento.action != Intent.ACTION_MY_PACKAGE_REPLACED) return
        InstaladorApk.guardar(contexto, "instalada", "")
        try {
            InstaladorApk.crearCanalAviso(contexto)
            val abrir = contexto.packageManager.getLaunchIntentForPackage(contexto.packageName)
                ?: return
            abrir.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            var flags = PendingIntent.FLAG_UPDATE_CURRENT
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) flags = flags or PendingIntent.FLAG_IMMUTABLE
            val pi = PendingIntent.getActivity(contexto, 4711, abrir, flags)
            val aviso = NotificationCompat.Builder(contexto, InstaladorApk.CANAL_AVISO)
                .setSmallIcon(R.drawable.ic_stat_tecnolider)
                .setContentTitle("Tecno Líder se actualizó")
                .setContentText("Toca para abrir la versión nueva")
                .setContentIntent(pi)
                .setAutoCancel(true)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .build()
            val nm = contexto.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.notify(4711, aviso)
        } catch (_: Exception) {
            // Sin permiso de avisos: la versión nueva igual quedó instalada.
        }
    }
}
