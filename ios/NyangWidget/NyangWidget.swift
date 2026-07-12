import SwiftUI
import WidgetKit

private let appGroupId = "group.com.nyang.nyangCoach"

struct NyangEntry: TimelineEntry {
    let date: Date
    let scheduleTime: String
    let scheduleTitle: String
    let remainingCount: Int
    let progress: Int
    let masterAccess: Bool
    let catMessage: String
    let secMaleMessage: String
    let secFemaleMessage: String
}

struct NyangProvider: TimelineProvider {
    func placeholder(in context: Context) -> NyangEntry {
        NyangEntry(
            date: Date(),
            scheduleTime: "17:00",
            scheduleTitle: "운동",
            remainingCount: 2,
            progress: 34,
            masterAccess: true,
            catMessage: "차근차근 간다냥!",
            secMaleMessage: "차근차근 좋습니다.",
            secFemaleMessage: "충분히 해낼 수 있어요."
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
        let masterAccess = defaults.object(forKey: "master_widget_access") as? Bool ?? Bool(defaults.string(forKey: "master_widget_access") ?? "") ?? false
        let catMessage = defaults.string(forKey: "coach_message_cat") ?? "오늘도 시작해보자냥!"
        let secMaleMessage = defaults.string(forKey: "coach_message_sec_male") ?? "오늘도 함께 해보시죠."
        let secFemaleMessage = defaults.string(forKey: "coach_message_sec_female") ?? "오늘도 응원할게요."

        return NyangEntry(
            date: Date(),
            scheduleTime: scheduleTime,
            scheduleTitle: scheduleTitle,
            remainingCount: remainingCount,
            progress: progress,
            masterAccess: masterAccess,
            catMessage: catMessage,
            secMaleMessage: secMaleMessage,
            secFemaleMessage: secFemaleMessage
        )
    }
}

enum CompactWidgetStyle {
    case cat
    case secMale
    case secFemale

    var title: String {
        switch self {
        case .cat: return "냥냥코치 기본"
        case .secMale: return "남비서 코치"
        case .secFemale: return "여비서 코치"
        }
    }

    var description: String {
        switch self {
        case .cat: return "오늘 목표와 남은 할 일을 냥냥코치 위젯으로 확인합니다."
        case .secMale: return "남비서 코치 위젯으로 오늘 진행률을 확인합니다."
        case .secFemale: return "여비서 코치 위젯으로 오늘 진행률을 확인합니다."
        }
    }

    var accent: Color {
        switch self {
        case .cat: return Color(red: 0.55, green: 0.49, blue: 1.0)
        case .secMale: return Color(red: 0.65, green: 0.65, blue: 0.84)
        case .secFemale: return Color(red: 0.77, green: 0.66, blue: 0.90)
        }
    }

    var background: [Color] {
        switch self {
        case .cat:
            return [
                Color(red: 0.20, green: 0.15, blue: 0.36),
                Color(red: 0.14, green: 0.11, blue: 0.28),
            ]
        case .secMale:
            return [
                Color(red: 0.17, green: 0.17, blue: 0.32),
                Color(red: 0.11, green: 0.12, blue: 0.24),
            ]
        case .secFemale:
            return [
                Color(red: 0.98, green: 0.95, blue: 1.0),
                Color(red: 0.91, green: 0.87, blue: 0.98),
            ]
        }
    }

    var textColor: Color {
        switch self {
        case .secFemale: return Color(red: 0.35, green: 0.29, blue: 0.45)
        default: return Color(red: 0.96, green: 0.95, blue: 1.0)
        }
    }

    var messageIcon: String {
        switch self {
        case .cat: return "sparkles"
        case .secMale: return "cup.and.saucer.fill"
        case .secFemale: return "heart.fill"
        }
    }

    func message(from entry: NyangEntry) -> String {
        switch self {
        case .cat:
            return entry.catMessage
        case .secMale:
            return entry.masterAccess ? entry.secMaleMessage : "마스터 플랜 전용 위젯입니다."
        case .secFemale:
            return entry.masterAccess ? entry.secFemaleMessage : "마스터 플랜 전용 위젯이에요."
        }
    }

    func remainingCount(from entry: NyangEntry) -> Int {
        switch self {
        case .cat:
            return entry.remainingCount
        case .secMale, .secFemale:
            return entry.masterAccess ? entry.remainingCount : 0
        }
    }

