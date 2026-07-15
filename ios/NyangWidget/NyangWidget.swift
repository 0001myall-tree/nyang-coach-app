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
}

struct NyangProvider: TimelineProvider {
    func placeholder(in context: Context) -> NyangEntry {
        NyangEntry(
            date: Date(),
            scheduleTime: "17:00",
            scheduleTitle: "운동",
            remainingCount: 2,
            progress: 34,
            catMessage: "차근차근 간다냥!"
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

        return NyangEntry(
            date: Date(),
            scheduleTime: scheduleTime,
            scheduleTitle: scheduleTitle,
            remainingCount: remainingCount,
            progress: progress,
            catMessage: catMessage
        )
    }
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

    private var catImageName: String {
        switch min(max(entry.progress, 0), 100) {
        case 0:
            return "cat_widget1"
        case 100:
            return "cat_widget3"
        default:
            return "cat_widget2"
        }
    }

    private func makeMetrics(for size: CGSize) -> Metrics {
        let clampedWidth = max(size.width, 280)
        let isComplete = min(max(entry.progress, 0), 100) == 100
        let baseImageWidth = min(max(clampedWidth * 0.40, 140), isComplete ? 178 : 166)
        let imageWidth = clampedWidth < 330 ? min(baseImageWidth, 150) : baseImageWidth
        let imageHeight = imageWidth * 0.73
        let textTrailing = min(max(imageWidth * 0.72, 108), 140)
        let compact = clampedWidth < 330

        return Metrics(
            textLeading: compact ? 24 : 32,
            textTrailing: textTrailing,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            imageTrailing: compact ? 10 : 16,
            imageCenterYRatio: 0.52,
            checkSize: compact ? 34 : 40,
            checkTrailing: compact ? 13 : 18,
            checkCenterYRatio: 0.64,
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
                        widgetText(timeFontSize: metrics.timeFontSize, titleFontSize: metrics.titleFontSize)
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

                    Text(entry.scheduleTitle)
                        .foregroundColor(.white)
                        .font(.system(size: titleFontSize, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
            } else {
                if hasNoTodayItems {
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
}

struct NyangCompactWidgetView: View {
    let entry: NyangEntry

    private var hasTimedSchedule: Bool {
        !entry.scheduleTime.isEmpty && !entry.scheduleTitle.isEmpty
    }

    private var catImageName: String {
        let progress = min(max(entry.progress, 0), 100)
        if progress > 80 {
            return "iphonecatwidget3"
        }
        if progress > 30 {
            return "iphonecatwidget2"
        }
        return "iphonecatwidget1"
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
                let bottomPadding: CGFloat = 14
                let horizontalPadding = min(max(proxy.size.width * 0.08, 12), 16)
                let textCenterY = proxy.size.height - bottomPadding - textHeight / 2
                let imageAreaHeight = max(textCenterY - textHeight / 2 - imageTextGap - topPadding, 1)
                let imageSize = min(proxy.size.width * 0.96, imageAreaHeight)
                let imageCenterY = topPadding + imageSize / 2

                Image(catImageName)
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
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                HStack(alignment: .firstTextBaseline, spacing: 13) {
                    Text(entry.scheduleTime)
                        .foregroundColor(compactWidgetAccent)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)

                    Text(entry.scheduleTitle)
                        .foregroundColor(Color(red: 0.15, green: 0.14, blue: 0.16))
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .minimumScaleFactor(0.78)
                }
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
