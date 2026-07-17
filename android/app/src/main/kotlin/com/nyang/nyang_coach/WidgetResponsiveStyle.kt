package com.coscene.nyangcoach

import android.appwidget.AppWidgetManager
import android.content.Context
import android.os.Build
import android.util.TypedValue
import android.widget.RemoteViews
import kotlin.math.min
import kotlin.math.roundToInt

object WidgetResponsiveStyle {
    fun applyMini(context: Context, appWidgetManager: AppWidgetManager, widgetId: Int, views: RemoteViews) {
        val options = appWidgetManager.getAppWidgetOptions(widgetId)
        val minWidthDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 120)
        val minHeightDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 120)
        val shortestSide = min(minWidthDp, minHeightDp)
        val scale = ((shortestSide - 110) / 55f).coerceIn(0f, 1f)

        val horizontalPadding = lerp(13f, 16f, scale).roundToInt()
        val topPadding = lerp(6f, 9f, scale).roundToInt()
        val bottomPadding = lerp(24f, 30f, scale).roundToInt()
        val imageSize = lerp(132f, 142f, scale)

        views.setViewPadding(
            R.id.widget_root,
            dp(context, horizontalPadding),
            dp(context, topPadding),
            dp(context, horizontalPadding),
            dp(context, bottomPadding)
        )
        views.setTextViewTextSize(R.id.mini_info_text, TypedValue.COMPLEX_UNIT_SP, lerp(18f, 20f, scale))

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            views.setViewLayoutWidth(R.id.mini_cat_image, imageSize, TypedValue.COMPLEX_UNIT_DIP)
            views.setViewLayoutHeight(R.id.mini_cat_image, imageSize, TypedValue.COMPLEX_UNIT_DIP)
        }
    }

    fun apply(context: Context, appWidgetManager: AppWidgetManager, widgetId: Int, views: RemoteViews) {
        val options = appWidgetManager.getAppWidgetOptions(widgetId)
        val minWidthDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 260)
        val minHeightDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 140)
        val scale = min(
            ((minWidthDp - 220) / 120f).coerceIn(0f, 1f),
            ((minHeightDp - 110) / 70f).coerceIn(0f, 1f)
        )

        val horizontalPadding = lerp(18f, 22f, scale).roundToInt()
        val topPadding = lerp(18f, 24f, scale).roundToInt()
        val bottomPadding = lerp(22f, 28f, scale).roundToInt()
        val cardHorizontalPadding = lerp(12f, 14f, scale).roundToInt()
        val chatHorizontalPadding = lerp(8f, 10f, scale).roundToInt()
        val chatVerticalPadding = lerp(4f, 6f, scale).roundToInt()

        views.setViewPadding(
            R.id.widget_root,
            dp(context, horizontalPadding),
            dp(context, topPadding),
            dp(context, horizontalPadding),
            dp(context, bottomPadding)
        )
        views.setViewPadding(
            R.id.remaining_row,
            dp(context, cardHorizontalPadding),
            0,
            dp(context, cardHorizontalPadding),
            0
        )
        views.setViewPadding(
            R.id.btn_open_chat,
            dp(context, chatHorizontalPadding),
            dp(context, chatVerticalPadding),
            dp(context, chatHorizontalPadding),
            dp(context, chatVerticalPadding)
        )

        views.setTextViewTextSize(R.id.coach_message, TypedValue.COMPLEX_UNIT_SP, lerp(15.5f, 18f, scale))
        views.setTextViewTextSize(R.id.remaining_count_text, TypedValue.COMPLEX_UNIT_SP, lerp(12.5f, 14f, scale))
        views.setTextViewTextSize(R.id.chat_label, TypedValue.COMPLEX_UNIT_SP, lerp(10f, 11f, scale))
    }

    private fun lerp(start: Float, end: Float, amount: Float): Float {
        return start + (end - start) * amount
    }

    private fun dp(context: Context, value: Int): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            value.toFloat(),
            context.resources.displayMetrics
        ).roundToInt()
    }
}
