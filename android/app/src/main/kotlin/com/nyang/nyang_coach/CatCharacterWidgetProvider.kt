package com.coscene.nyangcoach

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class CatCharacterWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.cat_character_widget_layout).apply {
                val displayKind = widgetData.getString("character_widget_kind", "cheer")?.trim().orEmpty()
                val status = widgetData.getString("character_widget_status", "")?.trim().orEmpty()
                val title = widgetData.getString("character_widget_title", "")?.trim().orEmpty()
                val progress = NyangWidgetMood.readInt(widgetData, "progress").coerceIn(0, 100)
                val pawCount = NyangWidgetMood.readInt(widgetData, "character_widget_paws").coerceIn(0, 5)
                val showsStatusRow = status.isNotEmpty() && (displayKind == "timed" || displayKind == "core" || displayKind == "in_progress")
                val showsMissYouMessage = displayKind != "timed" && NyangWidgetMood.isAwayOverDay(widgetData)

                if (showsMissYouMessage) {
                    setViewVisibility(R.id.cat_character_status_row, View.GONE)
                    setViewVisibility(R.id.cat_character_paw_row, View.GONE)
                    setTextViewText(R.id.cat_character_text, "집사,\n보고싶다옹....")
                } else {
                    if (showsStatusRow) {
                        setViewVisibility(R.id.cat_character_status_row, View.VISIBLE)
                        setTextViewText(R.id.cat_character_status_text, status)
                        setImageViewResource(
                            R.id.cat_character_status_icon,
                            when (displayKind) {
                                "core" -> R.drawable.ic_fa_star_widget
                                "in_progress" -> R.drawable.ic_fa_rotate_widget
                                else -> R.drawable.ic_fa_clock
                            }
                        )
                    } else {
                        setViewVisibility(R.id.cat_character_status_row, View.GONE)
                    }

                    setTextViewText(
                        R.id.cat_character_text,
                        title.ifEmpty { "오늘도 한 걸음씩 가보자냥!" }
                    )
                    setViewVisibility(R.id.cat_character_paw_row, View.VISIBLE)
                    setPawProgress(this, pawCount, progress)
                }

                setImageViewResource(R.id.cat_character_image, NyangWidgetMood.catImageRes(widgetData))

                val intent = Intent(context, MainActivity::class.java).apply {
                    action = "nyang_coach.OPEN_CHARACTER_WIDGET"
                    data = Uri.parse("nyangcoach://widget/cat/tasks")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                    putExtra("route", "tasks")
                    putExtra("coach_id", "cat")
                }
                val pendingIntent = PendingIntent.getActivity(
                    context,
                    4003,
                    intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                setOnClickPendingIntent(R.id.cat_character_widget_root, pendingIntent)
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun setPawProgress(views: RemoteViews, pawCount: Int, progress: Int) {
        val pawIds = intArrayOf(
            R.id.cat_character_paw_1,
            R.id.cat_character_paw_2,
            R.id.cat_character_paw_3,
            R.id.cat_character_paw_4,
            R.id.cat_character_paw_5
        )
        pawIds.forEachIndexed { index, viewId ->
            views.setImageViewResource(
                viewId,
                if (index < pawCount) R.drawable.ic_widget_paw_filled else R.drawable.ic_widget_paw_outline
            )
        }
        views.setTextViewText(R.id.cat_character_progress_text, "$progress%")
    }
}
