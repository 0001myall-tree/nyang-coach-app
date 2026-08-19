package com.coscene.nyangcoach

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.BitmapFactory
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.view.Gravity
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.widget.ImageView
import android.widget.TextView

/**
 * 다른 앱 위에 냥냥이를 잠깐 띄우는 서비스.
 *
 * 소리도 진동도 없다. 무시하면 15분 뒤 스스로 사라지고 한 시간 뒤에 다시 온다.
 * 누르면 그 자리에서 카드가 펼쳐지고, 고른 답은 다음에 앱이 켜질 때 일정에 반영된다.
 */
class OngoingNudgeService : Service() {
    companion object {
        private const val CHANNEL_ID = "nyang_ongoing_nudge"
        private const val NOTIFICATION_ID = 7402

        fun show(context: Context) {
            val intent = Intent(context, OngoingNudgeService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
    }

    private lateinit var windowManager: WindowManager
    private val handler = Handler(Looper.getMainLooper())

    private var bubbleView: View? = null
    private var cardView: View? = null
    private var bubbleParams: WindowManager.LayoutParams? = null

    /** 아무도 누르지 않으면 스스로 사라지는 타이머. */
    private val autoHide = Runnable { finishRound(scheduleNext = true) }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startInForeground()

        if (!OngoingNudgeState.shouldAppearNow(this)) {
            // 깨어나서 창을 붙이기 직전에 상황이 바뀐 경우.
            finishRound(scheduleNext = OngoingNudgeState.isActive(this))
            return START_NOT_STICKY
        }

        if (bubbleView == null && cardView == null) {
            showBubble()
            handler.postDelayed(autoHide, OngoingNudgeScheduler.VISIBLE_MILLIS)
        }
        return START_NOT_STICKY
    }

    private fun startInForeground() {
        val manager = getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL_ID) == null) {
            // 소리도 배지도 없는 가장 낮은 등급. 창을 띄우기 위해 필요한 자리표시일 뿐이다.
            val channel = NotificationChannel(
                CHANNEL_ID,
                "진행 중인 일정",
                NotificationManager.IMPORTANCE_MIN,
            ).apply {
                description = "시작한 일정이 진행 중일 때 조용히 표시됩니다."
                setShowBadge(false)
            }
            manager.createNotificationChannel(channel)
        }

        val taskText = OngoingNudgeState.taskText(this)
        val notification = Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(
                if (taskText.isBlank()) "진행 중인 일정이 있어요" else "진행 중: $taskText",
            )
            .setOngoing(true)
            .build()

        // specialUse는 안드로이드 14부터 있는 종류다. 그 아래에서는 종류 없이 띄운다.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    // ── 가장자리에 걸친 냥냥이 ────────────────────────────────

    private fun showBubble() {
        val view = LayoutInflater.from(this).inflate(R.layout.nudge_bubble, null)
        view.findViewById<ImageView>(R.id.nudge_bubble_image)
            .setImageBitmap(loadCatBitmap(dp(64)))

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            overlayType(),
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.END
            // 가장자리에 살짝 걸치게 둔다. 차지하는 자리는 줄고 캐릭터는 그대로 보인다.
            x = dp(-10)
            y = OngoingNudgeState.positionY(this@OngoingNudgeService)
                .takeIf { it >= 0 }
                ?: defaultY()
        }

