package com.coscene.nyangcoach

import android.content.Context
import android.content.SharedPreferences
import android.media.AudioManager
import android.os.Build

/**
 * 모닝콜이 울리는 동안만 폰의 알람 볼륨을 이 사람이 정한 크기로 올린다.
 *
 * 안드로이드에는 알람 볼륨 손잡이가 폰에 하나뿐이다. 모닝콜을 들리게 하려고
 * 그 값을 올려두면 그동안 조용하던 다른 앱 알람까지 전부 같이 깨어난다.
 * 아침에 온 세상 알람이 한꺼번에 우는 셈이라 무엇을 끄고 있는지도 알 수 없다.
 *
 * 그래서 값을 바꿔두지 않는다. 울리기 직전에 올리고, 끄면 원래 값으로 돌려놓는다.
 * 모닝콜 볼륨과 폰 알람 볼륨이 따로 놀게 되는 것이다.
 *
 * 되돌릴 값은 [KEY_RESTORE]에 적어둔다. 이 쪽지가 남아 있다는 것은 아직 안
 * 돌려놨다는 뜻이다. 앱이 알람 도중에 죽어도 쪽지는 남아서, 나중에 다시 켜질
 * 때나 안전용 알람이 대신 돌려놓는다. 폰이 큰 소리에 갇히면 안 된다.
 */
object MorningAlarmVolume {
    /** 사용자가 슬라이더로 정한 모닝콜 볼륨. 없으면 아무것도 하지 않는다. */
    private const val KEY_LEVEL = "flutter.nyang_morning_call_volume"

    /** 올리기 전의 폰 알람 볼륨. */
    private const val KEY_RESTORE = "flutter.native_morning_volume_restore"

    /** 울리기 직전에 부른다. 이미 올려둔 채면 원래 값을 덮어쓰지 않는다. */
    fun raise(context: Context) {
        val prefs = prefs(context)
        val desired = prefs.getLong(KEY_LEVEL, -1L).toInt()
        if (desired < 0) return

        val audio = audio(context)
        if (!prefs.contains(KEY_RESTORE)) {
            // 뒤따르는 알람이 두 번 더 오는데, 그때 이미 올려둔 값을 "원래 값"으로
            // 적어버리면 돌아갈 자리를 잃는다.
            prefs.edit()
                .putLong(KEY_RESTORE, audio.getStreamVolume(AudioManager.STREAM_ALARM).toLong())
                .commit()
        }
        apply(audio, desired)
        MorningAlarmScheduler.scheduleVolumeRestore(context)
    }

    /**
     * 원래 값으로 돌려놓는다. 올린 적이 없으면 아무것도 하지 않는다.
     *
     * 여러 곳에서 불러도 된다 - 쪽지를 먼저 지우므로 두 번째부터는 그냥 돌아간다.
     */
    fun restore(context: Context) {
        val prefs = prefs(context)
        if (!prefs.contains(KEY_RESTORE)) return
        val saved = prefs.getLong(KEY_RESTORE, -1L).toInt()
        prefs.edit().remove(KEY_RESTORE).commit()
        MorningAlarmScheduler.cancelVolumeRestore(context)
        if (saved < 0) return
        apply(audio(context), saved)
    }

    /** 설정 화면이 슬라이더를 그릴 때 필요한 값들. */
    fun read(context: Context, blockedByDnd: Boolean): Map<String, Any> {
        val audio = audio(context)
        val max = audio.getStreamMaxVolume(AudioManager.STREAM_ALARM)
        val min = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            audio.getStreamMinVolume(AudioManager.STREAM_ALARM)
        } else {
            0
        }
        // 아직 정한 적이 없으면 지금 폰 값에서 시작한다. 처음 여는 사람에게
        // 슬라이더가 엉뚱한 자리에 가 있으면 자기 폰 이야기로 안 들린다.
        val saved = prefs(context).getLong(KEY_LEVEL, -1L).toInt()
        val level = if (saved < 0) {
            audio.getStreamVolume(AudioManager.STREAM_ALARM)
        } else {
            saved
        }
        return mapOf(
            "level" to level.coerceIn(min, max),
            "max" to max,
            "min" to min,
            "blockedByDnd" to blockedByDnd,
        )
    }

    /**
     * 슬라이더를 움직였다. 폰 볼륨은 건드리지 않고 값만 적어둔다.
     *
     * 여기서 폰 값을 바꾸면 모닝콜이 울리기도 전에 다른 앱 알람부터 커진다.
     * 그게 이 파일이 생긴 이유다.
     */
    fun write(context: Context, level: Int, blockedByDnd: Boolean): Map<String, Any> {
        prefs(context).edit().putLong(KEY_LEVEL, level.toLong()).commit()
        return read(context, blockedByDnd)
    }

    private fun apply(audio: AudioManager, level: Int) {
        val max = audio.getStreamMaxVolume(AudioManager.STREAM_ALARM)
        val min = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            audio.getStreamMinVolume(AudioManager.STREAM_ALARM)
        } else {
            0
        }
        try {
            audio.setStreamVolume(AudioManager.STREAM_ALARM, level.coerceIn(min, max), 0)
        } catch (_: SecurityException) {
            // 방해금지 중에는 "알림 정책 접근" 권한 없이 못 바꾼다. 그때는 폰
            // 값 그대로 울린다 - 못 올리는 것이지 모닝콜이 막히는 것은 아니다.
        }
    }

    private fun audio(context: Context): AudioManager =
        context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
}
