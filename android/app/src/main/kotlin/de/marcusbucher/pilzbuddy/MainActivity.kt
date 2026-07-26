package de.marcusbucher.pilzbuddy

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
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
        const val CHANNEL = "de.marcusbucher.pilzbuddy/exit_info"

        /** Genug für den Haupt-Thread; das Schema erlaubt 4000 Zeichen. */
        const val TRACE_CHARS = 6000

        /** Obergrenze beim Lesen, damit ein Riesen-Dump nichts blockiert. */
        const val TRACE_BYTES = 4 * 1024 * 1024
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
                "rssKb" to info.rss / 1024,
                "pssKb" to info.pss / 1024,
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
