import SwiftUI
import WidgetKit
#if canImport(ActivityKit)
import ActivityKit
#endif

private let appGroupId = "group.com.nyang.nyangCoach"

struct NyangEntry: TimelineEntry {
    let date: Date
    let scheduleTime: String
    let scheduleTitle: String
    let remainingCount: Int
    let progress: Int
    let characterKind: String
    let characterStatus: String
    let characterTitle: String
    let characterPaws: Int
    let catMessage: String
    let isVacation: Bool
    let lastOpenedAt: Date?
}

/// 휴식 모드가 아닌 상태로 24시간 이상 앱을 열지 않았는지 여부.
/// 이때는 남은 일정 개수가 의미 없으므로 위젯 문구를 "보고싶다옹"으로 바꾼다.
func isAwayOverDay(_ entry: NyangEntry) -> Bool {
    if entry.isVacation {
        return false
    }
    guard let lastOpened = entry.lastOpenedAt else {
        return false
    }
    return Date().timeIntervalSince(lastOpened) >= 24 * 3600
}

/// 냥냥이 표정 우선순위: 휴식 모드 > 미접속(48h/24h) > 목표 달성률.
func nyangCatImageName(for entry: NyangEntry) -> String {
    if entry.isVacation {
        return "iphonecatwidget7"
    }
    if let lastOpened = entry.lastOpenedAt {
        let hours = Date().timeIntervalSince(lastOpened) / 3600
        if hours >= 48 {
            return "iphonecatwidget6"
        }
        if hours >= 24 {
            return "iphonecatwidget5"
        }
    }
    let progress = min(max(entry.progress, 0), 100)
    if progress >= 90 {
        return "iphonecatwidget4"
    }
    if progress >= 51 {
        return "iphonecatwidget3"
    }
    if progress >= 10 {
        return "iphonecatwidget2"
    }
    return "iphonecatwidget1"
}