    func progress(from entry: NyangEntry) -> Int {
        switch self {
        case .cat:
            return entry.progress
        case .secMale, .secFemale:
            return entry.masterAccess ? entry.progress : 0
        }
    }
}

struct NyangCharacterWidgetView: View {
    let entry: NyangEntry

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

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.20, green: 0.15, blue: 0.36),
                            Color(red: 0.14, green: 0.11, blue: 0.28),
                            Color(red: 0.09, green: 0.08, blue: 0.19),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color(red: 0.44, green: 0.33, blue: 0.78), lineWidth: 1.2)
                )
                .shadow(color: Color.black.opacity(0.30), radius: 10, x: 0, y: 6)
                .padding(.horizontal, 8)
                .padding(.top, 30)
                .padding(.bottom, 8)

            HStack {
                widgetText
                    .padding(.leading, 28)
                    .padding(.trailing, 145)
                    .padding(.top, 34)
                    .padding(.bottom, 12)
                Spacer(minLength: 0)
            }

            Image(catImageName)
                .resizable()
                .scaledToFit()
                .frame(width: entry.progress >= 100 ? 178 : 162, height: entry.progress >= 100 ? 130 : 122)
                .offset(x: 2, y: entry.progress >= 100 ? 0 : 2)
                .accessibilityHidden(true)
        }
        .widgetClearBackground()
    }

    private var widgetText: some View {
        Group {
            if hasTimedSchedule {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.scheduleTime)
                        .foregroundColor(Color(red: 0.55, green: 0.49, blue: 1.0))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .lineLimit(1)

                    Text(entry.scheduleTitle)
                        .foregroundColor(.white)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
            } else {
                if hasNoTodayItems {
                    Text("집사야 오늘 뭐할까?")
                        .foregroundColor(.white)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                } else {
                    (Text("오늘 할 일 ")
                        .foregroundColor(.white)
                     + Text("\(entry.remainingCount)")
                        .foregroundColor(Color(red: 0.55, green: 0.49, blue: 1.0))
                     + Text("개 남음")
                        .foregroundColor(.white))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
            }
        }
    }
}

struct NyangCompactWidgetView: View {
    let entry: NyangEntry
    let style: CompactWidgetStyle

    private var progressValue: Double {
        min(max(Double(style.progress(from: entry)) / 100.0, 0.0), 1.0)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: style.background,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(style.accent.opacity(0.55), lineWidth: 1.1)
                )
                .shadow(color: style.accent.opacity(0.18), radius: 12, x: 0, y: 6)

            VStack(spacing: 16) {
                HStack(spacing: 8) {
                    Text(style.message(from: entry))
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(style.textColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Image(systemName: style.messageIcon)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(style.accent)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(style.accent.opacity(style == .secFemale ? 0.20 : 0.28))
                        Capsule()
                            .fill(style.accent)
                            .frame(width: max(8, proxy.size.width * progressValue))
                    }
                }
                .frame(height: 8)

                HStack(spacing: 12) {
                    compactPill(
                        text: "\(style.remainingCount(from: entry))개 남음",
                        systemImage: "chevron.right",
                        outlined: true
                    )
                    compactPill(
                        text: "코치와 대화",
                        systemImage: "ellipsis.message.fill",
                        outlined: false
                    )
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
        }
        .widgetClearBackground()
    }

    private func compactPill(text: String, systemImage: String, outlined: Bool) -> some View {
        HStack(spacing: 7) {
            if !outlined {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .bold))
            }
            Text(text)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            if outlined {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .bold))
            }
        }
        .foregroundColor(outlined ? style.textColor : Color.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(outlined ? Color.clear : style.accent.opacity(0.35))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(style.accent.opacity(outlined ? 0.78 : 0.0), lineWidth: 1.1)
        )
    }
}

struct NyangCharacterWidget: Widget {
    let kind: String = "NyangWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NyangProvider()) { entry in
            NyangCharacterWidgetView(entry: entry)
        }
        .configurationDisplayName("캐릭터")
        .description("오늘 가장 가까운 일정이나 남은 할 일을 고양이 코치와 함께 보여줍니다.")
        .supportedFamilies([.systemMedium])
    }
}

struct NyangCompactWidget: Widget {
    let kind: String = "NyangCompactWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NyangProvider()) { entry in
            NyangCompactWidgetView(entry: entry, style: .cat)
        }
        .configurationDisplayName(CompactWidgetStyle.cat.title)
        .description(CompactWidgetStyle.cat.description)
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct SecMaleCompactWidget: Widget {
    let kind: String = "SecMaleWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NyangProvider()) { entry in
            NyangCompactWidgetView(entry: entry, style: .secMale)
        }
        .configurationDisplayName(CompactWidgetStyle.secMale.title)
        .description(CompactWidgetStyle.secMale.description)
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct SecFemaleCompactWidget: Widget {
    let kind: String = "SecFemaleWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NyangProvider()) { entry in
            NyangCompactWidgetView(entry: entry, style: .secFemale)
        }
        .configurationDisplayName(CompactWidgetStyle.secFemale.title)
        .description(CompactWidgetStyle.secFemale.description)
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

extension View {
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
}

@main
struct NyangWidgetBundle: WidgetBundle {
    var body: some Widget {
        NyangCharacterWidget()
        NyangCompactWidget()
        SecMaleCompactWidget()
        SecFemaleCompactWidget()
    }
}
