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
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import android.view.Gravity
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.widget.ImageView
import android.widget.Toast
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

        /** 캐릭터 크기. 홈 화면 앱 아이콘만 하다. */
        private const val BUBBLE_DP = 64

        /** 가장자리 밖으로 내보내는 만큼. 이만큼은 일부러 안 보인다. */
        private const val EDGE_PEEK_DP = 10

        private const val EXTRA_TRACK = "track"

        /** 진행 중인 일정 / 말 걸어보는 자리. [OngoingNudgeState]의 기본 슬롯. */
        private const val TRACK_PRIMARY = "primary"

        /** 시작 시각을 기다리는 자리. 독립된 슬롯이라 서로 지우지 않는다. */
        private const val TRACK_START = "start"

        /** 틈새 코칭 자리. 일정을 붙들지 않고 한 마디만 건넨다. */
        private const val TRACK_GAP = "gap"

        /**
         * "다시 시작할게"를 누른 뒤 냥냥이가 적어도 이만큼은 남아 있는다.
         *
         * 원래 있기로 한 시간이 거의 끝나갈 때 눌렀다면 몇 초 만에 사라진다.
         * 그러면 돌아갈 문이 있다고 해놓고 바로 닫아버리는 셈이다.
         */
        private const val LINGER_MILLIS = 2L * 60_000L

        fun show(context: Context) = start(context, TRACK_PRIMARY)

        /** 시작 시각 자리 전용. 진행 중인 일정과 서로 지우지 않는다. */
        fun showStart(context: Context) = start(context, TRACK_START)

        /** 틈새 코칭 자리 전용. 막히면 다시 걸지 않고 오늘은 지나간다. */
        fun showGap(context: Context) = start(context, TRACK_GAP)

        private fun start(context: Context, track: String) {
            val intent = Intent(context, OngoingNudgeService::class.java).apply {
                putExtra(EXTRA_TRACK, track)
            }
            // 백그라운드에서 서비스를 띄우는 건 기기·버전에 따라 막힐 수 있다.
            // 막히면 이번 차례를 거르고 다음 기회에 다시 본다. 여기서 터지면
            // 앱 전체가 조용히 죽는다.
            runCatching {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            }.onFailure {
                // 틈새 코칭은 다시 걸지 않는다. 재촉하지 않기로 한 자리라,
                // 못 나간 차례는 그냥 오늘 몫이 없었던 것이 된다.
                if (track == TRACK_GAP) {
                    return@onFailure
                }
                if (track == TRACK_START) {
                    OngoingNudgeScheduler.scheduleStartIn(
                        context,
                        OngoingNudgeScheduler.RETRY_DELAY_MILLIS,
                        OngoingNudgeScheduler.STAGE_FIRST,
                    )
                } else {
                    OngoingNudgeScheduler.scheduleIn(
                        context,
                        OngoingNudgeScheduler.RETRY_DELAY_MILLIS,
                        OngoingNudgeScheduler.STAGE_FIRST,
                    )
                }
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

    /**
     * 이번 차례에 냥냥이가 화면에 있기로 한 끝 시각.
     *
     * 카드를 펼쳤다 닫을 때마다 15분을 새로 세면, 카드만 여닫아도 냥냥이가
     * 계속 남는다. 처음 나온 시각을 기준으로 남은 만큼만 센다.
     */
    private var visibleUntil = 0L

    /**
     * 이번 차례에 이미 답을 골랐는지.
     *
     * 답한 뒤에도 냥냥이가 남아 있는 길이 생겼다. 같은 질문을 또 펼치지 않고
     * 할 일 창으로 보내려면, 일정이 도는 중이라는 것과 물을 것이 남았다는 것을
     * 따로 알아야 한다.
     */
    private var answered = false

    /** 다음 차례를 이미 잡아뒀는지. 답할 때 잡고, 사라질 때 또 잡지 않는다. */
    private var nextScheduled = false

    /**
     * 지금 이 화면이 어느 자리를 보여주는 중인지. [TRACK_PRIMARY] 또는 [TRACK_START].
     *
     * 두 자리가 독립된 알람으로 따로 예약되기 때문에, 하나가 화면에 떠 있는
     * 동안 다른 쪽 알람이 울릴 수 있다. 그때 어느 쪽 데이터를 읽고 어느 쪽
     * 알람을 다시 걸지 구분하는 기준이 이 값이다.
     */
    private var track = TRACK_PRIMARY

    private fun isStartTrack(): Boolean = track == TRACK_START

    private fun isGapTrack(): Boolean = track == TRACK_GAP

    private fun currentTaskText(): String = when {
        isGapTrack() -> ""
        isStartTrack() -> OngoingNudgeState.startTaskText(this)
        else -> OngoingNudgeState.taskText(this)
    }

    /**
     * 이 자리가 아직 무언가를 맡고 있는지. 다음 차례를 잡을지 여기서 갈린다.
     *
     * 틈새 코칭은 늘 아니다. 붙들고 있는 일정도 없고, 다음 차례도 없다.
     */
    private fun isActiveForCurrentTrack(): Boolean = when {
        isGapTrack() -> false
        isStartTrack() -> OngoingNudgeState.isStartActive(this)
        else -> OngoingNudgeState.isActive(this)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val requestedTrack = intent?.getStringExtra(EXTRA_TRACK) ?: TRACK_PRIMARY
        val currentlyShowing = bubbleView != null || cardView != null

        if (currentlyShowing && requestedTrack == TRACK_GAP) {
            // "다음 일"·"멈춘 일" 카드가 떠 있으면 자리를 넘겨받는다. 저쪽은
            // 두 시간 뒤에 다시 물어도 그만이지만, 틈새 코칭은 정해둔 그 시각을
            // 놓치면 그날치가 사라진다.
            val showingIdleNudge = track == TRACK_PRIMARY &&
                OngoingNudgeState.isIdleNudge(this)
            if (!showingIdleNudge) return START_NOT_STICKY

            OngoingNudgeScheduler.scheduleIn(
                this,
                OngoingNudgeScheduler.NEXT_TASK_ROUND_MILLIS,
                OngoingNudgeScheduler.STAGE_FIRST,
            )
            handler.removeCallbacks(autoHide)
            removeBubble()
            cardView?.let { runCatching { windowManager.removeView(it) } }
            cardView = null
            answered = false
            nextScheduled = false
            track = TRACK_GAP
        }

        if (currentlyShowing && requestedTrack != track) {
            if (requestedTrack == TRACK_START) {
                // 시작 알림이 우선이다. 보여주던 트랙은 다시 보게 접어두고
                // 넘어간다 — 틈새 코칭만 예외로, 밀려난 자리를 다시 잡지 않는다.
                if (track == TRACK_PRIMARY) {
                    OngoingNudgeScheduler.scheduleIn(
                        this,
                        OngoingNudgeScheduler.RETRY_DELAY_MILLIS,
                        OngoingNudgeScheduler.STAGE_FIRST,
                    )
                }
                handler.removeCallbacks(autoHide)
                removeBubble()
                cardView?.let { runCatching { windowManager.removeView(it) } }
                cardView = null
                answered = false
                nextScheduled = false
                track = requestedTrack
            } else {
                // 시작 카드가 이미 떠 있는데 진행 중 확인이 늦게 왔다. 이번 차례는
                // 접고 나중에 다시 본다 — 지금 뜬 걸 밀어내지 않는다.
                OngoingNudgeScheduler.scheduleIn(
                    this,
                    OngoingNudgeScheduler.RETRY_DELAY_MILLIS,
                    OngoingNudgeScheduler.STAGE_FIRST,
                )
                return START_NOT_STICKY
            }
        } else if (!currentlyShowing) {
            track = requestedTrack
        }

        startInForeground()

        // 시작 시간 알림과 다음 일 알림은 딴짓 방지 스위치(isEnabled)와 별개로
        // 뜬다. 여기서 requireEnabled를 그대로 두면, 그 스위치를 켠 적 없는
        // 사람에게는 Receiver가 통과시켜도 창을 붙이기 직전에 다시 막혀 결국
        // 안 나온다.
        val requireEnabled = !isStartTrack() && !OngoingNudgeState.isIdleNudge(this)
        val shouldAppear = when {
            isGapTrack() -> OngoingNudgeState.shouldAppearNowForGap(this)
            isStartTrack() -> OngoingNudgeState.shouldAppearNowForStart(this)
            else -> OngoingNudgeState.shouldAppearNow(this, requireEnabled = requireEnabled)
        }
        if (!shouldAppear) {
            // 깨어나서 창을 붙이기 직전에 상황이 바뀐 경우.
            finishRound(scheduleNext = isActiveForCurrentTrack())
            return START_NOT_STICKY
        }

        if (bubbleView == null && cardView == null) {
            val visibleMillis = if (isGapTrack()) {
                OngoingNudgeScheduler.GAP_VISIBLE_MILLIS
            } else {
                OngoingNudgeScheduler.VISIBLE_MILLIS
            }
            visibleUntil = SystemClock.elapsedRealtime() + visibleMillis
            showBubble()
            handler.postDelayed(autoHide, visibleMillis)
            // 실제로 화면에 붙은 자리다. 걸러져 지나간 경우와 구분해서 적어야,
            // 나가지도 않은 틈새 코칭 때문에 다음 코칭이 막히지 않는다.
            if (isGapTrack()) OngoingNudgeState.markGapShown(this)
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

        val taskText = currentTaskText()
        val waitingToStart = isStartTrack()
        val waitingForNext = !isStartTrack() && !isGapTrack() &&
            OngoingNudgeState.isNextTaskReminder(this)
        val waitingToResume = !isStartTrack() && !isGapTrack() &&
            OngoingNudgeState.isResumeReminder(this)
        val title = when {
            isGapTrack() -> "지금 잠깐 여유 있나냥?"
            taskText.isBlank() && waitingToStart -> "시작할 일정이 있어요"
            taskText.isBlank() && waitingForNext -> "아직 안 한 일이 있어요"
            taskText.isBlank() && waitingToResume -> "멈춰 있는 일이 있어요"
            taskText.isBlank() -> "진행 중인 일정이 있어요"
            waitingToStart -> "시작할 시간: $taskText"
            waitingForNext -> "다음 일: $taskText"
            waitingToResume -> "멈춘 일: $taskText"
            else -> "진행 중: $taskText"
        }
        val notification = Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
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
            .setImageBitmap(loadCatBitmap(dp(BUBBLE_DP)))

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
            x = EDGE_PEEK_DP.let { dp(-it) }
            // 지난번에 옮겨둔 자리를 쓰되, 지금 화면 밖이면 무시한다.
            // 가로로 눕히거나 기기를 바꾸면 그때 저장한 값이 화면 밖일 수 있다.
            y = clampY(
                OngoingNudgeState.positionY(this@OngoingNudgeService)
                    .takeIf { it >= 0 }
                    ?: defaultY()
            )
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

    /**
     * 냥냥이가 화면 밖으로 달아나지 않게 잡아둔다.
     *
     * 끌어서 옮길 수 있게 해둔 이상, 위아래로 밀어내면 얼굴이 반쯤 잘리거나
     * 아예 사라져서 다시 부를 방법이 없어진다. 위로는 상태바, 아래로는 제스처
     * 영역만큼 여백을 남긴다.
     */
    private fun clampY(y: Int): Int {
        val top = dp(28)
        val bottom = resources.displayMetrics.heightPixels - dp(BUBBLE_DP) - dp(56)
        if (bottom <= top) return top
        return y.coerceIn(top, bottom)
    }

    /** 오른쪽 끝 기준. 음수는 화면 밖으로 걸친 만큼, 클수록 왼쪽으로 온다. */
    private fun clampX(x: Int): Int {
        val leftMost = resources.displayMetrics.widthPixels - dp(BUBBLE_DP)
        val rightMost = dp(-EDGE_PEEK_DP)
        if (leftMost <= rightMost) return rightMost
        return x.coerceIn(rightMost, leftMost)
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
                        params.x = clampX(startX + dx)
                        params.y = clampY(startY + dy)
                        windowManager.updateViewLayout(view, params)
                    }
                    return true
                }

                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    if (moved) {
                        OngoingNudgeState.savePositionY(this@OngoingNudgeService, params.y)
                    } else if (!answered && (isGapTrack() || isActiveForCurrentTrack())) {
                        expandToCard()
                    } else {
                        // 이미 답을 마친 뒤다. 물을 것이 없으니 할 일 창으로 보낸다.
                        openPlanner()
                    }
                    return true
                }
            }
            return false
        }
    }

    // ── 눌렀을 때 펼쳐지는 카드 ───────────────────────────────

    private fun expandToCard() {
        if (isGapTrack()) {
            expandToGapCard()
            return
        }
        if (isStartTrack() || OngoingNudgeState.isNextTaskReminder(this)) {
            expandToStartCard()
            return
        }
        handler.removeCallbacks(autoHide)
        removeBubble()

        val view = LayoutInflater.from(this).inflate(R.layout.nudge_card, null)
        val cardImage = view.findViewById<ImageView>(R.id.nudge_card_image)
        cardImage.setImageBitmap(loadCatBitmap(dp(120)))
        // 여기서 답하지 않고 앱에서 보고 싶을 때. 냥냥이를 누르면 할 일 창으로 간다.
        cardImage.setOnClickListener { openPlanner() }

        val isResume = OngoingNudgeState.isResumeReminder(this)
        val taskText = OngoingNudgeState.taskText(this)
        val titleView = view.findViewById<TextView>(R.id.nudge_card_title)
        val doneButton = view.findViewById<TextView>(R.id.nudge_card_done)
        val continueButton = view.findViewById<TextView>(R.id.nudge_card_continue)
        val restartButton = view.findViewById<TextView>(R.id.nudge_card_restart)
        if (isResume) {
            titleView.text = if (taskText.isBlank()) {
                "집사, 하다가 멈춘 일,\n다시 시작할까?"
            } else {
                "집사, '$taskText' 하다가 멈췄네.\n다시 시작할까?"
            }
            doneButton.text = "하고 있어"
            continueButton.text = "그럴게"
            restartButton.text = "나중에"
            doneButton.setOnClickListener { resumeStillDoing() }
            continueButton.setOnClickListener { resumeNow() }
            restartButton.setOnClickListener { resumeLater() }
        } else {
            titleView.text = if (taskText.isBlank()) {
                "아까 시작한 일,\n지금도 하는 중이야?"
            } else {
                "아까 시작한 '$taskText',\n지금도 하는 중이야?"
            }
            doneButton.setOnClickListener { answerDone() }
            continueButton.setOnClickListener { keepGoing() }
            restartButton.setOnClickListener { restart() }
        }
        // 카드 바깥을 누르면 다시 작아진다.
        view.findViewById<View>(R.id.nudge_card_scrim).setOnClickListener {
            cardView?.let { windowManager.removeView(it) }
            cardView = null
            showBubble()
            handler.postDelayed(autoHide, remainingVisibleMillis())
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

    /**
     * 시작할 시각이 됐는데 아직 시작하지 않은 일정, 또는 방금 하나를 끝내고
     * 시간이 정해지지 않은 다음 일이 남았을 때 묻는 카드. 생김새는 같고 문구와
     * 답이 다르다.
     *
     * 시작한 일을 잊는 것보다 시작 자체를 안 하는 쪽이 훨씬 흔하다. 정해둔 시각에
     * 폰을 보고 있으면 그 일정은 대개 그날 시작되지 않는다.
     */
    private fun expandToStartCard() {
        handler.removeCallbacks(autoHide)
        removeBubble()

        val isNext = !isStartTrack() && OngoingNudgeState.isNextTaskReminder(this)
        val view = LayoutInflater.from(this).inflate(R.layout.nudge_start_card, null)
        val cardImage = view.findViewById<ImageView>(R.id.nudge_start_image)
        cardImage.setImageBitmap(loadCatBitmap(dp(120)))
        cardImage.setOnClickListener { openPlanner() }

        val taskText = currentTaskText()
        view.findViewById<TextView>(R.id.nudge_start_title).text = when {
            isNext && taskText.isBlank() -> "집사, 냥이랑 남은 일정도\n시작할까냥?"
            isNext -> "집사, '$taskText'\n냥이랑 지금 시작할까냥?"
            taskText.isBlank() -> "집사, 지금 시작하기로 한 일\n잊지 않았지?"
            else -> "집사, '$taskText'\n시작하는 거 잊지 않았지?"
        }

        val goButton = view.findViewById<TextView>(R.id.nudge_start_go)
        val laterButton = view.findViewById<TextView>(R.id.nudge_start_later)
        if (isNext) {
            goButton.text = "지금 할게"
            laterButton.text = "더 있다 할게"
            goButton.setOnClickListener { nextTaskNow() }
            laterButton.setOnClickListener { nextTaskLater() }
        } else {
            goButton.setOnClickListener { startNow() }
            laterButton.setOnClickListener { startLater() }
        }
        // 카드 바깥을 누르면 다시 작아진다.
        view.findViewById<View>(R.id.nudge_start_scrim).setOnClickListener {
            cardView?.let { windowManager.removeView(it) }
            cardView = null
            showBubble()
            handler.postDelayed(autoHide, remainingVisibleMillis())
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

    /**
     * 틈새 코칭 카드. 버튼이 없다.
     *
     * 무엇을 할지 정해주지 않는 자리라 실행도 거절도 물을 것이 없다. 하고 싶은
     * 사람은 냥냥이를 눌러 할 일 목록으로 가고, 아니면 바깥을 누르거나 그냥
     * 두면 사라진다. 어느 쪽이든 다시 부르지 않는다.
     */
    private fun expandToGapCard() {
        handler.removeCallbacks(autoHide)
        removeBubble()

        val view = LayoutInflater.from(this).inflate(R.layout.nudge_gap_card, null)
        val cardImage = view.findViewById<ImageView>(R.id.nudge_gap_image)
        cardImage.setImageBitmap(loadCatBitmap(dp(120)))
        cardImage.setOnClickListener { openPlanner() }

        view.findViewById<View>(R.id.nudge_gap_scrim).setOnClickListener {
            cardView?.let { runCatching { windowManager.removeView(it) } }
            cardView = null
            showBubble()
            handler.postDelayed(autoHide, remainingVisibleMillis())
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

    /**
     * "시작할게". 여기서 바로 시작한 것으로 적는다.
     *
     * 앱에 들어가 ▶를 다시 누르게 하면, 시작하겠다고 말한 사람에게 한 칸을 더
     * 시키는 셈이다. 그 한 칸이 그냥 안 하게 되는 이유가 된다.
     */
    private fun startNow() {
        answered = true
        val taskId = OngoingNudgeState.startTaskId(this)
        val taskText = OngoingNudgeState.startTaskText(this)
        if (taskId != null) {
            OngoingNudgeAnswerWriter.markStarted(this, taskId)
            OngoingNudgeState.writeResult(this, taskId, "started")
        }
        OngoingNudgeState.clearStart(this)
        OngoingNudgeScheduler.cancelStart(this)
        // 이제 도는 중이다. 딴짓 방지 기능을 켠 사람만 30분 뒤에 다시 챙긴다.
        // 시작 시간 알림은 기본 동작이지만, 시작 후 계속 따라가는 기능은 별도 스위치다.
        // 진행 중 자리는 시작 시각 자리와 독립이라, 이미 다른 일정이 돌고 있어도
        // 그건 그것대로 건드리지 않는다.
        if (taskId != null && OngoingNudgeState.isEnabled(this) &&
            !OngoingNudgeAnswerWriter.isAnyTaskInProgress(this)
        ) {
            OngoingNudgeState.start(this, taskId, taskText, OngoingNudgeState.KIND_ONGOING)
            OngoingNudgeScheduler.scheduleIn(
                this,
                OngoingNudgeScheduler.FIRST_DELAY_MILLIS,
                OngoingNudgeScheduler.STAGE_FIRST,
            )
        }
        Toast.makeText(this, "좋아! 지금부터 시작이야", Toast.LENGTH_SHORT).show()
        lingerAsDoorway()
    }

    /** "좀 더 있다가". 30분 뒤에 한 번 더 묻고, 그 뒤로는 묻지 않는다. */
    private fun startLater() {
        answered = true
        scheduleNextStartRound(OngoingNudgeScheduler.START_SNOOZE_MILLIS)
        Toast.makeText(this, "알겠어. 이따 다시 부를게!", Toast.LENGTH_SHORT).show()
        lingerAsDoorway()
    }

    /**
     * "지금 할게". 다음 일도 그 자리에서 바로 시작한 것으로 적는다.
     *
     * [startNow]와 같은 이유로 여기서 시작 표시까지 남긴다 — 앱에 들어가 ▶를
     * 또 누르게 하면 그 한 칸이 안 하게 되는 이유가 된다. 물을 것이 끝났으니
     * 더 반복하지 않는다.
     */
    private fun nextTaskNow() {
        answered = true
        val taskId = OngoingNudgeState.taskId(this)
        if (taskId != null) {
            OngoingNudgeAnswerWriter.markStarted(this, taskId)
            OngoingNudgeState.writeResult(this, taskId, "started")
        }
        OngoingNudgeState.clear(this)
        OngoingNudgeScheduler.cancel(this)
        Toast.makeText(this, "좋아! 지금부터 시작이야", Toast.LENGTH_SHORT).show()
        lingerAsDoorway()
    }

    /** "더 있다 할게". 22시가 되기 전까지 2시간마다 조건을 다시 보고 되묻는다. */
    private fun nextTaskLater() {
        answered = true
        scheduleNextRound(OngoingNudgeScheduler.NEXT_TASK_ROUND_MILLIS)
        Toast.makeText(this, "알겠어. 이따 다시 부를게!", Toast.LENGTH_SHORT).show()
        lingerAsDoorway()
    }

    /**
     * "그럴게". 멈춰 있던 일을 그 자리에서 다시 돈다.
     *
     * [nextTaskNow]와 달리 이미 손댄 일이라 처음 시작이 아니라 재시작이지만,
     * [OngoingNudgeAnswerWriter.markStarted]는 둘을 가리지 않는다 — 쌓인 시간에
     * 이어 붙이는 건 똑같다.
     */
    private fun resumeNow() = markResumed("좋아! 다시 시작이야")

    /**
     * "하고 있어". 버튼만 안 눌렀을 뿐 실제로는 하는 중이었다는 뜻이라, 여기서도
     * 똑같이 시작으로 적는다. 데이터를 안 건드리면 앱은 계속 멈춘 걸로 알고
     * 있다가 조금 뒤 또 "다시 시작할까"를 묻는데, 이미 하는 중이라고 답한
     * 사람에게 같은 질문을 반복하는 셈이 된다.
     */
    private fun resumeStillDoing() = markResumed("그렇구나! 이어서 기록할게")

    private fun markResumed(toast: String) {
        answered = true
        val taskId = OngoingNudgeState.taskId(this)
        if (taskId != null) {
            OngoingNudgeAnswerWriter.markStarted(this, taskId)
            OngoingNudgeState.writeResult(this, taskId, "started")
        }
        OngoingNudgeState.clear(this)
        OngoingNudgeScheduler.cancel(this)
        Toast.makeText(this, toast, Toast.LENGTH_SHORT).show()
        lingerAsDoorway()
    }

    /** "나중에". 22시가 되기 전까지 2시간마다 조건을 다시 보고 되묻는다. */
    private fun resumeLater() {
        answered = true
        scheduleNextRound(OngoingNudgeScheduler.NEXT_TASK_ROUND_MILLIS)
        Toast.makeText(this, "알겠어. 이따 다시 부를게!", Toast.LENGTH_SHORT).show()
        lingerAsDoorway()
    }

    /**
     * 앱의 할 일 창을 연다. 홈 화면 위젯이 쓰는 길을 그대로 탄다 —
     * 어느 화면에 있든 플래너가 열린 상태로 들어간다.
     */
    private fun openPlanner() {
        val intent = Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            data = Uri.parse("nyangcoach://widget")
            putExtra("route", "tasks")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        runCatching { startActivity(intent) }
        finishRound(scheduleNext = isActiveForCurrentTrack())
    }

    /** "다 했어". 여기서 바로 완료로 적고 이번 일정은 끝난다. */
    private fun answerDone() {
        val taskId = OngoingNudgeState.taskId(this)
        if (taskId != null) {
            // 지금 바로 적어 넣는다. 며칠 뒤에 앱을 열어도 이미 채워져 있어야 한다.
            OngoingNudgeAnswerWriter.apply(this, taskId, done = true)
            // 쪽지도 남긴다. 앱이 열리면 정식 경로가 한 번 더 정확히 훑는다.
            OngoingNudgeState.writeResult(this, taskId, "done")
        }
        // 카드가 그냥 사라지면 눌린 건지 알 수 없다. 소리 없이 한 줄만 남긴다.
        Toast.makeText(this, "다 했다고 기록했어!", Toast.LENGTH_SHORT).show()
        OngoingNudgeState.clear(this)
        OngoingNudgeScheduler.cancel(this)
        stopEverything()
    }

    /**
     * "계속하는 중"을 눌렀을 때.
     *
     * 일정은 건드리지 않는다. 하고 있다는 말을 그대로 믿는다.
     *
     * 다만 냥냥이는 남는다. 곧바로 사라지던 때는 이 버튼이 딴짓을 계속하기에
     * 가장 편한 길이었다 — 하는 중이라고 한 마디만 하면 방해가 사라지니,
     * 엄마에게 공부 중이라고 답하는 것과 같은 자리가 된다. 정말 하는 중이면
     * 화면 가장자리의 냥냥이는 아무것도 막지 않고, 아니면 돌아갈 문이 된다.
     */
    private fun keepGoing() {
        answered = true
        scheduleNextRound(OngoingNudgeScheduler.NEXT_ROUND_DELAY_MILLIS)
        Toast.makeText(this, "그래, 하던 거 이어서!", Toast.LENGTH_SHORT).show()
        lingerAsDoorway()
    }

    /**
     * "다시 시작할게"를 눌렀을 때.
     *
     * 일정은 아무것도 건드리지 않는다. 돌아가겠다고 말한 사람에게 "멈춘 걸로
     * 해뒀어"라고 답하면, 돌아가기 전에 다시 시작부터 해야 하는 셈이 된다.
     * 그 한 칸이 그냥 안 하게 되는 이유가 된다. 시계는 그대로 흐른다.
     *
     * 냥냥이가 남는 것은 [keepGoing]과 같다. 이제 물을 것은 없으니, 한 번 더
     * 누르면 할 일 창이 열린다.
     */
    private fun restart() {
        answered = true
        scheduleNextRound(OngoingNudgeScheduler.NEXT_ROUND_DELAY_MILLIS)
        Toast.makeText(this, "알았어. 냥이랑 가볍게 다시 시작!", Toast.LENGTH_SHORT).show()
        lingerAsDoorway()
    }

    /** 다음 차례를 잡아둔다. 한 번 잡았으면 이번 등장에서는 다시 잡지 않는다. */
    private fun scheduleNextRound(delayMillis: Long) {
        OngoingNudgeScheduler.scheduleIn(
            this,
            delayMillis,
            OngoingNudgeScheduler.STAGE_FIRST,
        )
        nextScheduled = true
    }

    /** [scheduleNextRound]의 시작 시각 자리 버전. 독립된 알람이라 따로 건다. */
    private fun scheduleNextStartRound(delayMillis: Long) {
        OngoingNudgeScheduler.scheduleStartIn(
            this,
            delayMillis,
            OngoingNudgeScheduler.STAGE_FIRST,
        )
        nextScheduled = true
    }

    /** 답을 하고도 냥냥이가 자리를 지킨다. */
    private fun lingerAsDoorway() {
        cardView?.let { runCatching { windowManager.removeView(it) } }
        cardView = null
        if (bubbleView == null) showBubble()
        handler.removeCallbacks(autoHide)
        handler.postDelayed(
            autoHide,
            maxOf(remainingVisibleMillis(), LINGER_MILLIS),
        )
    }

    /** 이번 차례에 남은 시간. 이미 지났으면 0. */
    private fun remainingVisibleMillis(): Long =
        (visibleUntil - SystemClock.elapsedRealtime()).coerceAtLeast(0L)

    private fun finishRound(scheduleNext: Boolean) {
        if (scheduleNext && !nextScheduled && isActiveForCurrentTrack()) {
            if (isStartTrack()) {
                // 시작을 기다리는 쪽은 더 자주 본다. 시작할 시각은 지나가는 중이고,
                // 한 시간 뒤에 다시 오면 그때는 이미 오늘이 아니다.
                scheduleNextStartRound(OngoingNudgeScheduler.START_SNOOZE_MILLIS)
            } else {
                scheduleNextRound(
                    // 아무 것도 안 누르고 15분간 놔둔 것도 "더 있다 할게"/"나중에"와 같다.
                    if (OngoingNudgeState.isIdleNudge(this)) {
                        OngoingNudgeScheduler.NEXT_TASK_ROUND_MILLIS
                    } else {
                        OngoingNudgeScheduler.NEXT_ROUND_DELAY_MILLIS
                    },
                )
            }
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
