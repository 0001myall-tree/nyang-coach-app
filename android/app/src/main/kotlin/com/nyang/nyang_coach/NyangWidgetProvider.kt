package com.nyang.nyang_coach

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.view.Gravity
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class NyangWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.nyang_widget_layout).apply {
                val rawProgress = widgetData.all["progress"]
                val progress = ((rawProgress as? Number)?.toInt() ?: (rawProgress as? String)?.toIntOrNull() ?: 0).coerceIn(0, 100)

                val scheduleTime = widgetData.getString("widget_schedule_time", "")?.trim().orEmpty()
                val scheduleTitle = widgetData.getString("widget_schedule_title", "")?.trim().orEmpty()
                val hasTimedSchedule = scheduleTime.isNotEmpty() && scheduleTitle.isNotEmpty()

                val rawRemaining = widgetData.all["remaining_count"]
                val remainingCount = (rawRemaining as? Number)?.toInt() ?: (rawRemaining as? String)?.toIntOrNull() ?: 0

                setImageViewResource(
                    R.id.mini_cat_image,
                    when {
                        progress > 80 -> R.drawable.iphonecatwidget3
                        progress > 30 -> R.drawable.iphonecatwidget2
                        else -> R.drawable.iphonecatwidget1
                    }
                )
                setTextViewText(
                    R.id.mini_info_text,
                    if (hasTimedSchedule) {
                        WidgetTextFormatter.formatMiniScheduleMessage(scheduleTime, scheduleTitle, "#8B7CFF")
                    } else {
                        WidgetTextFormatter.formatMiniRemainingCount(remainingCount, "#8B7CFF")
                    }
                )
                setInt(
                    R.id.mini_info_text,
                    "setGravity",
                    if (hasTimedSchedule) Gravity.START or Gravity.CENTER_VERTICAL else Gravity.CENTER
                )
                WidgetResponsiveStyle.applyMini(context, appWidgetManager, widgetId, this)

                val intentRemaining = Intent(context, MainActivity::class.java).apply {
                    action = "nyang_coach.OPEN_TASKS"
                    data = Uri.parse("nyangcoach://widget/cat/tasks")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                    putExtra("route", "tasks")
                    putExtra("coach_id", "cat")
                }
                val pendingRemaining = PendingIntent.getActivity(context, 1003, intentRemaining, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                setOnClickPendingIntent(R.id.widget_root, pendingRemaining)
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
