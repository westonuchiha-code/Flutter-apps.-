package com.westonuchiha.sprite_pet

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray

/**
 * The pet on the home screen. The app saves (via home_widget) a schedule of
 * moods for the next 24 hours and four PNG frames per mood; this picks the
 * entry for "now" each time the widget updates (scheduled every half hour,
 * and whenever the app or a button changes something).
 */
class PetWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        var key: String? = null
        var status = "Open Sprite Pet once"
        try {
            val schedule = JSONArray(widgetData.getString("pet_schedule", "[]"))
            val now = System.currentTimeMillis()
            for (i in 0 until schedule.length()) {
                val entry = schedule.getJSONArray(i)
                if (i == 0 || entry.getLong(0) <= now) {
                    key = entry.getString(1)
                    status = entry.getString(2)
                } else {
                    break
                }
            }
        } catch (e: Exception) {
            // No schedule yet.
        }
        val frames = try {
            JSONArray(widgetData.getString("pet_frames_$key", "[]"))
        } catch (e: Exception) {
            JSONArray()
        }
        val frameIds = intArrayOf(R.id.pet_frame0, R.id.pet_frame1, R.id.pet_frame2, R.id.pet_frame3)

        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.pet_widget)
            for (i in frameIds.indices) {
                val path = if (frames.length() > 0) frames.optString(i % frames.length(), "") else ""
                val bitmap = if (path.isNotEmpty()) BitmapFactory.decodeFile(path) else null
                if (bitmap != null) views.setImageViewBitmap(frameIds[i], bitmap)
                views.setOnClickPendingIntent(
                    frameIds[i],
                    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
                )
            }
            views.setTextViewText(R.id.pet_status, status)
            views.setOnClickPendingIntent(
                R.id.pet_feed,
                HomeWidgetBackgroundIntent.getBroadcast(context, Uri.parse("spritepet://feed")),
            )
            views.setOnClickPendingIntent(
                R.id.pet_pet,
                HomeWidgetBackgroundIntent.getBroadcast(context, Uri.parse("spritepet://pet")),
            )
            views.setOnClickPendingIntent(
                R.id.pet_play,
                HomeWidgetBackgroundIntent.getBroadcast(context, Uri.parse("spritepet://play")),
            )
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