struct NyangProvider: TimelineProvider {
    func placeholder(in context: Context) -> NyangEntry {
        NyangEntry(
            date: Date(),
            scheduleTime: "17:00",
            scheduleTitle: "운동",
            remainingCount: 2,
            progress: 34,
            characterKind: "timed",
            characterStatus: "17:00",
            characterTitle: "운동",
            characterPaws: 1,
            catMessage: "차근차근 간다냥!",
            isVacation: false,
            lastOpenedAt: Date()
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (NyangEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NyangEntry>) -> Void) {
        let entry = loadEntry()
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func loadEntry() -> NyangEntry {
        let defaults = UserDefaults(suiteName: appGroupId) ?? .standard
        let scheduleTime = defaults.string(forKey: "widget_schedule_time")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let scheduleTitle = defaults.string(forKey: "widget_schedule_title")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let remainingCount = defaults.object(forKey: "remaining_count") as? Int ?? Int(defaults.string(forKey: "remaining_count") ?? "") ?? 0
        let progress = defaults.object(forKey: "progress") as? Int ?? Int(defaults.string(forKey: "progress") ?? "") ?? 0
        let characterKind = defaults.string(forKey: "character_widget_kind")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "cheer"
        let characterStatus = defaults.string(forKey: "character_widget_status")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let characterTitle = defaults.string(forKey: "character_widget_title")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "오늘도 한 걸음씩 가보자냥!"
        let characterPaws = defaults.object(forKey: "character_widget_paws") as? Int ?? Int(defaults.string(forKey: "character_widget_paws") ?? "") ?? 0
        let catMessage = defaults.string(forKey: "coach_message_cat") ?? "오늘도 시작해보자냥!"
        let isVacation = defaults.bool(forKey: "vacation_mode")
        let lastOpenedMillis = defaults.object(forKey: "last_opened_at") as? Double
            ?? Double(defaults.string(forKey: "last_opened_at") ?? "")
        let lastOpenedAt = lastOpenedMillis.map { Date(timeIntervalSince1970: $0 / 1000) }

        return NyangEntry(
            date: Date(),
            scheduleTime: scheduleTime,
            scheduleTitle: scheduleTitle,
            remainingCount: remainingCount,
            progress: progress,
            characterKind: characterKind,
            characterStatus: characterStatus,
            characterTitle: characterTitle,
            characterPaws: characterPaws,
            catMessage: catMessage,
            isVacation: isVacation,
            lastOpenedAt: lastOpenedAt
        )
    }
}

private let compactWidgetTitle = "냥냥코치 미니 위젯"
private let compactWidgetDescription = "오늘 목표와 남은 할 일을 냥냥코치 위젯으로 확인합니다."
private let compactWidgetAccent = Color(red: 0.55, green: 0.49, blue: 1.0)

struct NyangCompactWidgetBackground: View {
    var body: some View {
        GeometryReader { proxy in
            let side = max(proxy.size.width, proxy.size.height) * 0.78
            let glow = Color(red: 0.72, green: 0.61, blue: 1.0)
            let softGlow = Color(red: 0.86, green: 0.80, blue: 1.0)

            ZStack {
                Color.white

                RadialGradient(
                    colors: [glow.opacity(0.22), softGlow.opacity(0.10), .clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: side * 0.66
                )

                RadialGradient(
                    colors: [glow.opacity(0.20), softGlow.opacity(0.08), .clear],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: side * 0.62
                )

                RadialGradient(
                    colors: [glow.opacity(0.24), softGlow.opacity(0.10), .clear],
                    center: .bottomLeading,
                    startRadius: 0,
                    endRadius: side * 0.66
                )

                RadialGradient(
                    colors: [glow.opacity(0.24), softGlow.opacity(0.10), .clear],
                    center: .bottomTrailing,
                    startRadius: 0,
                    endRadius: side * 0.66
                )
            }
        }
    }
}

struct NyangCharacterWidgetView: View {
    let entry: NyangEntry
    private let backgroundColors = [
        Color(red: 0.20, green: 0.15, blue: 0.36),
        Color(red: 0.14, green: 0.11, blue: 0.28),
        Color(red: 0.09, green: 0.08, blue: 0.19),
    ]

    private struct Metrics {
        let textLeading: CGFloat
        let textTrailing: CGFloat
        let imageWidth: CGFloat
        let imageHeight: CGFloat
        let imageTrailing: CGFloat
        let imageCenterYRatio: CGFloat
        let timeFontSize: CGFloat
        let titleFontSize: CGFloat
        let pawSize: CGFloat
    }

    private var catImageName: String {
        nyangCatImageName(for: entry)
    }

    private var pawCount: Int {
        min(max(entry.characterPaws, 0), 5)
    }

    private var showsCoreDoneMessage: Bool {
        entry.characterKind == "core_done"
    }

    private var showsCompletionMessage: Bool {
        entry.characterKind == "cheer" && min(max(entry.progress, 0), 100) >= 100
    }

    private var showsStatusRow: Bool {
        !entry.characterStatus.isEmpty &&
        (entry.characterKind == "timed" ||
         entry.characterKind == "habit" ||
         entry.characterKind == "core" ||
         entry.characterKind == "in_progress")
    }

    /// 시간 일정이 없는 상태로 24시간 이상 앱을 열지 않았을 때는
    /// 정보형 발자국 대신 예전의 기다림 문구만 보여준다.
    private var showsMissYouMessage: Bool {
        entry.characterKind != "timed" && isAwayOverDay(entry)
    }

    private var statusIconName: String {
        switch entry.characterKind {
        case "core":
            return "fa_star_solid"
        case "in_progress":
            return "fa_arrows_rotate_solid"
        default:
            return "fa_clock_solid"
        }
    }

    private func makeMetrics(for size: CGSize) -> Metrics {
        let clampedWidth = max(size.width, 280)
        let compact = clampedWidth < 330
        let imageSide = size.height * 0.68
        let textTrailing = min(max(imageSide * 1.35, 140), 170)

        return Metrics(
            textLeading: compact ? 22 : 30,
            textTrailing: textTrailing,
            imageWidth: imageSide,
            imageHeight: imageSide,
            imageTrailing: compact ? 30 : 42,
            imageCenterYRatio: 0.5,
            timeFontSize: compact ? 18 : 20,
            titleFontSize: compact ? 16 : 18,
            pawSize: compact ? 20 : 23
        )
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: backgroundColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color(red: 0.44, green: 0.33, blue: 0.78), lineWidth: 1.2)
                )

            GeometryReader { proxy in
                let metrics = makeMetrics(for: proxy.size)
                let contentSpacing: CGFloat = (showsCompletionMessage || showsMissYouMessage) ? 14 : 13

                ZStack(alignment: .bottomTrailing) {
                    HStack {
                        VStack(alignment: .leading, spacing: contentSpacing) {
                            widgetText(
                                timeFontSize: metrics.timeFontSize,
                                titleFontSize: metrics.titleFontSize
                            )
                            if !showsMissYouMessage {
                                pawProgressRow(pawSize: metrics.pawSize)
                            }
                        }
                            .padding(.leading, metrics.textLeading)
                            .padding(.trailing, metrics.textTrailing)
                            .frame(maxHeight: .infinity, alignment: .center)
                        Spacer(minLength: 0)
                    }

                    Image(catImageName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: metrics.imageWidth, height: metrics.imageHeight)
                        .position(
                            x: proxy.size.width - metrics.imageTrailing - (metrics.imageWidth / 2),
                            y: proxy.size.height * metrics.imageCenterYRatio
                        )
                        .accessibilityHidden(true)

                }
            }
        }
        .widgetBackground(backgroundColors)
        .unredacted()
        .widgetURL(URL(string: "nyangcoach://widget/cat/tasks"))
    }

