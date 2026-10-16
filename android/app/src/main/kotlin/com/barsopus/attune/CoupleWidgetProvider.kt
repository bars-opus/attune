// android/app/src/main/kotlin/com/barsopus/attune/CoupleWidgetProvider.kt
package com.barsopus.attune

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.SizeF
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import java.util.Calendar

/**
 * The distance widget (widget spec §3, §6.3). Shows only what the app wrote;
 * never touches the network; no names, places or app words on the card. An
 * alarm at the next change (expiry or midnight) keeps it honest through Doze.
 */
class CoupleWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        render(context, appWidgetManager, appWidgetIds, widgetData)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        render(context, appWidgetManager, intArrayOf(appWidgetId), HomeWidgetPlugin.getData(context))
    }

    override fun onDisabled(context: Context) {
        cancelExpiry(context)
        super.onDisabled(context)
    }

    private fun render(
        context: Context,
        manager: AppWidgetManager,
        ids: IntArray,
        data: SharedPreferences,
    ) {
        val now = System.currentTimeMillis()
        val cal = Calendar.getInstance()
        val today = CoupleWidgetModel.epochDay(
            cal.get(Calendar.YEAR),
            cal.get(Calendar.MONTH) + 1,
            cal.get(Calendar.DAY_OF_MONTH),
        )
        val raw = data.getString(PAYLOAD_KEY, null)
        val view = CoupleWidgetModel.resolve(raw, now, today)
        val map = if (view.showMap) loadMap(context, data.getString(MAP_KEY, null)) else null
        ids.forEach { id -> manager.updateAppWidget(id, build(context, manager, id, view, map)) }
        val next = CoupleWidgetModel.nextChangeMs(raw, now, nextMidnight(cal))
        if (next == null) {
            cancelExpiry(context)
        } else {
            val all = manager.getAppWidgetIds(ComponentName(context, CoupleWidgetProvider::class.java))
            scheduleExpiry(context, all, next)
        }
    }

    private fun build(
        context: Context,
        manager: AppWidgetManager,
        id: Int,
        view: CoupleWidgetView,
        map: Bitmap?,
    ): RemoteViews {
        val small = bind(context, RemoteViews(context.packageName, R.layout.couple_widget_small), view, null, false)
        val medium = bind(context, RemoteViews(context.packageName, R.layout.couple_widget_medium), view, map, true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            return RemoteViews(
                mapOf(
                    SizeF(110f, 110f) to small,
                    SizeF(MEDIUM_MIN_WIDTH_DP, 110f) to medium,
                ),
            )
        }
        val minWidth = manager.getAppWidgetOptions(id).getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
        return if (minWidth >= MEDIUM_MIN_WIDTH_DP) medium else small
    }

    private fun bind(
        context: Context,
        views: RemoteViews,
        view: CoupleWidgetView,
        map: Bitmap?,
        hasMapSlot: Boolean,
    ): RemoteViews = views.apply {
        setOnClickPendingIntent(
            R.id.couple_root,
            HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse(DEEP_LINK)),
        )
        setViewVisibility(R.id.couple_neutral, if (view.neutral) View.VISIBLE else View.GONE)
        // Neutral: no detail box, so the root centres the one line.
        setViewVisibility(R.id.couple_details, if (view.neutral) View.GONE else View.VISIBLE)
        showText(R.id.couple_headline, if (view.neutral) null else view.headline)
        setViewVisibility(R.id.couple_headline_clock, if (view.headlineIsClock) View.VISIBLE else View.GONE)
        showText(R.id.couple_caption, view.caption)
        setViewVisibility(R.id.couple_clock_line, if (view.clockLine) View.VISIBLE else View.GONE)
        view.clockOffsetMinutes?.let { offset ->
            val zone = CoupleWidgetModel.zoneId(offset)
            setString(R.id.couple_headline_clock, "setTimeZone", zone)
            setString(R.id.couple_clock_line, "setTimeZone", zone)
        }
        if (hasMapSlot) {
            if (map != null) {
                setImageViewBitmap(R.id.couple_map, map)
                setViewVisibility(R.id.couple_map, View.VISIBLE)
            } else {
                setViewVisibility(R.id.couple_map, View.GONE)
            }
        }
    }

    private fun RemoteViews.showText(id: Int, text: String?) {
        setViewVisibility(id, if (text == null) View.GONE else View.VISIBLE)
        if (text != null) setTextViewText(id, text)
    }

    /** Decoded small (≤ 480 px) from our own folder only; null on any problem. */
    private fun loadMap(context: Context, path: String?): Bitmap? = try {
        if (!CoupleWidgetModel.isWidgetFile(path, context.filesDir)) {
            null
        } else {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(path, bounds)
            var sample = 1
            while (bounds.outWidth / (sample * 2) >= MAP_MAX_PX) sample *= 2
            BitmapFactory.decodeFile(path, BitmapFactory.Options().apply { inSampleSize = sample })
        }
    } catch (_: Exception) {
        null
    }

    private fun nextMidnight(now: Calendar): Long = (now.clone() as Calendar).apply {
        add(Calendar.DAY_OF_MONTH, 1)
        set(Calendar.HOUR_OF_DAY, 0)
        set(Calendar.MINUTE, 0)
        set(Calendar.SECOND, 0)
        set(Calendar.MILLISECOND, 0)
    }.timeInMillis

    private fun expiryIntent(context: Context, ids: IntArray?): PendingIntent {
        val intent = Intent(context, CoupleWidgetProvider::class.java)
            .setAction(AppWidgetManager.ACTION_APPWIDGET_UPDATE)
        if (ids != null) intent.putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
        return PendingIntent.getBroadcast(
            context,
            EXPIRY_REQUEST,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /** RTC (not a wakeup): fires in Doze maintenance or when the phone wakes,
     * before the home screen is seen; no exact-alarm permission (spec §4.2). */
    private fun scheduleExpiry(context: Context, ids: IntArray, at: Long) {
        context.getSystemService(AlarmManager::class.java)
            ?.setAndAllowWhileIdle(AlarmManager.RTC, at, expiryIntent(context, ids))
    }

    private fun cancelExpiry(context: Context) {
        context.getSystemService(AlarmManager::class.java)?.cancel(expiryIntent(context, null))
    }

    companion object {
        const val PAYLOAD_KEY = "couple_widget_v1"
        const val MAP_KEY = "couple_widget_map"
        const val DEEP_LINK = "attune://planning?tab=map"
        const val MEDIUM_MIN_WIDTH_DP = 250f
        const val MAP_MAX_PX = 480
        const val EXPIRY_REQUEST = 4201
    }
}
