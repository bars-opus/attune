package com.barsopus.attune

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONObject

/** Together "Next" card (Phase 8a): reads what the app wrote; hides what has ended. */
class TogetherWidgetProvider : HomeWidgetProvider() {
  override fun onUpdate(
    context: Context,
    appWidgetManager: AppWidgetManager,
    appWidgetIds: IntArray,
    widgetData: SharedPreferences,
  ) {
    val lines = currentLines(widgetData.getString("together_widget_v1", null), System.currentTimeMillis())
    appWidgetIds.forEach { id ->
      val views = RemoteViews(context.packageName, R.layout.together_widget).apply {
        setOnClickPendingIntent(
          R.id.together_widget_root,
          HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
        )
        bind(this, R.id.line1_title, R.id.line1_label, lines.getOrNull(0))
        bind(this, R.id.line2_title, R.id.line2_label, lines.getOrNull(1))
        setViewVisibility(R.id.together_widget_empty, if (lines.isEmpty()) View.VISIBLE else View.GONE)
      }
      appWidgetManager.updateAppWidget(id, views)
    }
  }

  private fun bind(views: RemoteViews, titleId: Int, labelId: Int, line: Line?) {
    val visibility = if (line == null) View.GONE else View.VISIBLE
    views.setViewVisibility(titleId, visibility)
    views.setViewVisibility(labelId, visibility)
    if (line != null) {
      views.setTextViewText(titleId, line.title)
      views.setTextViewText(labelId, line.label)
    }
  }

  data class Line(val title: String, val label: String, val end: Double)

  companion object {
    fun currentLines(raw: String?, now: Long): List<Line> = try {
      val array = JSONObject(raw ?: return emptyList()).getJSONArray("lines")
      (0 until array.length())
        .map { array.getJSONObject(it) }
        .map { Line(it.getString("title"), it.getString("label"), it.getDouble("end")) }
        .filter { it.end > now }
        .take(2)
    } catch (_: Exception) {
      emptyList()
    }
  }
}
