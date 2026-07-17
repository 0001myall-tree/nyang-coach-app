package com.coscene.nyangcoach

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF

object WidgetProgressRenderer {
    fun create(
        context: Context,
        progress: Int,
        trackColor: String,
        progressColor: String
    ): Bitmap {
        val size = dp(context, 42f)
        val strokePx = dp(context, 6f).toFloat()
        val inset = strokePx / 2f
        val rect = RectF(inset, inset, size - inset, size - inset)
        val clampedProgress = progress.coerceIn(0, 100)

        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)

        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = strokePx
            strokeCap = Paint.Cap.BUTT
        }

        paint.color = Color.parseColor(trackColor)
        canvas.drawArc(rect, 0f, 360f, false, paint)

        paint.color = Color.parseColor(progressColor)
        canvas.drawArc(rect, -90f, 360f * clampedProgress / 100f, false, paint)

        return bitmap
    }

    private fun dp(context: Context, value: Float): Int {
        return (value * context.resources.displayMetrics.density + 0.5f).toInt()
    }
}
