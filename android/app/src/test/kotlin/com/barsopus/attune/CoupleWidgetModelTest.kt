// android/app/src/test/kotlin/com/barsopus/attune/CoupleWidgetModelTest.kt
package com.barsopus.attune

import java.io.File
import java.nio.file.Files
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Mirrors Dart's resolveCoupleWidget through the shared vectors (widget spec §8). */
class CoupleWidgetModelTest {
    private val fixture = JSONObject(
        File("../../test/features/couple_map/widget/fixtures/couple_widget_vectors.json").readText(),
    )
    private val nowMs = fixture.getLong("nowMs")
    private val today = fixture.getString("today").split("-").let {
        CoupleWidgetModel.epochDay(it[0].toInt(), it[1].toInt(), it[2].toInt())
    }

    private fun JSONObject.str(key: String): String? = if (isNull(key)) null else getString(key)

    @Test
    fun matchesTheDartVectors() {
        val vectors = fixture.getJSONArray("vectors")
        assertTrue(vectors.length() >= 20)
        for (i in 0 until vectors.length()) {
            val v = vectors.getJSONObject(i)
            val e = v.getJSONObject("expect")
            val name = v.getString("name")
            val got = CoupleWidgetModel.resolve(v.str("payload"), nowMs, today)
            assertEquals(name, e.str("headline"), got.headline)
            assertEquals(name, e.getBoolean("headlineIsClock"), got.headlineIsClock)
            assertEquals(name, e.str("caption"), got.caption)
            assertEquals(name, e.getBoolean("clockLine"), got.clockLine)
            assertEquals(
                name,
                if (e.isNull("clockOffsetMinutes")) null else e.getInt("clockOffsetMinutes"),
                got.clockOffsetMinutes,
            )
            assertEquals(name, e.getBoolean("neutral"), got.neutral)
            assertEquals(name, e.getBoolean("showMap"), got.showMap)
        }
    }

    @Test
    fun neutralCopyMatchesDart() {
        assertEquals(fixture.getString("neutralHeadline"), CoupleWidgetModel.NEUTRAL_HEADLINE)
    }

    @Test
    fun epochDays() {
        assertEquals(0L, CoupleWidgetModel.epochDay(1970, 1, 1))
        assertEquals(20742L, CoupleWidgetModel.epochDay(2026, 10, 16))
        assertEquals(19782L, CoupleWidgetModel.epochDay(2024, 2, 29))
    }

    @Test
    fun nextChangeIsTheEarlierOfExpiryAndMidnight() {
        val both = """{"v":1,"validUntilMs":5000,"reunionDate":"2026-10-28"}"""
        assertEquals(5000L, CoupleWidgetModel.nextChangeMs(both, 1000, 9000))
        val late = """{"v":1,"validUntilMs":9000,"reunionDate":"2026-10-28"}"""
        assertEquals(5000L, CoupleWidgetModel.nextChangeMs(late, 1000, 5000))
        assertNull(CoupleWidgetModel.nextChangeMs("""{"v":1}""", 1000, 5000))
        assertNull(CoupleWidgetModel.nextChangeMs("""{"v":1,"validUntilMs":500}""", 1000, 5000))
        assertNull(CoupleWidgetModel.nextChangeMs("{", 1000, 5000))
        assertNull(CoupleWidgetModel.nextChangeMs(null, 1000, 5000))
    }

    @Test
    fun zoneIdsForTextClock() {
        assertEquals("GMT+05:30", CoupleWidgetModel.zoneId(330))
        assertEquals("GMT-03:30", CoupleWidgetModel.zoneId(-210))
        assertEquals("GMT+00:00", CoupleWidgetModel.zoneId(0))
        assertEquals("GMT+14:00", CoupleWidgetModel.zoneId(840))
    }

    @Test
    fun onlyFilesInsideOurWidgetFolderAreRead() {
        val files = Files.createTempDirectory("files").toFile()
        val folder = File(files, "home_widget").apply { mkdirs() }
        val map = File(folder, "couple_widget_map.png").apply { writeBytes(byteArrayOf(1)) }
        assertTrue(CoupleWidgetModel.isWidgetFile(map.path, files))
        assertFalse(CoupleWidgetModel.isWidgetFile(File(folder, "missing.png").path, files))
        assertFalse(CoupleWidgetModel.isWidgetFile(File(files, "elsewhere.png").apply { writeBytes(byteArrayOf(1)) }.path, files))
        assertFalse(CoupleWidgetModel.isWidgetFile("${folder.path}/../elsewhere.png", files))
        assertFalse(CoupleWidgetModel.isWidgetFile(null, files))
    }
}
