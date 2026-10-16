package com.barsopus.attune

import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test
import org.w3c.dom.Element

/**
 * The drop order at large font scales (spec §3.2, final review I2): the
 * headline keeps its lines; the detail lines sit in a weighted box that clips
 * from the bottom (clock line first, then caption). Structure only: the real
 * rendering is a device check.
 */
class CoupleWidgetLayoutTest {
    private val android = "http://schemas.android.com/apk/res/android"

    private fun byId(file: String): Map<String, Element> {
        val factory = DocumentBuilderFactory.newInstance().apply { isNamespaceAware = true }
        val doc = factory.newDocumentBuilder().parse(File("src/main/res/layout/$file"))
        val all = doc.getElementsByTagName("*")
        return (0 until all.length).map { all.item(it) as Element }
            .filter { it.hasAttributeNS(android, "id") }
            .associateBy { it.getAttributeNS(android, "id").removePrefix("@+id/") }
    }

    private fun Element.attr(name: String) = getAttributeNS(android, name)

    private fun checkLayout(file: String) {
        val v = byId(file)
        val headline = assertNotNullAndGet(v, "couple_headline", file)
        assertEquals("$file headline height", "wrap_content", headline.attr("layout_height"))
        assertEquals("$file headline size on API 24–25", "20sp", headline.attr("textSize"))
        val details = assertNotNullAndGet(v, "couple_details", file)
        assertEquals("$file details height", "0dp", details.attr("layout_height"))
        assertEquals("$file details weight", "1", details.attr("layout_weight"))
        assertEquals("$file details gravity", "top", details.attr("gravity"))
        for (child in listOf("couple_caption", "couple_clock_line")) {
            assertEquals("$file $child inside details", details, v.getValue(child).parentNode)
        }
    }

    private fun assertNotNullAndGet(v: Map<String, Element>, id: String, file: String): Element {
        assertNotNull("$file has $id", v[id])
        return v.getValue(id)
    }

    @Test
    fun smallLayoutClipsDetailsNotTheHeadline() = checkLayout("couple_widget_small.xml")

    @Test
    fun mediumLayoutClipsDetailsNotTheHeadline() = checkLayout("couple_widget_medium.xml")
}
