package de.mcbuchi.pilzbuddy

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.InputStream
import java.util.zip.GZIPInputStream

/**
 * Liest, warum die App beim letzten Mal beendet wurde (Issue #147).
 *
 * Android führt seit Version 11 selbst Buch darüber, und eine App darf ihre
 * EIGENEN Einträge ohne jede Berechtigung lesen. Das schließt die Lücke, die
 * `error_reports` prinzipbedingt hat: Dort landet nur, was die App überlebt
 * — ein ANR oder Absturz hinterlässt nichts. Genau deshalb blieb #142
 * unsichtbar, bis jemand ein USB-Kabel angesteckt hat.
 *
 * Bewusst zwei Methoden statt einer: Die Übersicht ist billig, der
 * ANR-Thread-Dump ist es nicht (Rohdatei ~1,8 MB). Dart holt ihn nur für
 * Einträge, die es noch nicht gemeldet hat.
 */
class MainActivity : FlutterActivity() {

    private companion object {
        const val CHANNEL = "de.mcbuchi.pilzbuddy/exit_info"

        /** Update der GitHub-APK: fertige Datei an den System-Installer geben. */
        const val INSTALL_CHANNEL = "de.mcbuchi.pilzbuddy/apk_install"

        /**
         * Genug für den Haupt-Thread — und zugleich die Grenze der Spalte
         * `stack`. Vorher standen hier 6000: `ErrorReportRepository` schnitt
         * danach auf 4000 ab, die 2000 Zeichen dazwischen gingen still
         * verloren. Wer mehr braucht (etwa weitere Threads), erweitert
         * beides zusammen — die Spalte per patch_NNN.
         */
        const val TRACE_CHARS = 4000

        /** Obergrenze beim Lesen, damit ein Riesen-Dump nichts blockiert. */
        const val TRACE_BYTES = 4 * 1024 * 1024
    }

