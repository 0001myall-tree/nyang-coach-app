package com.coscene.nyangcoach

import android.content.Context
import android.os.PowerManager
import android.provider.Settings

/**
 * 진행 중인 일정을 다시 떠올리게 하는 냥냥이의 상태.
 *
 * Flutter와 같은 SharedPreferences 파일을 쓴다. Flutter가 읽어야 하는 값만
 * "flutter." 접두어를 붙이고, 네이티브만 쓰는 값(마지막 위치)은 접두어 없이 둔다.
 * 접두어가 붙은 값은 Flutter 쪽 플러그인이 전부 훑기 때문에 타입이 어긋나면 안 된다
 * (정수는 반드시 Long).
 *
 * 이름은 'nyang_'으로 시작하지 않는다. 그 접두어가 붙은 값은 통째로 클라우드에
 * 올라갔다 내려오는데, 여기 담기는 건 전부 이 기기에서만 뜻이 있는 것들이다.
 */
object OngoingNudgeState {
    private const val PREFS = "FlutterSharedPreferences"

    /** 테스터에게만 켜주는 스위치. 꺼져 있으면 아무것도 하지 않는다. */
    private const val KEY_ENABLED = "flutter.ongoing_nudge_enabled"
    private const val KEY_TASK_ID = "flutter.ongoing_nudge_task_id"
    private const val KEY_TASK_TEXT = "flutter.ongoing_nudge_task_text"
    private const val KEY_RESULT = "flutter.ongoing_nudge_pending_result"

    /** 냥냥코치가 화면 앞에 있는지. 앱 안에서는 이미 진행 중 카드가 보이므로 나가지 않는다. */
    private const val KEY_APP_FOREGROUND = "flutter.ongoing_nudge_app_foreground"

    /** 사용자가 옮겨둔 세로 위치. 네이티브만 쓴다. */
    private const val KEY_POSITION_Y = "ongoing_nudge_position_y"

    /**
     * 어떤 코치를 쓰든 화면 밖으로 나가는 얼굴은 냥냥이 하나다.
     * 앱의 상징이고, 다른 앱 위에서는 이게 냥냥코치라는 걸 한눈에 알아야 한다.
     */
    const val IMAGE_ASSET = "flutter_assets/assets/images/cat_nobg.png"

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun isEnabled(context: Context): Boolean =
        prefs(context).getBoolean(KEY_ENABLED, false)

    fun taskId(context: Context): String? =
        prefs(context).getString(KEY_TASK_ID, null)?.takeIf { it.isNotBlank() }

    fun taskText(context: Context): String =
        prefs(context).getString(KEY_TASK_TEXT, null).orEmpty()

    fun isActive(context: Context): Boolean = taskId(context) != null

    fun start(context: Context, taskId: String, taskText: String) {
        prefs(context).edit()
            .putString(KEY_TASK_ID, taskId)
            .putString(KEY_TASK_TEXT, taskText)
            .commit()
    }

    fun clear(context: Context) {
        prefs(context).edit()
            .remove(KEY_TASK_ID)
            .remove(KEY_TASK_TEXT)
            .commit()
    }

    /**
     * 사용자가 카드에서 고른 답. Flutter가 다음에 켜질 때 읽어서 일정에 반영한다.
     * 백그라운드에서 Dart를 깨우지 않고, 이미 쓰고 있는 모닝콜 payload와 같은 방식이다.
     */
    fun writeResult(context: Context, taskId: String, action: String) {
        val json = """{"taskId":"${escape(taskId)}","action":"$action","at":${System.currentTimeMillis()}}"""
        prefs(context).edit().putString(KEY_RESULT, json).commit()
    }

    private fun escape(value: String): String =
        value.replace("\\", "\\\\").replace("\"", "\\\"")

    fun isAppForeground(context: Context): Boolean =
        prefs(context).getBoolean(KEY_APP_FOREGROUND, false)

    fun positionY(context: Context): Int =
        prefs(context).getInt(KEY_POSITION_Y, -1)

    fun savePositionY(context: Context, y: Int) {
        prefs(context).edit().putInt(KEY_POSITION_Y, y).apply()
    }

    fun canDrawOverlays(context: Context): Boolean = Settings.canDrawOverlays(context)

    /** 화면이 켜져 있으면 폰을 보고 있는 중이라고 본다. 꺼져 있으면 건드리지 않는다. */
    fun isScreenOn(context: Context): Boolean {
        val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        return power.isInteractive
    }

    /** 지금 냥냥이를 내보내도 되는 상황인가. */
    fun shouldAppearNow(context: Context): Boolean =
        isEnabled(context) &&
            isActive(context) &&
            canDrawOverlays(context) &&
            isScreenOn(context) &&
            !isAppForeground(context)
}