    @ViewBuilder
    private func widgetText(timeFontSize: CGFloat, titleFontSize: CGFloat) -> some View {
        Group {
            if showsCompletionMessage {
                Text("할 일 다했다냥!\n우리 집사가 최고!")
                    .foregroundColor(.white)
                    .font(.system(size: titleFontSize, weight: .bold, design: .rounded))
                    .lineLimit(2)
                    .lineSpacing(3)
                    .multilineTextAlignment(.leading)
                    .minimumScaleFactor(0.82)
            } else if showsCoreDoneMessage {
                Text("핵심 완료했다냥!")
                    .foregroundColor(.white)
                    .font(.system(size: titleFontSize, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .multilineTextAlignment(.leading)
                    .minimumScaleFactor(0.82)
            } else if showsMissYouMessage {
                Text("집사,\n보고싶다옹....")
                    .foregroundColor(.white)
                    .font(.system(size: titleFontSize, weight: .bold, design: .rounded))
                    .lineLimit(2)
                    .lineSpacing(3)
                    .multilineTextAlignment(.leading)
                    .minimumScaleFactor(0.82)
            } else if showsStatusRow {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 5) {
                        Image(statusIconName)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: timeFontSize * 0.78, height: timeFontSize * 0.78)
                            .foregroundColor(Color(red: 0.63, green: 0.55, blue: 1.0))

                        Text(entry.characterStatus)
                            .foregroundColor(Color(red: 0.55, green: 0.49, blue: 1.0))
                            .font(.system(size: timeFontSize, weight: .bold, design: .rounded))
                            .lineLimit(1)
                    }

                    Text(entry.characterTitle.isEmpty ? "오늘도 한 걸음씩 가보자냥!" : entry.characterTitle)
                        .foregroundColor(.white)
                        .font(.system(size: titleFontSize, weight: .bold, design: .rounded))
                        .lineLimit(2)
                        .lineSpacing(3)
                        .minimumScaleFactor(0.82)
                        .truncationMode(.tail)
                }
            } else {
                Text(entry.characterTitle.isEmpty ? "오늘도 한 걸음씩 가보자냥!" : entry.characterTitle)
                    .foregroundColor(.white)
                    .font(.system(size: titleFontSize, weight: .bold, design: .rounded))
                    .lineLimit(2)
                    .lineSpacing(3)
                    .multilineTextAlignment(.leading)
                    .minimumScaleFactor(0.82)
            }
        }
    }

    private func pawProgressRow(pawSize: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 7) {
            ForEach(0..<5, id: \.self) { index in
                Image("fa_paw_solid")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: pawSize, height: pawSize)
                    .foregroundColor(index < pawCount ? .white : Color(red: 0.86, green: 0.83, blue: 1.0).opacity(0.26))
            }
        }
    }
}

struct NyangCompactWidgetView: View {
    let entry: NyangEntry