    /**
     * Legt den Benachrichtigungs-Kanal an, auf den das Manifest verweist
     * (`default_notification_channel_id`, #277).
     *
     * Ab Android 8 braucht jede Benachrichtigung einen Kanal. Fehlt der im
     * Manifest genannte, weicht FCM still auf einen eigenen aus — und der
     * ist so leise, dass die Meldung nur als Symbol in der Statusleiste
     * landet, ohne Banner. Genau so am 2026-08-12 auf dem Pixel gesehen,
     * während das Nachbarprojekt mit eigenem Kanal ein Banner zeigte.
     *
     * **IMPORTANCE_HIGH ist eine Einbahnstraße.** Android merkt sich die
     * Stufe beim ERSTEN Anlegen; ein späteres Ändern hier erreicht
     * bestehende Installationen nicht mehr, dafür bräuchte es eine neue
     * Kanal-ID. Deshalb bewusst hoch angesetzt: Herunterdrehen kann der
     * Nutzer selbst in den Systemeinstellungen, hochdrehen nicht.
     *
     * Hier statt in Dart, weil der Kanal auch dann stehen muss, wenn eine
     * Meldung eintrifft, ohne dass jemand die App geöffnet hat. Das
     * Anlegen ist idempotent — ein vorhandener Kanal bleibt unverändert,
     * samt allem, was der Nutzer daran verstellt hat.
     */
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            getString(R.string.notification_channel_id),
            getString(R.string.notification_channel_name),
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = getString(R.string.notification_channel_description)
        }
        getSystemService(NotificationManager::class.java)
            .createNotificationChannel(channel)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "exitReasons" ->
                        result.success(exitReasons(call.argument<Int>("limit") ?: 10))
                    "exitTrace" ->
                        result.success(exitTrace(call.argument<Long>("timestamp") ?: 0L))
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, INSTALL_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canInstall" -> result.success(canInstall())
                    "openInstallSettings" -> {
                        openInstallSettings()
                        result.success(null)
                    }
                    "install" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrEmpty()) {
                            result.error("no_path", "Pfad fehlt", null)
                        } else {
                            installApk(path, result)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Darf die App eine APK installieren?
     *
     * Ab Android 8 hängt das an einer Freigabe pro App („Unbekannte Apps
     * installieren"). Darunter genügt die Manifest-Berechtigung, deshalb dort
     * immer true — `canRequestPackageInstalls` gibt es erst ab API 26, und
     * minSdk ist 24.
     */
    private fun canInstall(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            packageManager.canRequestPackageInstalls()
        } else {
            true
        }

    /** Systemeinstellung für genau diese App öffnen, nicht die globale Liste. */
    private fun openInstallSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        startActivity(
            Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:$packageName"),
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
    }

    /**
     * Übergibt die geladene Datei dem System-Installer.
     *
     * Über einen FileProvider statt `file://`: Ab Android 7 wirft eine
     * herausgereichte Datei-URI eine FileUriExposedException, und der
     * Installer läuft in einem fremden Prozess — er braucht die per
     * `FLAG_GRANT_READ_URI_PERMISSION` erteilte Leseerlaubnis.
     *
     * Installiert wird NICHT still: Das System fragt, die App entscheidet
     * nichts allein. Genau deshalb reicht REQUEST_INSTALL_PACKAGES und es
     * braucht kein INSTALL_PACKAGES (Signatur-Berechtigung, siehe #88).
     */
    private fun installApk(path: String, result: MethodChannel.Result) {
        val file = File(path)
        if (!file.exists()) {
            result.error("missing_file", "Datei nicht gefunden: $path", null)
            return
        }
        try {
            val uri = FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                file,
            )
            startActivity(
                Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(uri, "application/vnd.android.package-archive")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
            )
            result.success(true)
        } catch (e: Exception) {
            // Dart fällt daraufhin auf den Browser-Download zurück.
            result.error("install_failed", e.message, null)
        }
    }

    /** Übersicht ohne Thread-Dump — billig genug für jeden App-Start. */
    private fun exitReasons(limit: Int): List<Map<String, Any?>> {
        val infos = historicalExits(limit) ?: return emptyList()
        return infos.map { info ->
            mapOf(
                "timestamp" to info.timestamp,
                "reason" to info.reason,
                "reasonName" to reasonName(info.reason),
                "description" to info.description,
                "importance" to info.importance,
                // getRss() und getPss() liefern BEREITS kB. Hier stand ein
                // zusätzliches / 1024, und AppExit.summary teilte danach
                // noch einmal für seine MB-Anzeige — ein 1,9-GB-Prozess kam
                // damit als "RSS 2 MB" an, alles unter einem halben GB als
                // "RSS 0 MB". Genau das ließ in #151 den Speicher als
                // Ursache ausscheiden, bevor er je gemessen war.
                "rssKb" to info.rss,
                "pssKb" to info.pss,
                // Nur bei ANR liefert Android überhaupt einen Dump.
                "hasTrace" to (info.reason == ApplicationExitInfo.REASON_ANR),
            )
        }
    }

    /**
     * Der Haupt-Thread-Abschnitt des Dumps zu einem Eintrag, oder null.
     *
     * Nur der Haupt-Thread: Bei #142 stand dort alles Nötige (nativ,
     * rechnend, an einer Mutex), und die vollständigen 26 Threads passen
     * weder in die Spalte noch in einen Wochendigest.
     */
    private fun exitTrace(timestamp: Long): String? {
        val info = historicalExits(20)?.firstOrNull { it.timestamp == timestamp }
            ?: return null
        if (info.reason != ApplicationExitInfo.REASON_ANR) return null
        val dump = try {
            info.traceInputStream?.use { readTrace(it) }
        } catch (e: Exception) {
            // Der Dump ist ein Extra. Scheitert er, ist der Eintrag selbst
            // immer noch die halbe Antwort — deshalb hier nicht werfen.
            null
        } ?: return null
        return mainThreadSection(dump)
    }

    private fun historicalExits(limit: Int): List<ApplicationExitInfo>? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null
        return try {
            val manager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            manager.getHistoricalProcessExitReasons(packageName, 0, limit)
        } catch (e: Exception) {
            null
        }
    }

    /** Android liefert den ANR-Dump gzip-gepackt; erkannt an der Signatur. */
    private fun readTrace(stream: InputStream): String {
        val raw = ByteArrayOutputStream().use { buffer ->
            val chunk = ByteArray(64 * 1024)
            var total = 0
            while (total < TRACE_BYTES) {
                val read = stream.read(chunk)
                if (read <= 0) break
                buffer.write(chunk, 0, read)
                total += read
            }
            buffer.toByteArray()
        }
        val gzipped = raw.size > 1 &&
            raw[0] == 0x1f.toByte() && raw[1] == 0x8b.toByte()
        return if (gzipped) {
            GZIPInputStream(raw.inputStream()).use { it.readBytes().decodeToString() }
        } else {
            raw.decodeToString()
        }
    }

    private fun mainThreadSection(dump: String): String {
        val start = dump.indexOf("\"main\"")
        if (start < 0) return dump.take(TRACE_CHARS)
        val end = dump.indexOf("\n\n", start)
        val section = if (end > start) dump.substring(start, end) else dump.substring(start)
        return section.take(TRACE_CHARS)
    }

    private fun reasonName(reason: Int): String = when (reason) {
        ApplicationExitInfo.REASON_ANR -> "ANR"
        ApplicationExitInfo.REASON_CRASH -> "CRASH"
        ApplicationExitInfo.REASON_CRASH_NATIVE -> "CRASH_NATIVE"
        ApplicationExitInfo.REASON_LOW_MEMORY -> "LOW_MEMORY"
        ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE -> "EXCESSIVE_RESOURCE_USAGE"
        ApplicationExitInfo.REASON_SIGNALED -> "SIGNALED"
        ApplicationExitInfo.REASON_DEPENDENCY_DIED -> "DEPENDENCY_DIED"
        ApplicationExitInfo.REASON_INITIALIZATION_FAILURE -> "INITIALIZATION_FAILURE"
        ApplicationExitInfo.REASON_PERMISSION_CHANGE -> "PERMISSION_CHANGE"
        ApplicationExitInfo.REASON_USER_REQUESTED -> "USER_REQUESTED"
        ApplicationExitInfo.REASON_USER_STOPPED -> "USER_STOPPED"
        ApplicationExitInfo.REASON_EXIT_SELF -> "EXIT_SELF"
        ApplicationExitInfo.REASON_OTHER -> "OTHER"
        else -> "UNKNOWN_$reason"
    }
}
