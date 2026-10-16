// android/app/src/main/kotlin/com/barsopus/attune/CoupleWidgetModel.kt
package com.barsopus.attune

import java.io.File
import java.util.Locale
import org.json.JSONObject

/**
 * What the distance widget shows (widget spec §3.1). Mirrors Dart's
 * resolveCoupleWidget; the live clock is a TextClock, so only its offset and
 * slot are returned. Pure: unit tested on the JVM against the shared vectors.
 */
data class CoupleWidgetView(
    val headline: String?,
    val headlineIsClock: Boolean,
    val caption: String?,
    val clockLine: Boolean,
    val clockOffsetMinutes: Int?,
    val neutral: Boolean,
    val showMap: Boolean,
)

object CoupleWidgetModel {
    const val NEUTRAL_HEADLINE = "Nothing to show yet"

    private val NEUTRAL = CoupleWidgetView(NEUTRAL_HEADLINE, false, null, false, null, true, false)

    private class Payload(
        val headline: String?,
        val headlineIsClock: Boolean,
        val caption: String?,
        val clockOffsetMinutes: Int?,
        val clockLine: Boolean,
        val validUntilMs: Long?,
        val reunionDate: String?,
    )

    private fun JSONObject.text(key: String): String? = if (has(key) && !isNull(key)) getString(key) else null

    private fun parse(raw: String?): Payload? = try {
        if (raw == null) {
            null
        } else {
            val o = JSONObject(raw)
            if ((o.opt("v") as? Int) != 1) {
                null
            } else {
                Payload(
                    headline = o.text("headline"),
                    headlineIsClock = o.optBoolean("headlineIsClock", false),
                    caption = o.text("caption"),
                    clockOffsetMinutes = if (o.has("clockOffsetMinutes")) o.getInt("clockOffsetMinutes") else null,
                    clockLine = o.optBoolean("clockLine", false),
                    validUntilMs = if (o.has("validUntilMs")) o.getLong("validUntilMs") else null,
                    reunionDate = o.text("reunionDate"),
                )
            }
        }
    } catch (_: Exception) {
        null
    }

    /** Days since 1970-01-01 for a civil date (Hinnant); no java.time on minSdk 24. */
    fun epochDay(year: Int, month: Int, day: Int): Long {
        val y = if (month <= 2) year - 1 else year
        val era = (if (y >= 0) y else y - 399) / 400
        val yoe = y - era * 400
        val mp = (month + 9) % 12
        val doy = (153 * mp + 2) / 5 + day - 1
        val doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097L + doe - 719468
    }

    private fun epochDay(date: String): Long? {
        val parts = date.split("-")
        if (parts.size != 3) return null
        val y = parts[0].toIntOrNull() ?: return null
        val m = parts[1].toIntOrNull() ?: return null
        val d = parts[2].toIntOrNull() ?: return null
        return epochDay(y, m, d)
    }

    private fun countdown(days: Long) = when (days) {
        0L -> "Together today"
        1L -> "Together tomorrow"
        else -> "$days days until you're together"
    }

    fun resolve(raw: String?, nowMs: Long, today: Long): CoupleWidgetView {
        val p = parse(raw) ?: return NEUTRAL
        val live = p.validUntilMs != null && p.validUntilMs > nowMs
        val days = p.reunionDate?.let { epochDay(it) }?.let { it - today }?.takeIf { it >= 0 }
        val off = p.clockOffsetMinutes
        val clockLine = p.clockLine && off != null
        if (live) {
            if (days != null) {
                return CoupleWidgetView(countdown(days), false, p.caption, clockLine, if (clockLine) off else null, false, true)
            }
            if (p.headlineIsClock && off != null) {
                return CoupleWidgetView(null, true, p.caption, false, off, false, true)
            }
            if (p.headline != null) {
                return CoupleWidgetView(p.headline, false, p.caption, clockLine, if (clockLine) off else null, false, true)
            }
        }
        if (days != null) {
            return if (days <= 1) {
                CoupleWidgetView(countdown(days), false, null, false, null, false, false)
            } else {
                CoupleWidgetView("$days days", false, "until you're together", false, null, false, false)
            }
        }
        return NEUTRAL
    }

    /** When the view next changes by itself: the distance expiring, or local
     * midnight while a reunion counts down (spec §4.2). */
    fun nextChangeMs(raw: String?, nowMs: Long, nextMidnightMs: Long): Long? {
        val p = parse(raw) ?: return null
        val candidates = mutableListOf<Long>()
        p.validUntilMs?.takeIf { it > nowMs }?.let { candidates += it }
        if (p.reunionDate != null) candidates += nextMidnightMs
        return candidates.minOrNull()
    }

    /** "GMT+05:30": a TextClock zone id for a fixed offset. */
    fun zoneId(offsetMinutes: Int): String {
        val sign = if (offsetMinutes < 0) "-" else "+"
        val abs = kotlin.math.abs(offsetMinutes)
        return String.format(Locale.ROOT, "GMT%s%02d:%02d", sign, abs / 60, abs % 60)
    }

    /** Only an existing file inside our own home_widget folder (spec §4.4, checklist 2.1). */
    fun isWidgetFile(path: String?, filesDir: File): Boolean = try {
        if (path == null) {
            false
        } else {
            val file = File(path).canonicalFile
            val folder = File(filesDir, "home_widget").canonicalFile
            file.isFile && file.parentFile == folder
        }
    } catch (_: Exception) {
        false
    }
}