    private var hasTimedSchedule: Bool {
        !entry.scheduleTime.isEmpty && !entry.scheduleTitle.isEmpty
    }

    private var miniPawCount: Int {
        min(max(entry.characterPaws, 0), 5)
    }

    private var usesCompactSchedule: Bool {
        hasTimedSchedule && entry.scheduleTitle.count <= 6
    }

    private var hasCoreTask: Bool {
        !hasTimedSchedule &&
        entry.characterKind == "core" &&
        !entry.characterStatus.isEmpty &&
        !entry.characterTitle.isEmpty
    }

    private var hasInProgressTask: Bool {
        !hasTimedSchedule &&
        !hasCoreTask &&
        entry.characterKind == "in_progress" &&
        !entry.characterStatus.isEmpty &&
        !entry.characterTitle.isEmpty
    }

    private var hasHabitTask: Bool {
        !hasTimedSchedule &&
        !hasCoreTask &&
        !hasInProgressTask &&
        entry.characterKind == "habit" &&
        !entry.characterStatus.isEmpty &&
        !entry.characterTitle.isEmpty
    }

    private var hasCoreDone: Bool {
        !hasTimedSchedule &&
        !hasCoreTask &&
        !hasInProgressTask &&
        !hasHabitTask &&
        entry.characterKind == "core_done"
    }

    private var hasCorePrompt: Bool {
        !hasTimedSchedule &&
        !hasCoreTask &&
        !hasInProgressTask &&
        !hasHabitTask &&
        !hasCoreDone &&
        entry.characterKind == "core_prompt" &&
        !entry.characterTitle.isEmpty
    }

    private var usesCompactInProgress: Bool {
        hasInProgressTask && entry.characterTitle.count <= 5
    }

    private var usesCompactHabit: Bool {
        hasHabitTask && entry.characterTitle.count <= 6
    }

    private var usesCompactLayout: Bool {
        usesCompactSchedule || usesCompactInProgress || usesCompactHabit || hasCoreDone || showsCompletionText
    }

    private var showsCompletionText: Bool {
        entry.characterKind == "cheer" &&
        entry.progress >= 100 &&
        !hasTimedSchedule &&
        !hasCoreTask &&
        !hasInProgressTask &&
        !hasHabitTask &&
        !hasCoreDone &&
        !hasCorePrompt
    }

    private var hasTwoLineText: Bool {
        (hasTimedSchedule && !usesCompactSchedule) ||
        hasCoreTask ||
        (hasInProgressTask && !usesCompactInProgress) ||
        (hasHabitTask && !usesCompactHabit)
    }

    private var catImageName: String {
        nyangCatImageName(for: entry)
    }

    private var miniStatusIconName: String {
        if hasCoreTask {
            return "fa_star_solid"
        }
        if hasInProgressTask {
            return "fa_arrows_rotate_solid"
        }
        return "fa_clock_solid"
    }

    var body: some View {
        Link(destination: URL(string: "nyangcoach://widget/cat/tasks")!) {
            compactContent
        }
    }

    private var compactContent: some View {
        ZStack(alignment: .topLeading) {
            NyangCompactWidgetBackground()

            GeometryReader { proxy in
                // Android 미니 위젯과 동일하게 짧은 일정/진행 중 상태는 한 줄,
                // 긴 일정과 핵심 할 일은 두 줄로 배치한다.
                let textHeight: CGFloat = hasTwoLineText ? 40 : 26
                let topPadding: CGFloat = 4
                let imageTextGap: CGFloat = 3
                let bottomPadding: CGFloat = 18
                let horizontalPadding = min(max(proxy.size.width * 0.08, 12), 16)
                let textCenterY = proxy.size.height - bottomPadding - textHeight / 2
                let imageAreaHeight = max(textCenterY - textHeight / 2 - imageTextGap - topPadding, 1)
                let imageScale: CGFloat = hasTwoLineText ? 0.96 : (usesCompactLayout ? 1.08 : 1.05)
                let imageSize = min(proxy.size.width * 0.96, imageAreaHeight * imageScale)
                let imageCenterOffset: CGFloat = usesCompactLayout ? 10 : 2
                let imageCenterY = topPadding + imageSize / 2 + imageCenterOffset

                Image(catImageName, bundle: .main)
                    .renderingMode(.original)
                    .interpolation(.high)
                    .resizable()
                    .scaledToFit()
                    .frame(width: imageSize, height: imageSize, alignment: .center)
                    .position(
                        x: proxy.size.width / 2,
                        y: imageCenterY
                    )
                    .accessibilityHidden(true)

                miniText
                    .frame(
                        maxWidth: .infinity,
                        alignment: hasTwoLineText ? .leading : .center
                    )
                    .frame(height: textHeight)
                    .padding(.horizontal, horizontalPadding)
                    .frame(width: proxy.size.width)
                    .position(
                        x: proxy.size.width / 2,
                        y: textCenterY
                    )
            }
        }
        .widgetCompactBackground()
        .unredacted()
    }

