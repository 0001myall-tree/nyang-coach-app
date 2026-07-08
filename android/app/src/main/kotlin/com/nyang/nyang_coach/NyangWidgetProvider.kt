package com.nyang.nyang_coach

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class NyangWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.nyang_widget_layout).apply {
                val rawProgress = widgetData.all["progress"]
                val progress = (rawProgress as? Number)?.toInt() ?: (rawProgress as? String)?.toIntOrNull() ?: 0
                
                val coachMessage = widgetData.getString("coach_message_cat", "오늘도 활기차게 시작해보자냥!") ?: "오늘도 활기차게 시작해보자냥!"
                
                val rawRemaining = widgetData.all["remaining_count"]
                val remainingCount = (rawRemaining as? Number)?.toInt() ?: (rawRemaining as? String)?.toIntOrNull() ?: 0

                setProgressBar(R.id.progress_bar, 100, progress, false)
                setTextViewText(R.id.coach_message, WidgetTextFormatter.formatCoachMessage(coachMessage))
                setTextViewText(R.id.remaining_count_text, WidgetTextFormatter.formatRemainingCount(remainingCount, "#8B7CFF"))
                WidgetResponsiveStyle.apply(context, appWidgetManager, widgetId, this)

                val intentRemaining = Intent(context, MainActivity::class.java).apply {
                    action = "nyang_coach.OPEN_REMAINING_LIST"
                    data = Uri.parse("nyangcoach://widget/cat/tasks_remaining_bottom_sheet")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                    putExtra("route", "tasks_remaining_bottom_sheet")
                    putExtra("coach_id", "cat")
                }
                val pendingRemaining = PendingIntent.getActivity(context, 1003, intentRemaining, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                setOnClickPendingIntent(R.id.remaining_row, pendingRemaining)

                val intentChat = Intent(context, MainActivity::class.java).apply {
                    action = "nyang_coach.OPEN_CHAT"
                    data = Uri.parse("nyangcoach://widget/cat/chat")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                    putExtra("route", "chat")
                    putExtra("coach_id", "cat")
                }
                val pendingChat = PendingIntent.getActivity(context, 1001, intentChat, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                setOnClickPendingIntent(R.id.btn_open_chat, pendingChat)
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