        view.setOnTouchListener(BubbleTouchListener(params))
        windowManager.addView(view, params)
        bubbleView = view
        bubbleParams = params
    }

    /** 화면 아래쪽이되, 제스처 영역과 키보드는 피하는 자리. */
    private fun defaultY(): Int {
        val metrics = resources.displayMetrics
        return (metrics.heightPixels * 0.62f).toInt()
    }

    private inner class BubbleTouchListener(
        private val params: WindowManager.LayoutParams,
    ) : View.OnTouchListener {
        private var startX = 0
        private var startY = 0
        private var touchX = 0f
        private var touchY = 0f
        private var moved = false
        private val slop = ViewConfiguration.get(this@OngoingNudgeService).scaledTouchSlop

        override fun onTouch(view: View, event: MotionEvent): Boolean {
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    startX = params.x
                    startY = params.y
                    touchX = event.rawX
                    touchY = event.rawY
                    moved = false
                    return true
                }

                MotionEvent.ACTION_MOVE -> {
                    // 오른쪽 기준이라 손가락이 왼쪽으로 갈수록 x가 커진다.
                    val dx = (touchX - event.rawX).toInt()
                    val dy = (event.rawY - touchY).toInt()
                    if (!moved && (kotlin.math.abs(dx) > slop || kotlin.math.abs(dy) > slop)) {
                        moved = true
                    }
                    if (moved) {
                        params.x = startX + dx
                        params.y = startY + dy
                        windowManager.updateViewLayout(view, params)
                    }
                    return true
                }

                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    if (moved) {
                        OngoingNudgeState.savePositionY(this@OngoingNudgeService, params.y)
                    } else {
                        expandToCard()
                    }
                    return true
                }
            }
            return false
        }
    }

    // ── 눌렀을 때 펼쳐지는 카드 ───────────────────────────────

    private fun expandToCard() {
        handler.removeCallbacks(autoHide)
        removeBubble()

        val view = LayoutInflater.from(this).inflate(R.layout.nudge_card, null)
        view.findViewById<ImageView>(R.id.nudge_card_image)
            .setImageBitmap(loadCatBitmap(dp(120)))

        val taskText = OngoingNudgeState.taskText(this)
        view.findViewById<TextView>(R.id.nudge_card_title).text =
            if (taskText.isBlank()) {
                "아까 시작한 일,\n지금도 하는 중이야?"
            } else {
                "아까 시작한 '$taskText',\n지금도 하는 중이야?"
            }

        view.findViewById<View>(R.id.nudge_card_done).setOnClickListener {
            answer("done")
        }
        view.findViewById<View>(R.id.nudge_card_continue).setOnClickListener {
            finishRound(scheduleNext = true)
        }
        view.findViewById<View>(R.id.nudge_card_paused).setOnClickListener {
            answer("paused")
        }
        // 카드 바깥을 누르면 다시 작아진다.
        view.findViewById<View>(R.id.nudge_card_scrim).setOnClickListener {
            cardView?.let { windowManager.removeView(it) }
            cardView = null
            showBubble()
            handler.postDelayed(autoHide, OngoingNudgeScheduler.VISIBLE_MILLIS)
        }

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            overlayType(),
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT,
        )
        windowManager.addView(view, params)
        cardView = view
    }

    private fun answer(action: String) {
        val taskId = OngoingNudgeState.taskId(this)
        if (taskId != null) {
            OngoingNudgeState.writeResult(this, taskId, action)
        }
        OngoingNudgeState.clear(this)
        OngoingNudgeScheduler.cancel(this)
        stopEverything()
    }

    private fun finishRound(scheduleNext: Boolean) {
        if (scheduleNext && OngoingNudgeState.isActive(this)) {
            OngoingNudgeScheduler.scheduleIn(
                this,
                OngoingNudgeScheduler.NEXT_ROUND_DELAY_MILLIS,
                OngoingNudgeScheduler.STAGE_FIRST,
            )
        }
        stopEverything()
    }

    private fun stopEverything() {
        handler.removeCallbacks(autoHide)
        removeBubble()
        cardView?.let { runCatching { windowManager.removeView(it) } }
        cardView = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun removeBubble() {
        bubbleView?.let { runCatching { windowManager.removeView(it) } }
        bubbleView = null
        bubbleParams = null
    }

    override fun onDestroy() {
        handler.removeCallbacks(autoHide)
        removeBubble()
        cardView?.let { runCatching { windowManager.removeView(it) } }
        cardView = null
        super.onDestroy()
    }

    // ── 도우미 ───────────────────────────────────────────────

    private fun overlayType(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

    /**
     * Flutter 자산에 들어 있는 냥냥이 이미지를 읽는다.
     *
     * 원본이 1254픽셀이라 그대로 올리면 64dp 자리에 6MB를 쓰게 된다.
     * 화면에 들어갈 크기에 맞춰 줄여서 읽는다.
     */
    private fun loadCatBitmap(targetPx: Int): android.graphics.Bitmap? = runCatching {
        val path = OngoingNudgeState.IMAGE_ASSET

        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        assets.open(path).use { BitmapFactory.decodeStream(it, null, bounds) }

        var sample = 1
        val longest = maxOf(bounds.outWidth, bounds.outHeight)
        while (longest / (sample * 2) >= targetPx) {
            sample *= 2
        }

        val options = BitmapFactory.Options().apply { inSampleSize = sample }
        assets.open(path).use { BitmapFactory.decodeStream(it, null, options) }
    }.getOrNull()

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()
}
