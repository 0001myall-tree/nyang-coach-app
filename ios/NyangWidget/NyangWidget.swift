import SwiftUI
import WidgetKit

private let appGroupId = "group.com.nyang.nyangCoach"

struct NyangEntry: TimelineEntry {
    let date: Date
    let scheduleTime: String
    let scheduleTitle: String
    let remainingCount: Int
    let progress: Int
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
            catMessage: catMessage,
            isVacation: isVacation,
            lastOpenedAt: lastOpenedAt
        )
    }
}

private func truncatedScheduleTitle(_ title: String, limit: Int = 10) -> String {
    title.count > limit ? String(title.prefix(limit)) + "…" : title
}

private let compactWidgetTitle = "냥냥코치 미니 위젯"
private let compactWidgetDescription = "오늘 목표와 남은 할 일을 냥냥코치 위젯으로 확인합니다."
private let compactWidgetAccent = Color(red: 0.55, green: 0.49, blue: 1.0)

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
        let checkSize: CGFloat
        let checkTrailing: CGFloat
        let checkCenterYRatio: CGFloat
        let timeFontSize: CGFloat
        let titleFontSize: CGFloat
    }

    private var hasTimedSchedule: Bool {
        !entry.scheduleTime.isEmpty && !entry.scheduleTitle.isEmpty
    }

    private var hasNoTodayItems: Bool {
        entry.remainingCount == 0 && min(max(entry.progress, 0), 100) == 0
    }

    /// 시간 일정 없이 24시간 이상 미접속이라 "집사, 보고싶다옹...."을 띄우는 상태.
    /// 이때는 일정 보기 버튼도 숨긴다.
    private var showsMissYouMessage: Bool {
        !hasTimedSchedule && isAwayOverDay(entry)
    }

    private var catImageName: String {
        nyangCatImageName(for: entry)
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
            checkSize: compact ? 32 : 38,
            checkTrailing: compact ? 12 : 16,
            checkCenterYRatio: 0.72,
            timeFontSize: compact ? 18 : 20,
            titleFontSize: compact ? 16 : 18
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

                ZStack(alignment: .bottomTrailing) {
                    HStack {
                        VStack(alignment: .leading, spacing: 14) {
                            widgetText(
                                timeFontSize: metrics.timeFontSize,
                                titleFontSize: metrics.titleFontSize
                            )
                            if !showsMissYouMessage {
                                scheduleButton
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

                    ZStack {
                        Text("✓")
                            .font(.system(size: metrics.checkSize + 8, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                            .shadow(color: Color.black.opacity(0.18), radius: 3, x: 0, y: 2)

                        Text("✓")
                            .font(.system(size: metrics.checkSize, weight: .heavy, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.64, green: 0.54, blue: 1.0),
                                        Color(red: 0.47, green: 0.38, blue: 0.92),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .rotationEffect(.degrees(-3))
                    .position(
                        x: proxy.size.width - metrics.checkTrailing - (metrics.checkSize / 2),
                        y: proxy.size.height * metrics.checkCenterYRatio
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
            if hasTimedSchedule {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 5) {
                        Image("fa_clock_solid")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: timeFontSize * 0.78, height: timeFontSize * 0.78)
                            .foregroundColor(Color(red: 0.63, green: 0.55, blue: 1.0))

                        Text(entry.scheduleTime)
                            .foregroundColor(Color(red: 0.55, green: 0.49, blue: 1.0))
                            .font(.system(size: timeFontSize, weight: .bold, design: .rounded))
                            .lineLimit(1)
                    }

                    Text(truncatedScheduleTitle(entry.scheduleTitle))
                        .foregroundColor(.white)
                        .font(.system(size: titleFontSize, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
            } else {
                if isAwayOverDay(entry) {
                    Text("집사,\n보고싶다옹....")
                        .foregroundColor(.white)
                        .font(.system(size: titleFontSize, weight: .bold, design: .rounded))
                        .lineLimit(2)
                        .lineSpacing(3)
                        .multilineTextAlignment(.leading)
                        .minimumScaleFactor(0.82)
                } else if hasNoTodayItems {
                    Text("집사야 오늘 뭐할까?")
                        .foregroundColor(.white)
                        .font(.system(size: titleFontSize, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                } else {
                    (Text("오늘 할 일 ")
                        .foregroundColor(.white)
                     + Text("\(entry.remainingCount)")
                        .foregroundColor(Color(red: 0.55, green: 0.49, blue: 1.0))
                     + Text("개 남음")
                        .foregroundColor(.white))
                        .font(.system(size: titleFontSize, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
            }
        }
    }

    private var scheduleButton: some View {
        HStack(spacing: 7) {
            Text("+")
                .font(.system(size: 19, weight: .regular, design: .rounded))
                .offset(y: -1)

            Text("일정 보기")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Text("›")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .offset(y: -1)
        }
        .foregroundColor(.white)
        .frame(width: 116, height: 32)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.36), lineWidth: 1.4)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
        )
    }
}

struct NyangCompactWidgetView: View {
    let entry: NyangEntry

    private var hasTimedSchedule: Bool {
        !entry.scheduleTime.isEmpty && !entry.scheduleTitle.isEmpty
    }

    private var catImageName: String {
        nyangCatImageName(for: entry)
    }

    var body: some View {
        Link(destination: URL(string: "nyangcoach://widget/cat/tasks")!) {
            compactContent
        }
    }

    private var compactContent: some View {
        ZStack(alignment: .topLeading) {
            Color.white

            GeometryReader { proxy in
                let textHeight: CGFloat = 26
                let topPadding: CGFloat = 4
                let imageTextGap: CGFloat = 6
                let bottomPadding: CGFloat = 18
                let horizontalPadding = min(max(proxy.size.width * 0.08, 12), 16)
                let textCenterY = proxy.size.height - bottomPadding - textHeight / 2
                let imageAreaHeight = max(textCenterY - textHeight / 2 - imageTextGap - topPadding, 1)
                let imageSize = min(proxy.size.width * 0.96, imageAreaHeight)
                let imageCenterY = topPadding + imageSize / 2

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
                        alignment: .center
                    )
                    .frame(height: textHeight)
                    .position(
                        x: proxy.size.width / 2,
                        y: textCenterY
                    )
                    .padding(.horizontal, horizontalPadding)
            }
        }
        .widgetWhiteBackground()
        .unredacted()
    }

    private var miniText: some View {
        Group {
            if hasTimedSchedule {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(entry.scheduleTime)
                        .foregroundColor(compactWidgetAccent)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)

                    Text(truncatedScheduleTitle(entry.scheduleTitle))
                        .foregroundColor(Color(red: 0.15, green: 0.14, blue: 0.16))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .minimumScaleFactor(0.78)
                }
            } else if isAwayOverDay(entry) {
                Text("집사 보고싶다옹...")
                    .foregroundColor(Color(red: 0.15, green: 0.14, blue: 0.16))
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .multilineTextAlignment(.center)
            } else {
                (Text("남은 일정 ")
                    .foregroundColor(Color(red: 0.15, green: 0.14, blue: 0.16))
                 + Text("\(entry.remainingCount)")
                    .foregroundColor(compactWidgetAccent)
                 + Text("개")
                    .foregroundColor(Color(red: 0.15, green: 0.14, blue: 0.16)))
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .multilineTextAlignment(.center)
            }
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
}

@main
struct NyangWidgetBundle: WidgetBundle {
    var body: some Widget {
        NyangCharacterWidget()
        NyangCompactWidget()
    }
}