    private var miniText: some View {
        Group {
            if hasTimedSchedule && usesCompactSchedule {
                compactStatusText("\(entry.scheduleTime) \(entry.scheduleTitle)")
            } else if hasTimedSchedule {
                twoLineStatusText(status: entry.scheduleTime, title: entry.scheduleTitle)
            } else if hasCoreTask {
                twoLineStatusText(status: entry.characterStatus, title: entry.characterTitle)
            } else if hasInProgressTask && usesCompactInProgress {
                compactStatusText("\(entry.characterStatus) \(entry.characterTitle)")
            } else if hasInProgressTask {
                twoLineStatusText(status: entry.characterStatus, title: entry.characterTitle)
            } else if hasHabitTask && usesCompactHabit {
                compactStatusText("\(entry.characterStatus) \(entry.characterTitle)")
            } else if hasHabitTask {
                twoLineStatusText(status: entry.characterStatus, title: entry.characterTitle)
            } else if hasCoreDone {
                Text("핵심 완료!")
                    .foregroundColor(Color(red: 0.15, green: 0.14, blue: 0.16))
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .multilineTextAlignment(.center)
            } else if hasCorePrompt {
                Text(entry.characterTitle)
                    .foregroundColor(Color(red: 0.15, green: 0.14, blue: 0.16))
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                    .multilineTextAlignment(.center)
            } else if isAwayOverDay(entry) {
                Text("집사 보고싶다옹...")
                    .foregroundColor(Color(red: 0.15, green: 0.14, blue: 0.16))
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .multilineTextAlignment(.center)
            } else if showsCompletionText {
                Text("다했다냥!")
                    .foregroundColor(Color(red: 0.15, green: 0.14, blue: 0.16))
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .multilineTextAlignment(.center)
            } else {
                miniPawProgressRow()
            }
        }
    }

    private func miniPawProgressRow() -> some View {
        HStack(alignment: .center, spacing: 6) {
            ForEach(0..<5, id: \.self) { index in
                Image("fa_paw_solid")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .foregroundColor(index < miniPawCount ? compactWidgetAccent : Color(red: 0.91, green: 0.90, blue: 0.93))
            }
        }
    }

    private func twoLineStatusText(status: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .center, spacing: 5) {
                Image(miniStatusIconName)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 11, height: 11)
                    .foregroundColor(Color(red: 0.63, green: 0.55, blue: 1.0))

                Text(status)
                    .foregroundColor(compactWidgetAccent)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .lineLimit(1)
            }

            Text(title)
                .foregroundColor(Color(red: 0.15, green: 0.14, blue: 0.16))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private func compactStatusText(_ text: String) -> some View {
        HStack(alignment: .center, spacing: 5) {
            Image(miniStatusIconName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 11, height: 11)
                .foregroundColor(Color(red: 0.63, green: 0.55, blue: 1.0))

            Text(text)
                .foregroundColor(compactWidgetAccent)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .truncationMode(.tail)
        }
    }
}

struct NyangCharacterWidget: Widget {
    let kind: String = "NyangWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NyangProvider()) { entry in
            NyangCharacterWidgetView(entry: entry)
        }
        .configurationDisplayName("냥냥코치 가로 위젯")
        .description("오늘 가장 가까운 일정이나 남은 할 일을 고양이 코치와 함께 보여줍니다.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

struct NyangCompactWidget: Widget {
    let kind: String = "NyangCompactWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NyangProvider()) { entry in
            NyangCompactWidgetView(entry: entry)
        }
        .configurationDisplayName(compactWidgetTitle)
        .description(compactWidgetDescription)
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

extension View {
    @ViewBuilder
    func widgetBackground(_ colors: [Color]) -> some View {
        let fill = LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        if #available(iOSApplicationExtension 17.0, *) {
            containerBackground(for: .widget) {
                fill
            }
        } else {
            self.background(fill)
        }
    }

    @ViewBuilder
    func widgetClearBackground() -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            containerBackground(for: .widget) {
                Color.clear
            }
        } else {
            background(Color.clear)
        }
    }

    @ViewBuilder
    func widgetWhiteBackground() -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            containerBackground(for: .widget) {
                Color.white
            }
        } else {
            background(Color.white)
        }
    }

    @ViewBuilder
    func widgetCompactBackground() -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            containerBackground(for: .widget) {
                NyangCompactWidgetBackground()
            }
        } else {
            background(NyangCompactWidgetBackground())
        }
    }
}


#if canImport(ActivityKit)

// MARK: - 진행 중인 일정 (라이브 액티비티)

/// 아이폰에서는 다른 앱 위에 그릴 수 없다. 그래서 안드로이드처럼 잠깐 나타났다
/// 사라지는 대신, 일정이 도는 동안 잠금화면과 다이내믹 아일랜드에 조용히 머문다.
/// 소리도 진동도 없고, 눌러야만 앱으로 들어온다.
@available(iOSApplicationExtension 16.1, *)
struct NyangTaskLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NyangTaskActivityAttributes.self) { context in
            // 잠금화면과 알림센터에 보이는 모습.
            HStack(spacing: 12) {
                NyangLiveActivityCat(size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.taskText.isEmpty ? "진행 중인 일정" : context.state.taskText)
                        .font(.system(size: 15, weight: .bold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                    Text("진행 중")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(context.state.startedAt, style: .timer)
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(Color(red: 0.545, green: 0.486, blue: 1.0))
                    // 한 시간을 넘기면 "1:05:23"이 되어 자리가 모자란다. 줄여서라도 다 보여준다.
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    NyangLiveActivityCat(size: 36)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.startedAt, style: .timer)
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(Color(red: 0.545, green: 0.486, blue: 1.0))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: 88, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.taskText.isEmpty ? "진행 중인 일정" : context.state.taskText)
                        .font(.system(size: 15, weight: .bold))
                        .lineLimit(1)
                }
            } compactLeading: {
                NyangLiveActivityCat(size: 20)
            } compactTrailing: {
                // 알약에서 가장 좁은 자리다. 시간이 길어지면 글자를 줄여서 맞춘다.
                Text(context.state.startedAt, style: .timer)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(Color(red: 0.545, green: 0.486, blue: 1.0))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: 56)
            } minimal: {
                NyangLiveActivityCat(size: 18)
            }
        }
    }
}

/// 어느 코치를 쓰든 밖으로 나가는 얼굴은 냥냥이 하나다. 앱의 상징이라서다.
///
/// 얼굴만 잘라낸 그림을 따로 쓴다. 다이내믹 아일랜드에서는 20pt까지 작아지는데,
/// 몸통까지 든 그림을 그만큼 줄이면 얼굴이 뭉개져 무엇인지 알아볼 수 없다.
/// 위젯의 다른 냥냥이 그림에는 완료를 뜻하는 체크가 붙어 있어 여기 쓸 수 없다 —
/// 진행 중을 알리는 자리에서 뜻이 정반대가 된다.
struct NyangLiveActivityCat: View {
    let size: CGFloat

    var body: some View {
        // 동그랗게 오려내지 않는다. 배경이 없는 그림이라 그대로 두면 귀 끝까지
        // 살아 있고, 다이내믹 아일랜드의 검은 바탕 위에 그대로 얹힌다.
        Image("nyang_cat_face")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }
}

#endif

@main
struct NyangWidgetBundle: WidgetBundle {
    var body: some Widget {
        NyangCharacterWidget()
        NyangCompactWidget()
        #if canImport(ActivityKit)
        if #available(iOSApplicationExtension 16.1, *) {
            NyangTaskLiveActivity()
        }
        #endif
    }
}
